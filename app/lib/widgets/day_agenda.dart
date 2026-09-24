import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';

import 'package:entrelares_db_contracts/models/child.dart';
import 'package:entrelares_db_contracts/models/child_event.dart';
import 'package:entrelares_db_contracts/models/child_routine.dart';
import 'package:entrelares_db_contracts/models/member.dart';
import '../services/custody_data_source.dart';
import '../theme/tokens.dart';
import 'app_l10n.dart';
import 'app_snack.dart';
import 'ui/ui.dart';

/// F-55 — the day's agenda, inside the day sheet.
///
/// The agenda REPLACES the Observação do dia (owner, 24/09/2026): with
/// `feature.child_agenda` on, the sheet shows this section where the note used
/// to be, and the note became the agenda's "Nota". It is coordination, not
/// custody: nothing here touches the day's carer, freezes it or enters the
/// swap workflow, so it lives beside the day's form and never inside its save.
///
/// Who writes is the server's: an active member, today on, the Premium gate,
/// the free note cap. The section only decides what to OFFER — a door the
/// server would refuse is not shown, and a refusal it still sends is said in
/// its own words.
class DayAgendaSection extends StatefulWidget {
  final DateTime date;
  final DateTime today;
  final CustodyDataSource dataSource;
  final PublicSettings settings;

  /// null = entitlement unknown: the free-plan line is skipped and the
  /// server's own refusal speaks, never a wrongful client-side block.
  final bool? isPremium;
  final Member? me;

  /// Every profile, departed included — a byline may name someone who left.
  final List<Member> allProfiles;
  final bool offline;

  /// Opens `/family/plan` — every Premium gate CTA lands there (U-35).
  final VoidCallback? onOpenPlan;

  const DayAgendaSection({
    super.key,
    required this.date,
    required this.today,
    required this.dataSource,
    required this.settings,
    required this.isPremium,
    required this.me,
    required this.allProfiles,
    this.offline = false,
    this.onOpenPlan,
  });

  @override
  State<DayAgendaSection> createState() => _DayAgendaSectionState();
}

class _DayAgendaSectionState extends State<DayAgendaSection> {
  List<ChildEvent>? _events;
  List<Child> _children = const [];
  List<ChildRoutine> _routines = const [];
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        widget.dataSource.fetchChildEvents(widget.date, widget.date),
        widget.dataSource.fetchChildren(),
        widget.dataSource.fetchChildRoutines(),
      ]);
      if (!mounted) return;
      setState(() {
        _events = results[0] as List<ChildEvent>;
        _children = results[1] as List<Child>;
        _routines = results[2] as List<ChildRoutine>;
        _failed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _events = const [];
        _failed = true;
      });
    }
  }

  bool get _dayWritable =>
      AgendaRules.canWriteDay(widget.date, widget.today) &&
      !widget.offline &&
      widget.me != null &&
      !widget.me!.hasLeft &&
      // F-50: a Visualizador reads the agenda and writes nothing.
      !widget.me!.isViewer;

  bool get _freeLimited => AgendaRules.freeLimited(
      isPremium: widget.isPremium ?? true,
      premiumOnly: widget.settings.agendaPremiumOnly);

  List<ChildEvent> get _live => AgendaRules.timeline(
        [for (final e in _events ?? const <ChildEvent>[]) if (!e.isDeleted) e],
        (e) => AgendaEntry(
          id: e.id,
          kind: AgendaKind.parse(e.kind) ?? AgendaKind.other,
          start: e.startTime,
          end: e.endTime,
          createdAt: e.createdAt,
        ),
      );

  int get _notesToday =>
      _live.where((e) => e.kind == AgendaKind.note.wire).length;

  /// A limited family with its notes used offers no add door at all: the
  /// only thing it could add is a note, and the server would refuse it.
  bool get _canAdd {
    if (!_dayWritable) return false;
    if (_live.length >= widget.settings.agendaMaxEventsPerDay) return false;
    if (_freeLimited &&
        AgendaRules.notesLeft(
                notesOnDay: _notesToday,
                freeNotesPerDay: widget.settings.agendaFreeNotesPerDay) ==
            0) {
      return false;
    }
    return true;
  }

  bool _canChange(ChildEvent e) =>
      _dayWritable &&
      AgendaRules.canChange(
        kind: AgendaKind.parse(e.kind) ?? AgendaKind.other,
        day: e.eventDate,
        today: widget.today,
        freeLimited: _freeLimited,
      );

  /// The running routine [e] still belongs to (a hand edit left it).
  ChildRoutine? _routineOf(ChildEvent e) =>
      _routines.where((r) => r.id == e.batchId).firstOrNull;

  Future<void> _openEditor(Localization l, {ChildEvent? event}) async {
    // The sheet says what it did, in one sentence — a routine's reads
    // differently from a single item's.
    final done = await showAppSheet<String>(
      context: context,
      builder: (_) => AgendaEventSheet(
        date: widget.date,
        event: event,
        routine: event == null ? null : _routineOf(event),
        children: _children,
        settings: widget.settings,
        freeLimited: _freeLimited,
        isAdmin: widget.me?.isAdmin == true,
        dataSource: widget.dataSource,
      ),
    );
    if (done == null || !mounted) return;
    showAppSnack(context, done);
    await _load();
  }

  String? _byline(Localization l, ChildEvent e) {
    if (e.sourceScheduleId != null && e.createdBy == null) {
      return l[KApp.agendaFromObservation];
    }
    final name = widget.allProfiles
        .where((m) => m.id == e.createdBy)
        .map((m) => m.fullName)
        .firstOrNull;
    return name == null ? null : l.format(KApp.agendaBy, [name]);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context).l;
    final textTheme = Theme.of(context).textTheme;
    final tokens = context.tokens;
    final events = _events;
    final live = _live;
    final freeNotes = widget.settings.agendaFreeNotesPerDay;

    return Column(
      key: const ValueKey('day-agenda'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: Spacing.md),
        Text(l[KApp.agendaSection],
            style: textTheme.labelMedium?.copyWith(color: tokens.textMuted)),
        const SizedBox(height: Spacing.xs),
        if (events == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: Spacing.sm),
            child: LinearProgressIndicator(),
          )
        else if (_failed)
          Text(l[KApp.agendaErrLoad],
              style: textTheme.bodySmall?.copyWith(color: tokens.textMuted))
        else if (live.isEmpty)
          Text(l[KApp.agendaEmpty],
              key: const ValueKey('day-agenda-empty'),
              style: textTheme.bodyMedium?.copyWith(color: tokens.textMuted))
        else ...[
          for (final e in live) _entry(l, e),
          // A family that lapsed keeps its Premium items; say why they have
          // no pencil instead of leaving the reader to guess.
          if (_dayWritable &&
              _freeLimited &&
              live.any((e) =>
                  (AgendaKind.parse(e.kind) ?? AgendaKind.other).isStructured))
            Text(l[KApp.agendaReadOnlyPremium],
                key: const ValueKey('day-agenda-read-only-premium'),
                style:
                    textTheme.bodySmall?.copyWith(color: tokens.textMuted)),
        ],
        if (events != null && !_failed) ...[
          if (_canAdd)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                key: const ValueKey('day-agenda-add'),
                onPressed: () => _openEditor(l),
                icon: const Icon(Icons.add),
                label: Text(l[KApp.agendaAdd]),
              ),
            ),
          if (!AgendaRules.canWriteDay(widget.date, widget.today))
            Text(l[KApp.agendaReadOnlyPast],
                style: textTheme.bodySmall?.copyWith(color: tokens.textMuted))
          else if (_dayWritable && _freeLimited) ...[
            const SizedBox(height: Spacing.xs),
            AppBanner(
              key: const ValueKey('day-agenda-free'),
              tone: tokens.info,
              icon: Icons.workspace_premium_outlined,
              message: l.format(
                  freeNotes == 1
                      ? KApp.agendaFreeNotesOne
                      : KApp.agendaFreeNotesMany,
                  [freeNotes]),
              actionLabel:
                  widget.onOpenPlan == null ? null : l[K.famSeePremium],
              onAction: widget.onOpenPlan,
            ),
          ],
        ],
      ],
    );
  }

  static IconData _icon(AgendaKind kind) => switch (kind) {
        AgendaKind.school => Icons.school_outlined,
        AgendaKind.health => Icons.local_hospital_outlined,
        AgendaKind.medicine => Icons.medication_outlined,
        AgendaKind.activity => Icons.sports_soccer_outlined,
        AgendaKind.free => Icons.wb_sunny_outlined,
        AgendaKind.note => Icons.sticky_note_2_outlined,
        AgendaKind.other => Icons.event_note_outlined,
      };

  Widget _entry(Localization l, ChildEvent e) {
    final textTheme = Theme.of(context).textTheme;
    final tokens = context.tokens;
    final kind = AgendaKind.parse(e.kind) ?? AgendaKind.other;
    final child =
        _children.where((c) => c.id == e.childId).map((c) => c.firstName);
    final head = [
      ?AgendaRules.timeRange(e.startTime, e.endTime),
      l[kind.labelKey],
      ...child,
    ].join(' · ');
    final byline = _byline(l, e);
    final canChange = _canChange(e);
    return Padding(
      key: ValueKey('day-agenda-entry-${e.id}'),
      padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(_icon(kind), size: 20, color: tokens.textMuted),
          ),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(head, style: textTheme.titleSmall),
                if (e.body != null) Text(e.body!, style: textTheme.bodyMedium),
                if (byline != null)
                  Text(byline,
                      style: textTheme.bodySmall
                          ?.copyWith(color: tokens.textMuted)),
                if (_routineOf(e) case final r?)
                  Text(
                      l.format(KApp.agendaRoutinePart, [
                        AgendaRules.weekdaysLabel(r.weekdays, l.weekdayAbbrev)
                      ]),
                      key: ValueKey('day-agenda-routine-${e.id}'),
                      style: textTheme.bodySmall
                          ?.copyWith(color: tokens.textMuted)),
              ],
            ),
          ),
          if (canChange)
            IconButton(
              key: ValueKey('day-agenda-edit-${e.id}'),
              icon: const Icon(Icons.edit_outlined),
              tooltip: l[KApp.agendaEditTitle],
              onPressed: () => _openEditor(l, event: e),
            ),
        ],
      ),
    );
  }
}

/// The editor of one agenda item — new, or [event] to edit. Stacks on top of
/// the day sheet; a refusal keeps it open with the server's sentence. Pops
/// with the sentence the snack says.
///
/// F-55 PR 3: a new item may repeat every week until the end of the plan (a
/// routine); an item of a running [routine] offers to edit the routine from
/// this day on, or to stop it.
class AgendaEventSheet extends StatefulWidget {
  final DateTime date;
  final ChildEvent? event;
  final ChildRoutine? routine;
  final List<Child> children;
  final PublicSettings settings;
  final bool freeLimited;
  final bool isAdmin;
  final CustodyDataSource dataSource;

  const AgendaEventSheet({
    super.key,
    required this.date,
    required this.event,
    required this.children,
    required this.settings,
    required this.freeLimited,
    required this.isAdmin,
    required this.dataSource,
    this.routine,
  });

  @override
  State<AgendaEventSheet> createState() => _AgendaEventSheetState();
}

class _AgendaEventSheetState extends State<AgendaEventSheet> {
  late AgendaKind _kind =
      AgendaKind.parse(widget.event?.kind) ?? AgendaKind.note;
  late int? _childId = widget.event?.childId ??
      (widget.children.length == 1 ? widget.children.single.id : null);
  late String? _start = widget.event?.startTime;
  late String? _end = widget.event?.endTime;
  late final TextEditingController _body =
      TextEditingController(text: widget.event?.body ?? '');

  /// F-55 PR 4: who is told, on which channels, and the reminder.
  late AgendaAudience _notifyTo = AgendaAudience.parse(widget.event?.notifyTo);
  late bool _notifyPush = widget.event?.notifyPush ?? true;
  late bool _notifyInApp = widget.event?.notifyInApp ?? true;
  late int? _remind = widget.event?.remindMinutes;
  String? _error;
  bool _busy = false;
  bool _confirmingDelete = false;

  /// A new item that repeats, or an existing routine being edited.
  bool _repeat = false;
  bool _editingRoutine = false;
  late Set<int> _weekdays = {widget.date.weekday};

  /// Switches the sheet to the routine's own fields, from this day on.
  void _editRoutine(ChildRoutine r) => setState(() {
        _editingRoutine = true;
        _confirmingDelete = false;
        _kind = AgendaKind.parse(r.kind) ?? AgendaKind.other;
        _childId = r.childId;
        _start = r.startTime;
        _end = r.endTime;
        _body.text = r.body ?? '';
        _weekdays = r.weekdays.toSet();
        _notifyTo = AgendaAudience.parse(r.notifyTo);
        _notifyPush = r.notifyPush;
        _notifyInApp = r.notifyInApp;
        _remind = r.remindMinutes;
        _error = null;
      });

  AgendaNotify get _notify => AgendaNotify(
        to: _notifyTo,
        push: _notifyPush,
        inApp: _notifyInApp,
        remindMinutes: _remind,
      ).normalized(start: _start);

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  /// A limited family is offered the note only — the rest would be refused.
  List<AgendaKind> get _offered => widget.freeLimited
      ? const [AgendaKind.note]
      : AgendaRules.pickerOrder;

  Future<void> _pickTime({required bool start}) async {
    final current = start ? _start : _end;
    final parts = (current ?? (start ? '08:00' : _start ?? '09:00')).split(':');
    final picked = await showTimePicker(
      context: context,
      initialTime:
          TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1])),
    );
    if (picked == null || !mounted) return;
    final hm = '${picked.hour.toString().padLeft(2, '0')}:'
        '${picked.minute.toString().padLeft(2, '0')}';
    setState(() {
      if (start) {
        _start = hm;
      } else {
        _end = hm;
      }
      _error = null;
    });
  }

  Future<void> _run(Localization l, Future<String> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final done = await action();
      if (!mounted) return;
      Navigator.of(context).pop(done);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _confirmingDelete = false;
        _error = translateSaveError(e.toString(), l[K.errSaveFailed], l);
      });
    }
  }

  void _save(Localization l) {
    final childId = _kind.isStructured ? _childId : null;
    final error = AgendaRules.validate(
      kind: _kind,
      childId: childId,
      start: _start,
      end: _end,
      body: _body.text,
      maxChars: widget.settings.agendaTextMaxChars,
    );
    final notifyError = _notify.validate(start: _start);
    if (error != null || notifyError != null) {
      setState(() => _error = error ?? notifyError);
      return;
    }
    final notify = _notify;
    final event = widget.event;
    if (_repeat || _editingRoutine) {
      if (_weekdays.isEmpty) {
        setState(() => _error = AgendaRules.noWeekday);
        return;
      }
      _run(l, () async {
        final r = await widget.dataSource.saveChildRoutine(
          routineId: _editingRoutine ? widget.routine?.id : null,
          from: widget.date,
          kind: _kind.wire,
          weekdays: (_weekdays.toList()..sort()),
          childId: childId,
          start: _start,
          end: _end,
          body: _body.text,
          notify: notify,
        );
        return l.format(
            KApp.agendaRoutineApplied, [r.created, l.formatDate(r.until)]);
      });
      return;
    }
    _run(l, () async {
      if (event == null) {
        await widget.dataSource.addChildEvent(
          date: widget.date,
          kind: _kind.wire,
          childId: childId,
          start: _start,
          end: _end,
          body: _body.text,
          notify: notify,
        );
      } else {
        await widget.dataSource.updateChildEvent(
          id: event.id,
          date: widget.date,
          kind: _kind.wire,
          childId: childId,
          start: _start,
          end: _end,
          body: _body.text,
          notify: notify,
        );
      }
      return l[KApp.agendaSaved];
    });
  }

  Widget _weekdayPicker(Localization l) {
    final textTheme = Theme.of(context).textTheme;
    final tokens = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l[KApp.agendaRepeatDays],
            style: textTheme.labelMedium?.copyWith(color: tokens.textMuted)),
        const SizedBox(height: Spacing.xs),
        Wrap(
          spacing: Spacing.xs,
          runSpacing: Spacing.xs,
          children: [
            for (var w = 1; w <= 7; w++)
              FilterChip(
                key: ValueKey('agenda-weekday-$w'),
                label: Text(l.weekdayAbbrev(w)),
                selected: _weekdays.contains(w),
                onSelected: _busy
                    ? null
                    : (on) => setState(() {
                          on ? _weekdays.add(w) : _weekdays.remove(w);
                          _error = null;
                        }),
              ),
          ],
        ),
        const SizedBox(height: Spacing.xs),
        Text(
            l.format(
                _editingRoutine
                    ? KApp.agendaRoutineEditLead
                    : KApp.agendaRepeatLead,
                [l.formatDate(widget.date)]),
            style: textTheme.bodySmall?.copyWith(color: tokens.textMuted)),
      ],
    );
  }

  Widget _timeButton(Localization l,
      {required bool start, required String? value}) {
    return OutlinedButton.icon(
      key: ValueKey(start ? 'agenda-start' : 'agenda-end'),
      onPressed: _busy ? null : () => _pickTime(start: start),
      icon: const Icon(Icons.schedule),
      label: Text(
          '${l[start ? KApp.agendaStartLabel : KApp.agendaEndLabel]}: '
          '${value ?? l[KApp.agendaNoTime]}'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context).l;
    final textTheme = Theme.of(context).textTheme;
    final tokens = context.tokens;
    final event = widget.event;
    final routine = widget.routine;
    if (_editingRoutine && routine != null) {
      return _routineFrame(l, routine);
    }
    return AppSheetFrame(
      title: l[event == null ? KApp.agendaNewTitle : KApp.agendaEditTitle],
      busy: _busy,
      error: _error,
      primaryLabel: l[K.commonSave],
      onPrimary: () => _save(l),
      secondaryLabel: l[K.commonCancel],
      onSecondary: () => Navigator.of(context).pop(),
      extraAction: event == null
          ? null
          : AppSheetDangerAction(
              key: const ValueKey('agenda-delete'),
              label: l[KApp.agendaDelete],
              icon: Icons.delete_outline,
              onPressed: _busy
                  ? null
                  : () => setState(() => _confirmingDelete = true),
            ),
      confirmation: event == null || !_confirmingDelete
          ? null
          : AppSheetConfirmation.destructive(
              key: const ValueKey('agenda-delete-confirm'),
              message: l[KApp.agendaDeleteConfirm],
              yesLabel: l[KApp.agendaDelete],
              onYes: () => _run(l, () async {
                await widget.dataSource.deleteChildEvent(event.id);
                return l[KApp.agendaDeleted];
              }),
              noLabel: l[K.commonCancel],
              onNo: () => setState(() => _confirmingDelete = false),
              busy: _busy,
            ),
      children: [
        if (routine != null) ...[
          Text(
              l.format(KApp.agendaRoutinePart, [
                AgendaRules.weekdaysLabel(routine.weekdays, l.weekdayAbbrev)
              ]),
              style: textTheme.bodySmall?.copyWith(color: tokens.textMuted)),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              key: const ValueKey('agenda-routine-edit'),
              onPressed: _busy ? null : () => _editRoutine(routine),
              icon: const Icon(Icons.event_repeat_outlined),
              label: Text(l[KApp.agendaRoutineEdit]),
            ),
          ),
          const SizedBox(height: Spacing.sm),
        ],
        ..._fields(l),
        if (event == null) ...[
          const SizedBox(height: Spacing.sm),
          SwitchListTile(
            key: const ValueKey('agenda-repeat'),
            contentPadding: EdgeInsets.zero,
            title: Text(l[KApp.agendaRepeat]),
            value: _repeat,
            onChanged: _busy
                ? null
                : (on) => setState(() {
                      _repeat = on;
                      _error = null;
                    }),
          ),
          if (_repeat) _weekdayPicker(l),
        ],
      ],
    );
  }

  /// The routine itself, from this day on: its fields, its weekdays, and the
  /// stop (confirmed in the sheet, U-38).
  Widget _routineFrame(Localization l, ChildRoutine routine) {
    return AppSheetFrame(
      title: l[KApp.agendaRoutineEditTitle],
      busy: _busy,
      error: _error,
      primaryLabel: l[K.commonSave],
      onPrimary: () => _save(l),
      secondaryLabel: l[K.commonCancel],
      onSecondary: () => Navigator.of(context).pop(),
      extraAction: AppSheetDangerAction(
        key: const ValueKey('agenda-routine-stop'),
        label: l[KApp.agendaRoutineStop],
        icon: Icons.event_busy_outlined,
        onPressed:
            _busy ? null : () => setState(() => _confirmingDelete = true),
      ),
      confirmation: !_confirmingDelete
          ? null
          : AppSheetConfirmation.destructive(
              key: const ValueKey('agenda-routine-stop-confirm'),
              message: l.format(
                  KApp.agendaRoutineStopConfirm, [l.formatDate(widget.date)]),
              yesLabel: l[KApp.agendaRoutineStop],
              onYes: () => _run(l, () async {
                final gone = await widget.dataSource.stopChildRoutine(
                    routineId: routine.id, from: widget.date);
                return l.format(KApp.agendaRoutineStopped, [gone]);
              }),
              noLabel: l[K.commonCancel],
              onNo: () => setState(() => _confirmingDelete = false),
              busy: _busy,
            ),
      children: [
        ..._fields(l),
        const SizedBox(height: Spacing.md),
        _weekdayPicker(l),
      ],
    );
  }

  List<Widget> _fields(Localization l) {
    final textTheme = Theme.of(context).textTheme;
    final tokens = context.tokens;
    final structured = _kind.isStructured;
    return [
        Text(l[KApp.agendaKindLabel],
            style: textTheme.labelMedium?.copyWith(color: tokens.textMuted)),
        const SizedBox(height: Spacing.xs),
        Wrap(
          spacing: Spacing.sm,
          runSpacing: Spacing.xs,
          children: [
            for (final k in _offered)
              ChoiceChip(
                key: ValueKey('agenda-kind-${k.wire}'),
                label: Text(l[k.labelKey]),
                selected: _kind == k,
                onSelected: _busy
                    ? null
                    : (_) => setState(() {
                          _kind = k;
                          _error = null;
                        }),
              ),
          ],
        ),
        if (structured) ...[
          const SizedBox(height: Spacing.md),
          if (widget.children.isEmpty)
            Text(
                l[widget.isAdmin
                    ? KApp.agendaNoChildAdmin
                    : KApp.agendaNoChildMember],
                style: textTheme.bodySmall?.copyWith(color: tokens.textMuted))
          else if (widget.children.length > 1)
            DropdownButtonFormField<int>(
              key: const ValueKey('agenda-child'),
              initialValue: _childId,
              decoration:
                  InputDecoration(labelText: l[KApp.agendaChildLabel]),
              items: [
                for (final c in widget.children)
                  DropdownMenuItem(value: c.id, child: Text(c.firstName)),
              ],
              onChanged:
                  _busy ? null : (v) => setState(() => _childId = v),
            )
          else
            AppListRow(
              label: l[KApp.agendaChildLabel],
              value: widget.children.single.firstName,
            ),
        ],
        const SizedBox(height: Spacing.md),
        Wrap(
          spacing: Spacing.sm,
          runSpacing: Spacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _timeButton(l, start: true, value: _start),
            if (_start != null) _timeButton(l, start: false, value: _end),
            if (_start != null)
              TextButton(
                key: const ValueKey('agenda-clear-time'),
                onPressed: _busy
                    ? null
                    : () => setState(() {
                          _start = null;
                          _end = null;
                        }),
                child: Text(l[KApp.agendaClearTime]),
              ),
          ],
        ),
        const SizedBox(height: Spacing.md),
        AppTextField(
          key: const ValueKey('agenda-body'),
          label: l[_kind == AgendaKind.note
              ? KApp.agendaNoteBodyLabel
              : KApp.agendaBodyLabel],
          controller: _body,
          maxLength: widget.settings.agendaTextMaxChars,
          maxLines: 4,
        ),
        const SizedBox(height: Spacing.sm),
        ..._notifyFields(l),
    ];
  }

  /// F-55 PR 4: the creator's choice — who, which channels (never e-mail),
  /// and the reminder when the item has a start time.
  List<Widget> _notifyFields(Localization l) {
    final textTheme = Theme.of(context).textTheme;
    final tokens = context.tokens;
    final muted = textTheme.labelMedium?.copyWith(color: tokens.textMuted);
    void pick(VoidCallback change) => setState(() {
          change();
          _error = null;
        });
    return [
      Text(l[KApp.agendaNotifyLabel], style: muted),
      const SizedBox(height: Spacing.xs),
      Wrap(
        spacing: Spacing.xs,
        runSpacing: Spacing.xs,
        children: [
          for (final (a, key) in const [
            (AgendaAudience.none, KApp.agendaNotifyNone),
            (AgendaAudience.self, KApp.agendaNotifySelf),
            (AgendaAudience.responsible, KApp.agendaNotifyResponsible),
            (AgendaAudience.family, KApp.agendaNotifyFamily),
          ])
            ChoiceChip(
              key: ValueKey('agenda-notify-${a.wire}'),
              label: Text(l[key]),
              selected: _notifyTo == a,
              onSelected: _busy ? null : (_) => pick(() => _notifyTo = a),
            ),
        ],
      ),
      if (_notifyTo != AgendaAudience.none) ...[
        const SizedBox(height: Spacing.xs),
        Wrap(
          spacing: Spacing.xs,
          runSpacing: Spacing.xs,
          children: [
            FilterChip(
              key: const ValueKey('agenda-notify-push'),
              label: Text(l[KApp.agendaNotifyPush]),
              selected: _notifyPush,
              onSelected:
                  _busy ? null : (on) => pick(() => _notifyPush = on),
            ),
            FilterChip(
              key: const ValueKey('agenda-notify-app'),
              label: Text(l[KApp.agendaNotifyInApp]),
              selected: _notifyInApp,
              onSelected:
                  _busy ? null : (on) => pick(() => _notifyInApp = on),
            ),
          ],
        ),
        const SizedBox(height: Spacing.sm),
        Text(l[KApp.agendaRemindLabel], style: muted),
        const SizedBox(height: Spacing.xs),
        if (_start == null)
          Text(l[KApp.agendaRemindNeedsStart],
              key: const ValueKey('agenda-remind-needs-start'),
              style: textTheme.bodySmall?.copyWith(color: tokens.textMuted))
        else
          Wrap(
            spacing: Spacing.xs,
            runSpacing: Spacing.xs,
            children: [
              ChoiceChip(
                key: const ValueKey('agenda-remind-none'),
                label: Text(l[KApp.agendaRemindNone]),
                selected: _remind == null,
                onSelected: _busy ? null : (_) => pick(() => _remind = null),
              ),
              for (final m in AgendaNotify.remindOffsets)
                ChoiceChip(
                  key: ValueKey('agenda-remind-$m'),
                  label: Text(m == 0
                      ? l[KApp.agendaRemindAtStart]
                      : l.format(KApp.agendaRemindBefore, [m])),
                  selected: _remind == m,
                  onSelected: _busy ? null : (_) => pick(() => _remind = m),
                ),
            ],
          ),
        const SizedBox(height: Spacing.xs),
        Text(l[KApp.agendaNotifyLead],
            style: textTheme.bodySmall?.copyWith(color: tokens.textMuted)),
      ],
    ];
  }
}

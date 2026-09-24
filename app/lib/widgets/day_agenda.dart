import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';

import 'package:entrelares_db_contracts/models/child.dart';
import 'package:entrelares_db_contracts/models/child_event.dart';
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
      ]);
      if (!mounted) return;
      setState(() {
        _events = results[0] as List<ChildEvent>;
        _children = results[1] as List<Child>;
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
      !widget.me!.hasLeft;

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

  Future<void> _openEditor(Localization l, {ChildEvent? event}) async {
    final outcome = await showAppSheet<_EditorOutcome>(
      context: context,
      builder: (_) => AgendaEventSheet(
        date: widget.date,
        event: event,
        children: _children,
        settings: widget.settings,
        freeLimited: _freeLimited,
        isAdmin: widget.me?.isAdmin == true,
        dataSource: widget.dataSource,
      ),
    );
    if (outcome == null || !mounted) return;
    showAppSnack(
        context,
        l[outcome == _EditorOutcome.deleted
            ? KApp.agendaDeleted
            : KApp.agendaSaved]);
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

enum _EditorOutcome { saved, deleted }

/// The editor of one agenda item — new, or [event] to edit. Stacks on top of
/// the day sheet; a refusal keeps it open with the server's sentence.
class AgendaEventSheet extends StatefulWidget {
  final DateTime date;
  final ChildEvent? event;
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
  String? _error;
  bool _busy = false;
  bool _confirmingDelete = false;

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

  Future<void> _run(Localization l, Future<void> Function() action,
      _EditorOutcome outcome) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (!mounted) return;
      Navigator.of(context).pop(outcome);
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
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    final event = widget.event;
    _run(
      l,
      () => event == null
          ? widget.dataSource.addChildEvent(
              date: widget.date,
              kind: _kind.wire,
              childId: childId,
              start: _start,
              end: _end,
              body: _body.text,
            )
          : widget.dataSource.updateChildEvent(
              id: event.id,
              date: widget.date,
              kind: _kind.wire,
              childId: childId,
              start: _start,
              end: _end,
              body: _body.text,
            ),
      _EditorOutcome.saved,
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
    final structured = _kind.isStructured;
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
              onYes: () => _run(
                  l,
                  () => widget.dataSource.deleteChildEvent(event.id),
                  _EditorOutcome.deleted),
              noLabel: l[K.commonCancel],
              onNo: () => setState(() => _confirmingDelete = false),
              busy: _busy,
            ),
      children: [
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
      ],
    );
  }
}

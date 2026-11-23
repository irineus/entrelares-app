import 'dart:async';

import 'package:entrelares_core/entrelares_core.dart';
import 'package:entrelares_db_contracts/models/child.dart';
import 'package:entrelares_db_contracts/models/care_schedule.dart';
import 'package:entrelares_db_contracts/models/child_event.dart';
import 'package:entrelares_db_contracts/models/family.dart';
import 'package:entrelares_db_contracts/models/member.dart';
import 'package:material_ui/material_ui.dart';

import '../env.dart';
import '../services/custody_data_source.dart';
import '../services/file_delivery.dart';
import '../theme/tokens.dart';
import 'app_l10n.dart';
import 'app_snack.dart';
import 'ui/ui.dart';

/// F-08 — *Exportar para outro calendário*: the plan and the children's agenda
/// as an `.ics` file (owner, 20/11/2026).
///
/// The rules live in core ([CalendarExportRules], [IcsWriter]); this sheet
/// only reads the period, keeps the reader's choices and hands the file to
/// [deliverTextFile] — the share sheet on Android, a download on the web.
///
/// A family without Premium (while `calendar_export.premium_only` is on) gets
/// the gate instead: an [AppBanner] whose CTA opens `/family/plan` with the
/// `calendar-export` token (F-79/F-102), where a non-admin can ask the admin.
Future<void> showCalendarExportSheet(
  BuildContext context, {
  required CustodyDataSource dataSource,
  required Family family,
  required List<Member> members,
  required List<Child> children,
  required Member? me,
  required bool allowed,
  required bool agendaEnabled,
  required DateTime visibleMonth,
  VoidCallback? onOpenPlan,
}) =>
    showAppSheet<void>(
      context: context,
      builder: (context) => CalendarExportSheet(
        dataSource: dataSource,
        family: family,
        members: members,
        children: children,
        me: me,
        allowed: allowed,
        agendaEnabled: agendaEnabled,
        visibleMonth: visibleMonth,
        onOpenPlan: onOpenPlan,
      ),
    );

enum _Period { month, year, custom }

class CalendarExportSheet extends StatefulWidget {
  final CustodyDataSource dataSource;
  final Family family;
  final List<Member> members;
  final List<Child> children;
  final Member? me;

  /// Premium, or the gate is off (`calendar_export.premium_only`).
  final bool allowed;

  /// `feature.child_agenda`: without it there is no events layer to offer.
  final bool agendaEnabled;
  final DateTime visibleMonth;
  final VoidCallback? onOpenPlan;

  /// Tests: the file goes here instead of the platform.
  final Future<void> Function(String fileName, String contents)? deliver;

  const CalendarExportSheet({
    super.key,
    required this.dataSource,
    required this.family,
    required this.members,
    required this.children,
    required this.me,
    required this.allowed,
    required this.agendaEnabled,
    required this.visibleMonth,
    this.onOpenPlan,
    this.deliver,
  });

  static const submitKey = ValueKey('cal-export-submit');
  static const countKey = ValueKey('cal-export-count');

  @override
  State<CalendarExportSheet> createState() => _CalendarExportSheetState();
}

class _CalendarExportSheetState extends State<CalendarExportSheet> {
  _Period _period = _Period.month;
  late int _month = widget.visibleMonth.month;
  late int _year = widget.visibleMonth.year;
  late DateTime _customFrom = FamilyTime.today();
  late DateTime _customTo = DateTime(
      _customFrom.year, _customFrom.month + 3, _customFrom.day);

  bool _handoffs = true;
  late bool _events = widget.agendaEnabled;
  bool _days = false;
  bool _reminders = false;
  bool _mine = false;
  Set<AgendaKind> _kinds = {...CalendarExportRules.defaultKinds};
  late Set<int> _children = {for (final c in widget.children) c.id};

  List<ExportPlanDay>? _plan;
  List<ExportAgendaEvent> _agenda = const [];
  String? _loadedFor;
  bool _loading = false;
  bool _busy = false;
  String? _error;

  bool get _viewer => widget.me?.isViewer == true;

  (DateTime, DateTime) get _range => switch (_period) {
        _Period.month => (DateTime(_year, _month, 1), DateTime(_year, _month + 1, 0)),
        _Period.year => (DateTime(_year, 1, 1), DateTime(_year, 12, 31)),
        _Period.custom => (_customFrom, _customTo),
      };

  bool get _rangeValid => !_range.$2.isBefore(_range.$1);

  CalendarExportOptions get _options => CalendarExportOptions(
        from: _range.$1,
        to: _range.$2,
        handoffs: _handoffs,
        events: _events && widget.agendaEnabled,
        days: _days,
        reminders: _reminders,
        kinds: _kinds,
        children: widget.children.length > 1 ? _children : null,
        onlyProfileId: _mine && !_viewer ? widget.me?.id : null,
      );

  CalendarExportFamily get _family {
    String firstName(Member m) {
      final name = m.fullName.trim();
      return name.isEmpty ? '?' : name.split(RegExp(r'\s+')).first;
    }

    final origin = Env.current.webOrigin;
    return CalendarExportFamily(
      familyId: widget.family.id,
      familyName: widget.family.name,
      names: {for (final m in widget.members) m.id: firstName(m)},
      childNames: {for (final c in widget.children) c.id: c.firstName},
      perChild: widget.family.isPerChild && widget.children.isNotEmpty,
      dayUrl: (d) => '$origin/?day=${CareSchedule.isoDate(d)}',
    );
  }

  @override
  void initState() {
    super.initState();
    if (widget.allowed) unawaited(_load());
  }

  /// Reads the period once per range; the count then follows every toggle
  /// without a round trip.
  Future<void> _load() async {
    if (!_rangeValid) return;
    final (from, to) = _range;
    final key = '${CareSchedule.isoDate(from)}|${CareSchedule.isoDate(to)}';
    if (key == _loadedFor || _loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await widget.dataSource
          .fetchSchedulesForPeriod(CalendarExportRules.fetchFrom(from), to);
      final events = widget.agendaEnabled
          ? await widget.dataSource
              .fetchChildEvents(from, to, includeDeleted: true)
          : const <ChildEvent>[];
      if (!mounted) return;
      setState(() {
        _plan = [
          for (final r in rows)
            ExportPlanDay(
              date: r.scheduleDate,
              lane: r.childId,
              plannedId: r.scheduledParentId,
              effectiveId: r.effectiveParentId,
              handoff: r.handoffTime,
            ),
        ];
        _agenda = [
          for (final e in events)
            if (AgendaKind.parse(e.kind) case final kind?)
              ExportAgendaEvent(
                id: e.id,
                date: e.eventDate,
                kind: kind,
                childId: e.childId,
                start: e.startTime,
                end: e.endTime,
                body: e.body,
                deleted: e.isDeleted,
                remindMinutes: e.remindMinutes,
              ),
        ];
        _loadedFor = key;
        _loading = false;
      });
      // The range may have moved while this read was in flight.
      unawaited(_load());
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = AppL10n.of(context).l[KApp.calExportError];
      });
    }
  }

  List<IcsEvent> _build(Localization l) => CalendarExportRules.build(
        plan: _plan ?? const [],
        agenda: _agenda,
        options: _options,
        family: _family,
        l: l,
      );

  void _changed(VoidCallback change) {
    setState(change);
    unawaited(_load());
  }

  Future<void> _export(Localization l) async {
    final events = _build(l);
    final count = CalendarExportRules.count(events);
    if (count == 0) return;
    setState(() => _busy = true);
    try {
      final text = IcsWriter.write(events,
          calendarName: CalendarExportRules.calendarName(l, _family),
          stampUtc: DateTime.now().toUtc());
      final name = CalendarExportRules.fileName(_options);
      final deliver = widget.deliver ??
          (String n, String c) =>
              deliverTextFile(n, c, mimeType: 'text/calendar');
      await deliver(name, text);
      unawaited(widget.dataSource.analytics?.trackEvent(
              AnalyticsEvents.calendarExport,
              props: {
                'layers': CalendarExportRules.layersToken(_options),
                'period': _period.name,
                'scope': _options.onlyProfileId == null ? 'family' : 'mine',
                'size': CalendarExportRules.sizeBucket(count),
              }) ??
          Future<void>.value());
      if (!mounted) return;
      setState(() => _busy = false);
      showAppSnack(context, l[KApp.calExportDone]);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = l[KApp.calExportError];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context).l;
    final tokens = context.tokens;
    final textTheme = Theme.of(context).textTheme;

    if (!widget.allowed) {
      final openPlan = widget.onOpenPlan;
      return AppSheetFrame(
        title: l[KApp.calExportAction],
        children: [
          AppBanner(
            key: const ValueKey('cal-export-premium'),
            tone: tokens.info,
            icon: Icons.workspace_premium_outlined,
            message: l[KApp.calExportPremium],
            actionLabel: openPlan == null ? null : l[K.famSeePremium],
            onAction: openPlan == null
                ? null
                : () {
                    widget.dataSource.analytics?.trackEvent(
                        AnalyticsEvents.premiumGateClick,
                        props: {'gate': 'calendar-export'});
                    Navigator.of(context).pop();
                    openPlan();
                  },
          ),
        ],
      );
    }

    final events = _plan == null ? null : _build(l);
    final count = events == null ? null : CalendarExportRules.count(events);
    final ready = _rangeValid && !_loading && count != null && count > 0;

    return AppSheetFrame(
      title: l[KApp.calExportAction],
      subtitle: l[KApp.calExportLead],
      error: _error,
      busy: _busy,
      primaryLabel: l[KApp.calExportSubmit],
      onPrimary: ready && !_busy ? () => _export(l) : null,
      children: [
        // ── Period ──
        AppFieldLabel(l[KApp.calExportPeriod]),
        AppSegmented<_Period>(
          semantics: l[KApp.calExportPeriod],
          options: [
            (value: _Period.month, label: l[KApp.calExportPeriodMonth]),
            (value: _Period.year, label: l[KApp.calExportPeriodYear]),
            (value: _Period.custom, label: l[KApp.calExportPeriodCustom]),
          ],
          selected: _period,
          onChanged: (v) => _changed(() => _period = v),
        ),
        const SizedBox(height: Spacing.sm),
        if (_period == _Period.custom)
          Row(
            children: [
              Expanded(
                  child: _dateField(l, l[KApp.calExportFrom], _customFrom,
                      (d) => _changed(() => _customFrom = d))),
              const SizedBox(width: Spacing.sm),
              Expanded(
                  child: _dateField(l, l[KApp.calExportTo], _customTo,
                      (d) => _changed(() => _customTo = d))),
            ],
          )
        else
          Row(
            children: [
              if (_period == _Period.month) ...[
                Expanded(
                  child: Semantics(
                    label: l[KApp.calExportPeriodMonth],
                    child: DropdownButtonFormField<int>(
                      isExpanded: true,
                      initialValue: _month,
                      items: [
                        for (var m = 1; m <= 12; m++)
                          DropdownMenuItem(
                              value: m, child: Text(l.monthName(m))),
                      ],
                      onChanged: (m) => _changed(() => _month = m ?? _month),
                    ),
                  ),
                ),
                const SizedBox(width: Spacing.sm),
              ],
              Expanded(
                child: Semantics(
                  label: l[KApp.calExportPeriodYear],
                  child: DropdownButtonFormField<int>(
                    isExpanded: true,
                    initialValue: _year,
                    items: [
                      for (final y in reportYearRange(FamilyTime.today().year))
                        DropdownMenuItem(value: y, child: Text('$y')),
                    ],
                    onChanged: (y) => _changed(() => _year = y ?? _year),
                  ),
                ),
              ),
            ],
          ),
        if (!_rangeValid) ...[
          const SizedBox(height: Spacing.xs),
          Text(l[KApp.calExportPeriodInvalid],
              style: textTheme.bodySmall
                  ?.copyWith(color: tokens.danger.onContainer)),
        ],
        const SizedBox(height: Spacing.md),

        // ── Layers ──
        AppFieldLabel(l[KApp.calExportLayers]),
        SwitchListTile(
          key: const ValueKey('cal-export-handoffs'),
          contentPadding: EdgeInsets.zero,
          value: _handoffs,
          title: Text(l[KApp.calExportHandoffs]),
          subtitle: Text(l[KApp.calExportHandoffsHint]),
          onChanged: (v) => setState(() => _handoffs = v),
        ),
        if (widget.agendaEnabled) ...[
          SwitchListTile(
            key: const ValueKey('cal-export-events'),
            contentPadding: EdgeInsets.zero,
            value: _events,
            title: Text(l[KApp.calExportEvents]),
            onChanged: (v) => setState(() => _events = v),
          ),
          if (_events) ...[
            AppFieldLabel(l[KApp.calExportKinds]),
            Wrap(
              key: const ValueKey('cal-export-kinds'),
              spacing: Spacing.sm,
              children: [
                for (final kind in AgendaRules.pickerOrder)
                  FilterChip(
                    key: ValueKey('cal-export-kind-${kind.wire}'),
                    label: Text(l[kind.labelKey]),
                    selected: _kinds.contains(kind),
                    onSelected: (on) => setState(() => _kinds = on
                        ? {..._kinds, kind}
                        : ({..._kinds}..remove(kind))),
                  ),
              ],
            ),
          ],
        ],
        SwitchListTile(
          key: const ValueKey('cal-export-days'),
          contentPadding: EdgeInsets.zero,
          value: _days,
          title: Text(l[KApp.calExportDays]),
          onChanged: (v) => setState(() => _days = v),
        ),

        // ── Children (F-96's picker) ──
        if (widget.children.length > 1) ...[
          const SizedBox(height: Spacing.sm),
          AppFieldLabel(l[KApp.calExportChildren]),
          Wrap(
            key: const ValueKey('cal-export-children'),
            spacing: Spacing.sm,
            children: [
              for (final c in widget.children)
                FilterChip(
                  key: ValueKey('cal-export-child-${c.id}'),
                  label: Text(c.firstName),
                  selected: _children.contains(c.id),
                  onSelected: (on) => setState(() => _children = on
                      ? {..._children, c.id}
                      : ({..._children}..remove(c.id))),
                ),
            ],
          ),
        ],

        // ── For whom ──
        if (!_viewer && widget.me != null) ...[
          const SizedBox(height: Spacing.md),
          AppFieldLabel(l[KApp.calExportScope]),
          AppSegmented<bool>(
            semantics: l[KApp.calExportScope],
            options: [
              (value: false, label: l[KApp.calExportScopeFamily]),
              (value: true, label: l[KApp.calExportScopeMine]),
            ],
            selected: _mine,
            onChanged: (v) => setState(() => _mine = v),
          ),
        ],

        // ── Reminders ──
        SwitchListTile(
          key: const ValueKey('cal-export-reminders'),
          contentPadding: EdgeInsets.zero,
          value: _reminders,
          title: Text(l[KApp.calExportReminders]),
          subtitle: Text(l[KApp.calExportRemindersHint]),
          onChanged: (v) => setState(() => _reminders = v),
        ),
        const SizedBox(height: Spacing.sm),

        // ── What will go out ──
        if (_loading || count == null)
          const AppSkeleton(height: 20, width: 120)
        else
          Text(
            count == 0
                ? l[KApp.calExportEmpty]
                : count == 1
                    ? l[KApp.calExportCountOne]
                    : l.format(KApp.calExportCountMany, [count]),
            key: CalendarExportSheet.countKey,
            style: textTheme.titleSmall,
          ),
        const SizedBox(height: Spacing.sm),
        // Said, not hidden behind a tooltip nobody long-presses (U-36): the
        // Google Calendar app may not import a file at all on Android.
        AppBanner(
          key: const ValueKey('cal-export-tip'),
          tone: tokens.info,
          icon: Icons.info_outline,
          message: l[KApp.calExportTip],
        ),
      ],
    );
  }

  Widget _dateField(Localization l, String label, DateTime value,
          ValueChanged<DateTime> onPicked) =>
      OutlinedButton(
        onPressed: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: value,
            firstDate: DateTime(FamilyTime.today().year - 5),
            lastDate: DateTime(FamilyTime.today().year + 5, 12, 31),
          );
          if (picked != null) onPicked(picked);
        },
        child: Text('$label ${l.formatDate(value)}'),
      );
}

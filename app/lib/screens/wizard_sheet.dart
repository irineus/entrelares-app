import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import '../widgets/ui/ui.dart';
import 'package:flutter/services.dart';

import 'package:entrelares_db_contracts/models/care_schedule.dart';
import 'package:entrelares_db_contracts/models/member.dart';
import '../services/admin_mode.dart';
import '../services/analytics_service.dart';
import '../services/custody_data_source.dart';
import '../theme/tokens.dart';
import '../widgets/admin_mode_offer.dart';
import '../widgets/app_l10n.dart';
import '../widgets/cycle_strip.dart';

/// The Rotation Wizard — mirror of `ScheduleWizard.razor` over the pure rules
/// in `entrelares_core/wizard_rules.dart`: presets, cycle blocks, start date
/// and duration, one handoff time landing only on transitions, the F-39
/// horizon clamp, and the insert-only bulk write that PRESERVES existing days
/// ("criados X, mantidos Y"). Pops with `true` after a successful generation
/// (the caller reloads; the success text is shown inside the sheet, mirror of
/// the web's `isCompleted` view).
///
/// F-51: under the admin bypass the sheet offers "substituir os dias já
/// planejados" — the wizard then clears EXACTLY the range it is about to
/// generate and inserts the plan in ONE server-side transaction
/// (`replaceScheduleRange`), after the same S-09 confirmation the bulk edit
/// asks before rewriting planned days. Without it, re-planning over an old
/// plan answered "0 dias criados" and read as a bug.
Future<bool?> showWizardSheet({
  required BuildContext context,
  required List<Member> activeMembers,
  required DateTime today,
  required CustodyDataSource dataSource,
  DateTime? maxScheduleDate,
  required bool isFreeTier,
  bool adminBypass = false,
  AdminModeOfferer? adminOffer,
  AnalyticsService? analytics,
  DateTime? initialStart,
}) {
  return showAppSheet<bool>(
    context: context,
    builder: (context) => _WizardSheet(
      activeMembers: activeMembers,
      today: today,
      dataSource: dataSource,
      maxScheduleDate: maxScheduleDate,
      isFreeTier: isFreeTier,
      adminBypass: adminBypass,
      adminOffer: adminOffer,
      analytics: analytics,
      initialStart: initialStart,
    ),
  );
}

class _WizardSheet extends StatefulWidget {
  final List<Member> activeMembers;
  final DateTime today;
  final CustodyDataSource dataSource;
  final DateTime? maxScheduleDate;
  final bool isFreeTier;

  /// F-51: admin mode on AND a real admin — the only state that may offer
  /// the replace. The database enforces it regardless (the RPC refuses a
  /// non-admin); this only decides whether to ASK.
  final bool adminBypass;

  /// F-67 Part B: non-null only for an admin — the replace is then SHOWN with
  /// the mode off, and ticking it asks to turn the mode on.
  final AdminModeOfferer? adminOffer;

  /// T-37 — optional: the activation signal never gates the generation.
  final AnalyticsService? analytics;

  /// U-40: the day the start-date field opens on — the empty month's strip
  /// passes the 1st of that month (or today, in the current month). Null is
  /// today. Never before today: the picker's own floor is today, so a start
  /// behind it would be a value the field could show but never pick.
  final DateTime? initialStart;

  const _WizardSheet({
    required this.activeMembers,
    required this.today,
    required this.dataSource,
    required this.maxScheduleDate,
    required this.isFreeTier,
    required this.adminBypass,
    this.adminOffer,
    this.analytics,
    this.initialStart,
  });

  @override
  State<_WizardSheet> createState() => _WizardSheetState();
}

class _MutableBlock {
  int profileId;
  int days;
  _MutableBlock(this.profileId, this.days);
}

class _WizardSheetState extends State<_WizardSheet> {
  String _preset = '7-7';
  List<_MutableBlock> _blocks = [];
  late DateTime _startDate;
  int _durationMonths = 3;
  /// U-37: one value, picked by the platform; null is "no handoff time".
  TimeOfDay? _handoff;
  bool _generating = false;
  bool _completed = false;
  String? _successMessage;
  String? _errorMessage;
  double _progress = 0;

  /// F-51: the replace checkbox and its S-09 confirmation. The count is the
  /// planned days the range holds NOW (one read, before the confirmation);
  /// `_replaceConfirmed` is consumed by the generation that follows the yes.
  bool _replaceExisting = false;

  /// F-14 bypass as THIS sheet sees it — turned true by the F-67 offer, so
  /// the cycle already typed survives the answer.
  late bool _bypass = widget.adminBypass;
  bool _offering = false;
  bool _showReplaceConfirm = false;
  bool _replaceConfirmed = false;
  int _replaceCount = 0;

  /// The replace is one server round trip with no progress to report — the
  /// bar runs indeterminate while it lasts.
  bool _indeterminate = false;

  List<int> get _profileIds =>
      [for (final m in widget.activeMembers) m.id];

  /// U-41: the strip paints with the grid's own rules (slot, initials), which
  /// read the core's `MemberView` slice.
  List<MemberView> get _views =>
      [for (final m in widget.activeMembers) m.toView()];

  ({int hour, int minute})? get _handoffTime =>
      _handoff == null ? null : (hour: _handoff!.hour, minute: _handoff!.minute);

  @override
  void initState() {
    super.initState();
    final floor = dateOnly(widget.today);
    final wanted = widget.initialStart;
    _startDate =
        wanted == null || wanted.isBefore(floor) ? floor : dateOnly(wanted);
    _applyPreset('7-7');
  }

  void _applyPreset(String preset) {
    _blocks = [
      for (final b in wizardPresetBlocks(preset, _profileIds))
        _MutableBlock(b.profileId, b.days),
    ];
  }

  List<CycleBlock> get _cycleBlocks =>
      [for (final b in _blocks) CycleBlock(b.profileId, b.days)];

  String? _validationText(Localization l) {
    final error = validateWizard(
      blocks: _cycleBlocks,
      start: _startDate,
      today: widget.today,
      maxScheduleDate: widget.maxScheduleDate,
    );
    return switch (error) {
      null => null,
      WizardValidationError.tooFewBlocks => l[KApp.wizErrTooFewBlocks],
      WizardValidationError.blockWithoutParent =>
        l[K.wizErrPickParentPerBlock],
      WizardValidationError.blockWithoutDays => l[KApp.wizErrBlockDays],
      WizardValidationError.startInPast => l[K.wizErrStartInPast],
      WizardValidationError.startBeyondHorizon => widget.isFreeTier
          ? l[K.wizErrStartBeyondFree]
          : l[K.wizErrStartBeyondMax],
    };
  }

  Future<void> _generate() async {
    if (_generating) return;
    final l = AppL10n.of(context).l;
    final validation = _validationText(l);
    if (validation != null) {
      setState(() => _errorMessage = validation);
      return;
    }
    setState(() {
      _generating = true;
      _errorMessage = null;
      _progress = 0;
      _indeterminate = false;
    });
    try {
      // F-39: clamp the generated range to the family's planning horizon.
      final clampResult = clampScheduleEnd(
          addMonthsClamped(_startDate, _durationMonths),
          widget.maxScheduleDate);
      final generated = generateRotation(
        start: _startDate,
        end: clampResult.end,
        blocks: _cycleBlocks,
        handoffTime: _handoffTime,
      );
      final rows = [
        for (final g in generated)
          CareSchedule(
            id: 0,
            scheduleDate: g.date,
            scheduledParentId: g.scheduledParentId,
            handoffTime: g.handoffTime == null
                ? null
                : '${g.handoffTime!.hour.toString().padLeft(2, '0')}:'
                    '${g.handoffTime!.minute.toString().padLeft(2, '0')}:00',
          ),
      ];

      final replaceRange = _bypass && _replaceExisting
          ? wizardReplaceRange(start: _startDate, end: clampResult.end)
          : null;

      String message;
      int created;
      if (replaceRange != null) {
        // F-51: the S-09 question, asked once, with the count of planned days
        // the range holds — the same warning the bulk edit shows before it
        // rewrites a planned parent. Nothing to overwrite → nothing to ask.
        if (!_replaceConfirmed) {
          final existing = await widget.dataSource.fetchUpcoming(
              replaceRange.from,
              replaceRange.to.difference(replaceRange.from).inDays);
          // A day holding an approved swap is kept by the server, so it is
          // not a day this call will rewrite. Frozen days are kept too, but
          // the sheet has no frozen list for a range beyond the displayed
          // month — the question may over-count by those, never under.
          final count = plannedDaysInRange([
            for (final d in existing)
              if (d.actualParentId == null ||
                  d.actualParentId == d.scheduledParentId)
                d.scheduleDate,
          ], replaceRange);
          if (count > 0) {
            if (!mounted) return;
            setState(() {
              _generating = false;
              _replaceCount = count;
              _showReplaceConfirm = true;
            });
            return;
          }
        }
        _replaceConfirmed = false;
        setState(() => _indeterminate = true);
        final result = await widget.dataSource.replaceScheduleRange(
            replaceRange.from, replaceRange.to, rows);
        created = result.inserted;
        message = wizardReplaceSummary(l, result);
      } else {
        created = await widget.dataSource.bulkInsertNewDays(rows,
            onProgress: (percent) =>
                setState(() => _progress = percent / 100));
        final kept = rows.length - created;
        message = l.format(K.wizDoneCreated, [created]);
        if (kept > 0) message += l.format(K.wizDoneKept, [kept]);
      }
      if (clampResult.clamped) {
        message += l[
            widget.isFreeTier ? K.wizDoneClampedFree : K.wizDoneClampedMax];
      }
      // T-37: the key activation moment — a family generated its base plan.
      widget.analytics?.trackEvent('wizard_completed', props: {
        'created': created > 0 ? 'yes' : 'none',
        'replaced': replaceRange != null ? 'yes' : 'no',
      });
      setState(() {
        _generating = false;
        _completed = true;
        _successMessage = message;
      });
    } catch (e) {
      if (!mounted) return;
      final raw = e.toString();
      setState(() {
        _generating = false;
        _errorMessage = isSessionExpired(raw)
            ? sessionExpiredMessage(l)
            : l.format(K.wizErrGenerate,
                [translateSaveError(raw, l[K.errSaveFailed], l)]);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context).l;
    // U-28 QA: the wizard was the worst offender — full screen, nothing to tap
    // to dismiss, and "Gerar"/"Cancelar" below the fold at the end of a long
    // form. The frame pins them, and `showAppSheet` keeps a strip of calendar
    // visible above.
    return AppSheetFrame(
      title: l[K.wizTitle],
      subtitle: l[K.wizSubtitle],
      error: _errorMessage,
      // F-51: while the S-09 question is on screen it owns the action row —
      // since U-38 literally, in the row's own place, where "Gerar" was
      // tapped. It used to open at the TOP of the form, out of sight of
      // anyone who had scrolled down to the options.
      confirmation: _offering
          ? AdminModeOfferConfirmation(
              action: AdminModeAction.wizardReplace,
              onActivate: () {
                widget.adminOffer?.accept(AdminModeAction.wizardReplace);
                setState(() {
                  _offering = false;
                  _bypass = true;
                  _replaceExisting = true;
                });
              },
              onCancel: () {
                widget.adminOffer?.decline(AdminModeAction.wizardReplace);
                setState(() => _offering = false);
              },
            )
          : _showReplaceConfirm
              ? _replaceConfirmation(l)
              : null,
      primaryLabel: _completed ? l[K.wizClose] : l[K.wizGenerate],
      onPrimary: _completed
          ? () => Navigator.of(context).pop(true)
          : (_generating ? null : _generate),
      secondaryLabel: _completed ? null : l[K.commonCancel],
      onSecondary: () => Navigator.of(context).pop(),
      busy: _generating,
      children: _completed ? _successView(l) : _form(l),
    );
  }

  /// F-51: the S-09 warning, the bulk sheet's own question (U-38: the shared
  /// [AppSheetConfirmation]).
  Widget _replaceConfirmation(Localization l) =>
      AppSheetConfirmation.destructive(
        message: l.format(
            _replaceCount == 1
                ? K.bulkOverwriteWarningOne
                : K.bulkOverwriteWarningMany,
            [_replaceCount]),
        yesLabel: l[K.editorYesChange],
        busy: _generating,
        onYes: () {
          setState(() {
            _showReplaceConfirm = false;
            _replaceConfirmed = true;
          });
          _generate();
        },
        noLabel: l[K.editorNoGoBack],
        onNo: () => setState(() => _showReplaceConfirm = false),
      );

  List<Widget> _successView(Localization l) => [
        Row(
          children: [
            Icon(Icons.check_circle_outline,
                size: 24, color: context.tokens.success.solid),
            const SizedBox(width: 8),
            Expanded(child: Text(_successMessage ?? '')),
          ],
        ),
      ];

  List<Widget> _form(Localization l) {
    final summary = wizardCycleSummary(
      blocks: _cycleBlocks,
      start: _startDate,
      durationMonths: _durationMonths,
    );
    // U-41: the strip is the plan's own first days — the same expansion the
    // generation runs, cut to two cycles — so what is previewed is what is
    // written. It follows every setState the form already does.
    final stripLength = cycleStripLength(summary.cycleDays);
    final stripDays = generateRotation(
      start: _startDate,
      end: DateTime(
          _startDate.year, _startDate.month, _startDate.day + stripLength),
      blocks: _cycleBlocks,
      handoffTime: _handoffTime,
    );
    return [
      // ── Preset shortcuts (the VALUES are pattern ids, never localized) ──
      //
      // U-28 QA: every control on this sheet was a bare `DropdownButton` — an
      // underline where the rest of the app has a bordered field with the label
      // folded into it. `DropdownButtonFormField` is the same control wearing
      // the app's own decoration, which is what the owner asked for: use the
      // integrated label wherever it is possible.
      AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
      DropdownButtonFormField<String>(
        key: const Key('wizPreset'),
        isExpanded: true,
        decoration: InputDecoration(
          labelText: l[K.wizPreset],
          suffixText: l[K.commonOptional],
        ),
        initialValue: _preset,
        items: [
          DropdownMenuItem(value: '', child: Text(l[K.wizPresetCustom])),
          DropdownMenuItem(value: '7-7', child: Text(l[K.wizPreset77])),
          DropdownMenuItem(value: '14-14', child: Text(l[K.wizPreset1414])),
          DropdownMenuItem(value: '1-1', child: Text(l[K.wizPreset11])),
          DropdownMenuItem(
              value: '5-2-2-5', child: Text(l[K.wizPreset5225])),
          DropdownMenuItem(value: '2-2-3', child: Text(l[K.wizPreset223])),
        ],
        onChanged: _generating
            ? null
            : (v) => setState(() {
                  _preset = v ?? '';
                  if (_preset.isNotEmpty) _applyPreset(_preset);
                }),
      ),
          ],
        ),
      ),
      const SizedBox(height: Spacing.sm),

      // ── Cycle blocks ──
      AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
      AppFieldLabel(l[K.wizCycleBlocks]),
      for (final (index, block) in _blocks.indexed)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 20, right: Spacing.sm),
              child: Text('${index + 1}.'),
            ),
            Expanded(
              child: DropdownButtonFormField<int>(
                key: Key('wizBlockParent$index'),
                isExpanded: true,
                decoration:
                    InputDecoration(labelText: l[K.wizBlockParentLabel]),
                initialValue: block.profileId,
                items: [
                  DropdownMenuItem(
                      value: 0, child: Text(l[K.wizBlockParent])),
                  for (final m in widget.activeMembers)
                    DropdownMenuItem(
                        value: m.id,
                        child: Text(m.fullName.split(' ').first)),
                ],
                onChanged: _generating
                    ? null
                    : (v) => setState(() {
                          block.profileId = v ?? 0;
                          _preset = '';
                        }),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(
                  horizontal: Spacing.xs, vertical: 20),
              child: Text('×'),
            ),
            SizedBox(
              width: 88,
              child: TextFormField(
                key: Key('wizBlockDays$index'),
                initialValue: '${block.days}',
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                textAlign: TextAlign.center,
                enabled: !_generating,
                decoration: InputDecoration(labelText: l[K.wizDays]),
                onChanged: (v) => setState(() {
                  block.days = clampBlockDays(int.tryParse(v) ?? 1);
                  _preset = '';
                }),
              ),
            ),
            // F-28: any non-empty cycle is valid — only the last block stays.
            if (_blocks.length > 1)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: IconButton(
                  tooltip: l[K.wizRemoveBlock],
                  icon: const Icon(Icons.delete_outline, size: 18),
                  onPressed: _generating
                      ? null
                      : () => setState(() => _blocks.removeAt(index)),
                ),
              ),
          ],
        ),
      const SizedBox(height: Spacing.xs),
      // U-28 QA: a full-width outlined action, as the web draws it. A bare
      // TextButton read as a caption under the last row rather than as the way
      // to add another one.
      OutlinedButton.icon(
        onPressed: _generating
            ? null
            : () => setState(() {
                  final ids = _profileIds;
                  _blocks.add(_MutableBlock(
                      ids.isEmpty ? 0 : ids[_blocks.length % ids.length], 1));
                  _preset = '';
                }),
        icon: const Icon(Icons.add),
        label: Text(l[K.wizAddBlock]),
      ),
          ],
        ),
      ),
      const SizedBox(height: Spacing.sm),

      // ── Start date and duration ──
      AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
      AppFieldLabel(l[K.wizStartDate]),
      OutlinedButton.icon(
        key: const Key('wizStartDate'),
        icon: const Icon(Icons.event_outlined),
        label: Text(l.formatDate(_startDate)),
        onPressed: _generating
            ? null
            : () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _startDate,
                  firstDate: dateOnly(widget.today),
                  lastDate: DateTime(widget.today.year + 3),
                );
                if (picked != null) {
                  setState(() => _startDate = dateOnly(picked));
                }
              },
      ),
      const SizedBox(height: Spacing.md),
      DropdownButtonFormField<int>(
        key: const Key('wizDuration'),
        isExpanded: true,
        decoration: InputDecoration(labelText: l[K.wizDuration]),
        initialValue: _durationMonths,
        items: [
          for (final months in const [1, 2, 3, 6, 12])
            DropdownMenuItem(
                value: months,
                child: Text(l.format(
                    months == 1 ? K.wizMonthsOne : K.wizMonthsMany,
                    [months]))),
        ],
        onChanged: _generating
            ? null
            : (v) => setState(() => _durationMonths = v ?? 3),
      ),
      const SizedBox(height: Spacing.md),

      // ── Handoff time (transitions only — T-27) ──
      //
      // U-37: one field, the platform's picker, instead of the hour + minute
      // dropdown pair.
      AppTimeField(
        fieldKey: const Key('wizHandoff'),
        label: l[K.wizHandoffTime],
        info: l[K.wizHandoffHint],
        optionalLabel: l[K.commonOptional],
        value: _handoff,
        enabled: !_generating,
        emptyText: l[K.editorHandoffEmpty],
        clearLabel: l[K.editorHandoffClear],
        formatValue: (t) => l.formatTime(DateTime(2000, 1, 1, t.hour, t.minute)),
        onChanged: (t) => setState(() => _handoff = t),
      ),
          ],
        ),
      ),
      const SizedBox(height: Spacing.sm),

      // ── F-51: replace the days already planned (admin mode only) ──
      //
      // The bulk sheet's own checkbox shape (label + hint), so the two places
      // that rewrite planned days look like one feature. The hint says what
      // is kept, because the server keeps it whatever the box says.
      // F-67 Part B: an admin with the mode off sees it too — ticking it asks.
      if (_bypass || widget.adminOffer != null) ...[
        AppCard(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                key: const Key('wizReplaceExisting'),
                // U-32: the label is a sibling text, so the box names itself.
                semanticLabel: l[K.wizReplaceExisting],
                value: _replaceExisting,
                onChanged: _generating
                    ? null
                    : (v) => v == true && !_bypass
                        ? setState(() {
                            _errorMessage = null;
                            _offering = true;
                          })
                        : setState(() => _replaceExisting = v ?? false),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(l[K.wizReplaceExisting]),
                    ),
                    const SizedBox(height: Spacing.xs),
                    Text(l[K.wizReplaceHint],
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Spacing.sm),
      ],

      // ── Preview ──
      //
      // U-28 QA: the cycle summary is the sheet's answer to "what will this
      // actually do", and it was a loose grey sentence at the end of the form.
      //
      // U-41: the strip first — the calendar about to be born, in the grid's
      // own language — and the arithmetic sentence under it.
      AppCard(
        title: l[K.wizCyclePreview],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (stripDays.isNotEmpty) ...[
              CycleStrip(days: stripDays, views: _views),
              const SizedBox(height: Spacing.sm),
            ],
            Text(
              l.format(K.wizCycleSummary,
                  [summary.cycleDays, summary.repetitions, summary.totalDays]),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),

      if (_generating) ...[
        const SizedBox(height: Spacing.sm),
        LinearProgressIndicator(value: _indeterminate ? null : _progress),
      ],
    ];
  }
}

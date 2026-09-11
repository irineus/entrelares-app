import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import '../widgets/ui/ui.dart';
import 'package:flutter/services.dart';

import 'package:entrelares_db_contracts/models/care_schedule.dart';
import 'package:entrelares_db_contracts/models/member.dart';
import '../services/analytics_service.dart';
import '../services/custody_data_source.dart';
import '../theme/tokens.dart';
import '../widgets/app_l10n.dart';

/// The Rotation Wizard — mirror of `ScheduleWizard.razor` over the pure rules
/// in `entrelares_core/wizard_rules.dart`: presets, cycle blocks, start date
/// and duration, one handoff time landing only on transitions, the F-39
/// horizon clamp, and the insert-only bulk write that PRESERVES existing days
/// ("criados X, mantidos Y"). Pops with `true` after a successful generation
/// (the caller reloads; the success text is shown inside the sheet, mirror of
/// the web's `isCompleted` view).
Future<bool?> showWizardSheet({
  required BuildContext context,
  required List<Member> activeMembers,
  required DateTime today,
  required CustodyDataSource dataSource,
  DateTime? maxScheduleDate,
  required bool isFreeTier,
  AnalyticsService? analytics,
}) {
  return showAppSheet<bool>(
    context: context,
    builder: (context) => _WizardSheet(
      activeMembers: activeMembers,
      today: today,
      dataSource: dataSource,
      maxScheduleDate: maxScheduleDate,
      isFreeTier: isFreeTier,
      analytics: analytics,
    ),
  );
}

class _WizardSheet extends StatefulWidget {
  final List<Member> activeMembers;
  final DateTime today;
  final CustodyDataSource dataSource;
  final DateTime? maxScheduleDate;
  final bool isFreeTier;

  /// T-37 — optional: the activation signal never gates the generation.
  final AnalyticsService? analytics;

  const _WizardSheet({
    required this.activeMembers,
    required this.today,
    required this.dataSource,
    required this.maxScheduleDate,
    required this.isFreeTier,
    this.analytics,
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
  int _handoffHour = -1;
  int _handoffMinute = 0;
  bool _generating = false;
  bool _completed = false;
  String? _successMessage;
  String? _errorMessage;
  double _progress = 0;

  List<int> get _profileIds =>
      [for (final m in widget.activeMembers) m.id];

  @override
  void initState() {
    super.initState();
    _startDate = dateOnly(widget.today);
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
        handoffTime: _handoffHour >= 0
            ? (hour: _handoffHour, minute: _handoffMinute)
            : null,
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

      final created = await widget.dataSource.bulkInsertNewDays(rows,
          onProgress: (percent) =>
              setState(() => _progress = percent / 100));
      final kept = rows.length - created;

      var message = l.format(K.wizDoneCreated, [created]);
      if (kept > 0) message += l.format(K.wizDoneKept, [kept]);
      if (clampResult.clamped) {
        message += l[
            widget.isFreeTier ? K.wizDoneClampedFree : K.wizDoneClampedMax];
      }
      // T-37: the key activation moment — a family generated its base plan.
      widget.analytics?.trackEvent('wizard_completed',
          props: {'created': created > 0 ? 'yes' : 'none'});
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
      pinnedNotice: _errorMessage == null
          ? null
          : Text('⚠️ $_errorMessage',
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
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

  List<Widget> _successView(Localization l) => [
        Row(
          children: [
            const Text('✅', style: TextStyle(fontSize: 20)),
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
      AppFieldLabel(l[K.wizHandoffTime],
          info: l[K.wizHandoffHint], optionalLabel: l[K.commonOptional]),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: DropdownButtonFormField<int>(
              key: const Key('wizHandoffHour'),
              decoration: InputDecoration(labelText: l[K.editorHourLabel]),
              initialValue: _handoffHour,
              items: [
                const DropdownMenuItem(value: -1, child: Text('--')),
                for (var h = 0; h < 24; h++)
                  DropdownMenuItem(
                      value: h, child: Text(h.toString().padLeft(2, '0'))),
              ],
              onChanged: _generating
                  ? null
                  : (v) => setState(() => _handoffHour = v ?? -1),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: Spacing.sm, vertical: 16),
            child: Text(':'),
          ),
          Expanded(
            child: DropdownButtonFormField<int>(
              key: const Key('wizHandoffMinute'),
              decoration: InputDecoration(labelText: l[K.editorMinuteLabel]),
              initialValue: _handoffMinute,
              items: [
                for (var m = 0; m < 60; m++)
                  DropdownMenuItem(
                      value: m, child: Text(m.toString().padLeft(2, '0'))),
              ],
              onChanged: _generating || _handoffHour < 0
                  ? null
                  : (v) => setState(() => _handoffMinute = v ?? 0),
            ),
          ),
        ],
      ),
          ],
        ),
      ),
      const SizedBox(height: Spacing.sm),

      // ── Preview ──
      //
      // U-28 QA: the cycle summary is the sheet's answer to "what will this
      // actually do", and it was a loose grey sentence at the end of the form.
      AppCard(
        title: l[K.wizCyclePreview],
        child: Text(
          l.format(K.wizCycleSummary,
              [summary.cycleDays, summary.repetitions, summary.totalDays]),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),

      if (_generating) ...[
        const SizedBox(height: Spacing.sm),
        LinearProgressIndicator(value: _progress),
      ],
    ];
  }
}

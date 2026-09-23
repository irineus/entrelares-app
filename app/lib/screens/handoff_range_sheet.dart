import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';

import '../services/custody_data_source.dart';
import '../theme/tokens.dart';
import '../widgets/app_l10n.dart';
import '../widgets/ui/ui.dart';

/// U-55 — "Horário das trocas": one time for every future transition day
/// that has none, in one server call (`set_handoff_time_range`). Opened by the
/// admin from the calendar's strip on a plan born without a handoff time.
///
/// The sheet decides nothing: which days are transitions, which are frozen,
/// which already have a time — the server answers all three, and the counts
/// it returns are the closing line. Pops with that line; the caller shows it
/// and reloads.
Future<String?> showHandoffRangeSheet({
  required BuildContext context,
  required CustodyDataSource dataSource,
  required DateTime today,
}) =>
    showAppSheet<String>(
      context: context,
      builder: (context) =>
          _HandoffRangeSheet(dataSource: dataSource, today: today),
    );

class _HandoffRangeSheet extends StatefulWidget {
  final CustodyDataSource dataSource;
  final DateTime today;

  const _HandoffRangeSheet({required this.dataSource, required this.today});

  @override
  State<_HandoffRangeSheet> createState() => _HandoffRangeSheetState();
}

class _HandoffRangeSheetState extends State<_HandoffRangeSheet> {
  /// No default, like the wizard: a guessed time would be a wrong deadline.
  TimeOfDay? _time;
  String? _fieldError;
  String? _error;
  bool _busy = false;

  Future<void> _apply() async {
    final l = AppL10n.of(context).l;
    final time = _time;
    if (time == null) {
      setState(() => _fieldError = l[K.handoffRangeRequired]);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.dataSource.setHandoffTimeRange(
          dateOnly(widget.today), null, (hour: time.hour, minute: time.minute));
      if (!mounted) return;
      Navigator.of(context).pop(handoffRangeSummary(l, result));
    } catch (e) {
      if (!mounted) return;
      final raw = e.toString();
      setState(() {
        _busy = false;
        _error = isSessionExpired(raw)
            ? sessionExpiredMessage(l)
            : translateSaveError(raw, l[K.errSaveFailed], l);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context).l;
    return AppSheetFrame(
      title: l[K.handoffRangeTitle],
      subtitle: l[K.handoffRangeIntro],
      error: _error,
      primaryLabel: l[K.handoffRangeApply],
      onPrimary: _busy ? null : _apply,
      secondaryLabel: l[K.commonCancel],
      onSecondary: () => Navigator.of(context).pop(),
      busy: _busy,
      children: [
        AppTimeField(
          fieldKey: const Key('handoffRangeTime'),
          label: l[K.wizHandoffTime],
          info: l[K.wizHandoffHint],
          value: _time,
          enabled: !_busy,
          emptyText: l[K.wizHandoffPick],
          clearLabel: l[K.editorHandoffClear],
          errorText: _fieldError,
          formatValue: (t) =>
              l.formatTime(DateTime(2000, 1, 1, t.hour, t.minute)),
          onChanged: (t) => setState(() {
            _time = t;
            if (t != null) _fieldError = null;
          }),
        ),
        const SizedBox(height: Spacing.sm),
      ],
    );
  }
}

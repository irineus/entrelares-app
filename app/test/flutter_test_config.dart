import 'dart:async';

import 'package:entrelares_core/entrelares_core.dart';

/// T-105: the app reads "today" and deadlines on the FAMILY's clock
/// (America/Sao_Paulo). The widget tests build their fixtures' "today" from
/// `DateTime.now()` — the host's clock — so the family clock follows the host
/// here, or a CI runner in UTC would disagree with every fixture between 21:00
/// and midnight in Brasília. `family_time_test` (core) pins the real offset.
///
/// `--dart-define=TEST_TODAY=2026-11-01` (optionally `T13:19`) runs the suite
/// on that day instead of the host's: the screen's clock is
/// [FamilyTime.debugNow] and the calendar fixtures' `today` reads it too. It
/// is how a red that only one calendar day produces is reproduced, and how
/// `tool/date_sweep.sh` proves the date-bound tests on every day of a year.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  FamilyTime.debugOffset = DateTime.now().timeZoneOffset;
  const pinned = String.fromEnvironment('TEST_TODAY');
  if (pinned.isNotEmpty) {
    FamilyTime.debugNow =
        DateTime.parse(pinned.contains('T') ? pinned : '${pinned}T12:00');
  }
  await testMain();
}

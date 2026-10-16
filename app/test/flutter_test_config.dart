import 'dart:async';

import 'package:entrelares_core/entrelares_core.dart';

/// T-105: the app reads "today" and deadlines on the FAMILY's clock
/// (America/Sao_Paulo). The widget tests build their fixtures' "today" from
/// `DateTime.now()` — the host's clock — so the family clock follows the host
/// here, or a CI runner in UTC would disagree with every fixture between 21:00
/// and midnight in Brasília. `family_time_test` (core) pins the real offset.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  FamilyTime.debugOffset = DateTime.now().timeZoneOffset;
  await testMain();
}

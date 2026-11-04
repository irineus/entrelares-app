// The date sweep — the widget suites that read "today", run once per calendar
// day. The scheduled `verify` on `main` went red on days with no code change
// (01/11, 17/10, 11/10, 10/10/2026): each of these suites held on the day it
// was written and broke on a day it was not, because the screen and the
// fixtures read the real clock. Here the family clock is pinned
// ([FamilyTime.debugNow]) to every day of a leap year in turn, and each day's
// group re-declares the suites under it.
//
// Not part of `flutter test` (it lives outside test/ on purpose: 366 days of
// these suites is minutes, not seconds). Run it when a test that reads today
// is added or changed:
//
//   fvm flutter test test_sweep/date_sweep_test.dart
//   fvm flutter test test_sweep/date_sweep_test.dart \
//     --dart-define=SWEEP_FROM=2028-10-01 --dart-define=SWEEP_DAYS=31 \
//     --dart-define=SWEEP_TIME=23:30
import 'package:entrelares_core/entrelares_core.dart';
import 'package:entrelares_db_contracts/models/care_schedule.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test/admin_mode_offer_test.dart' as admin_mode_offer;
import '../test/agenda_validation_test.dart' as agenda_validation;
import '../test/calendar_slice_test.dart' as calendar_slice;
import '../test/calendar_weeks_u62_test.dart' as calendar_weeks_u62;

/// 2028 is a leap year: 366 days, 29/02 among them, and every weekday a
/// month can start on.
const _from = String.fromEnvironment('SWEEP_FROM', defaultValue: '2028-01-01');
const _days = int.fromEnvironment('SWEEP_DAYS', defaultValue: 366);

/// The family's wall-clock time on each day.
const _time = String.fromEnvironment('SWEEP_TIME', defaultValue: '12:00');

void main() {
  // What test/flutter_test_config.dart does for the suite (this directory has
  // none): the family clock follows the host's zone.
  FamilyTime.debugOffset = DateTime.now().timeZoneOffset;
  final first = DateTime.parse('${_from}T$_time');
  for (var i = 0; i < _days; i++) {
    final day = DateTime(
        first.year, first.month, first.day + i, first.hour, first.minute);
    group(CareSchedule.isoDate(day), () {
      setUp(() => FamilyTime.debugNow = day);
      tearDown(() => FamilyTime.debugNow = null);
      admin_mode_offer.main();
      agenda_validation.main();
      calendar_slice.main();
      calendar_weeks_u62.main();
    });
  }
}

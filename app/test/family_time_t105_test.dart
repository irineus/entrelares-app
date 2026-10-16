// T-105 — a deadline on the family's clock says so when this device reads
// another one. The suite runs with the family clock on the HOST's offset
// (flutter_test_config.dart); here it is moved one hour away, as for a parent
// in Manaus.
import 'package:entrelares_app/services/notification_badge.dart';
import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'calendar_slice_test.dart';
import 'frozen_day_test.dart' show swapReq;
import 'notifications_test.dart' show notifApp;

void main() {
  final l = Localization(AppLanguage.ptBr);

  testWidgets('another clock: the pending row\'s deadline names Brasília',
      (tester) async {
    final host = DateTime.now().timeZoneOffset;
    FamilyTime.debugOffset = host + const Duration(hours: 1);
    addTearDown(() => FamilyTime.debugOffset = host);
    final ds = FakeCustodyDataSource(members: [ana, bruno], days: [])
      ..pendingForMe = [swapReq(10, dayOfMonth(28))];
    await tester.pumpWidget(notifApp(ds, NotificationBadge(ds)));
    await tester.pumpAndSettle();
    expect(find.textContaining(l[KApp.familyTimeSuffix]), findsWidgets);
  });

  testWidgets('the same clock: no suffix', (tester) async {
    final ds = FakeCustodyDataSource(members: [ana, bruno], days: [])
      ..pendingForMe = [swapReq(10, dayOfMonth(28))];
    await tester.pumpWidget(notifApp(ds, NotificationBadge(ds)));
    await tester.pumpAndSettle();
    expect(find.textContaining(l[KApp.familyTimeSuffix]), findsNothing);
  });
}

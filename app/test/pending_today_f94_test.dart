// F-94 — a request for TODAY that nobody answered is said on the Hoje card.
//
// Owner, 05/10/2026: on the day, while the request waits, both parties read
// who stays responsible until the answer; the target gets "Responder", the
// requester "Cancelar pedido" — both open the same approval panel. The eve
// reminder is server-side (gate suite `swap_eve_reminder.dart`).
import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:entrelares_app/screens/calendar_screen.dart';

import 'calendar_slice_test.dart';
import 'frozen_day_test.dart' show swapReq;

final pt = Localization(AppLanguage.ptBr);

void main() {
  Finder strip() => find.byKey(CalendarScreen.pendingTodayStripKey);

  testWidgets('the target reads that the carer stays until they answer, and '
      '"Responder" opens the panel', (tester) async {
    // The fake's own profile is the first member: Ana, the target here.
    final ds = FakeCustodyDataSource(
        members: [ana, bruno], days: [row(7, dateOnly(today), ana.id)])
      ..frozenRequests = [
        swapReq(40, dateOnly(today), requesting: bruno.id, target: ana.id,
            proposed: bruno.id)
      ]
      ..pendingForMe = [
        swapReq(40, dateOnly(today), requesting: bruno.id, target: ana.id,
            proposed: bruno.id)
      ];
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();

    expect(strip(), findsOneWidget);
    expect(
        find.descendant(
            of: strip(), matching: find.text(pt[KApp.cardPendingTodayTitle])),
        findsOneWidget);
    expect(
        find.descendant(
            of: strip(),
            matching:
                find.text(pt[KApp.cardPendingTodayYouUntilYou])),
        findsOneWidget,
        reason: 'scenario B: Ana has the day and must answer');
    // The U-60 strip does not repeat today's request.
    expect(find.byKey(CalendarScreen.requestStripKey), findsNothing);

    await tester.tap(find.descendant(
        of: strip(), matching: find.text(pt[KApp.cardRequestsAnswer])));
    await tester.pumpAndSettle();
    expect(find.textContaining(pt[K.frozenSwapTitle]), findsOneWidget);
  });

  testWidgets('the requester reads who stays and is offered to cancel',
      (tester) async {
    final ds = FakeCustodyDataSource(
        members: [ana, bruno], days: [row(7, dateOnly(today), ana.id)])
      ..frozenRequests = [
        swapReq(41, dateOnly(today), requesting: ana.id, target: bruno.id,
            proposed: bruno.id)
      ];
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();

    expect(
        find.descendant(
            of: strip(),
            matching: find.text(
                pt.format(KApp.cardPendingTodayYouStay, ['Bruno']))),
        findsOneWidget);
    expect(
        find.descendant(
            of: strip(), matching: find.text(pt[KApp.cardPendingTodayCancel])),
        findsOneWidget);
  });

  testWidgets('a request for another day draws no day strip', (tester) async {
    final day = futureDay;
    if (day == null) return;
    final ds = FakeCustodyDataSource(
        members: [ana, bruno], days: [row(7, dayOfMonth(day), ana.id)])
      ..frozenRequests = [
        swapReq(42, dayOfMonth(day), requesting: ana.id, target: bruno.id,
            proposed: bruno.id)
      ];
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();
    expect(strip(), findsNothing);
  });
}

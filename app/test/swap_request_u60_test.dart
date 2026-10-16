// U-60 — asking for a swap is explicit, and so is answering one.
//
// The T-103 audit (04/10/2026) saw, on the device: no "Pedir troca" anywhere
// (a request was made by choosing an unlabelled initial under *Responsável
// real*), a button that said "Salvar" while it SENT a request, a row the
// other parent had to decode, and a Hoje card that never mentioned the
// request waiting for them. These pin the way in, the label, the strip and
// the ⋮ entry. The row itself is pinned in `notifications_test.dart`, the
// "Limpar dia" question in `day_editor_test.dart`.
import 'package:entrelares_core/entrelares_core.dart';
import 'package:entrelares_db_contracts/models/member.dart';
import 'package:entrelares_db_contracts/models/role.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:entrelares_app/screens/calendar_screen.dart';
import 'package:entrelares_app/screens/day_sheet.dart';

import 'calendar_slice_test.dart';
import 'frozen_day_test.dart' show swapReq;

final pt = Localization(AppLanguage.ptBr);

void main() {
  testWidgets('"Pedir para outra pessoa ficar com este dia" pre-selects the '
      'other carer, and the button says it sends a request', (tester) async {
    final day = futureDay;
    if (day == null) return;
    final ds = FakeCustodyDataSource(
        members: [ana, bruno], days: [row(7, dayOfMonth(day), ana.id)]);
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();
    await openDayEditor(tester, day);

    expect(find.text(pt[KApp.editorSendRequest]), findsNothing);
    await tapSheet(tester, find.byKey(daySheetAskSwapKey));
    // Bruno is now the real carer of the draft — the field's own choice.
    expect(tester.widget<ChoiceChip>(memberChip('Bruno').last).selected,
        isTrue);
    expect(find.byKey(daySheetAskSwapKey), findsNothing,
        reason: 'once armed, the field below says it');
    await tapSheet(
        tester, find.widgetWithText(FilledButton, pt[KApp.editorSendRequest]));
    expect(ds.createdSwapRequests, hasLength(1));
    expect(ds.createdSwapRequests.single['proposed'], bruno.id);
    expect(find.text(pt[K.toastSwapRequested]), findsOneWidget);
  });

  // Owner's QA of 3.1.10 (06/10/2026): with three or more carers the first
  // of the roster read as a guess. Father and mother swap between themselves;
  // anyone else gets whoever has the child around the day.
  group('who the swap entry pre-selects among three carers', () {
    const roles = [
      Role(id: 1, roleName: 'father'),
      Role(id: 2, roleName: 'mother'),
      Role(id: 3, roleName: 'grandmother'),
    ];
    const pai = Member(
        id: 1, fullName: 'Ana Souza', colorSlot: 1, userId: 'u1', roleId: 1);
    const avo = Member(
        id: 2, fullName: 'Bruno Lima', colorSlot: 2, userId: 'u2', roleId: 3);
    const mae = Member(
        id: 3, fullName: 'Carla Dias', colorSlot: 3, userId: 'u3', roleId: 2);

    Future<void> armOn(WidgetTester tester, FakeCustodyDataSource ds,
        int day) async {
      ds.roles = roles;
      await tester.pumpWidget(app(ds));
      await tester.pumpAndSettle();
      await openDayEditor(tester, day);
      await tapSheet(tester, find.byKey(daySheetAskSwapKey));
    }

    testWidgets("the father's day goes to the mother, even with the "
        'grandmother on the next day', (tester) async {
      final day = futureDay;
      if (day == null ||
          day + 1 > DateUtils.getDaysInMonth(today.year, today.month)) {
        return;
      }
      final ds = FakeCustodyDataSource(members: [
        pai,
        avo,
        mae
      ], days: [
        row(7, dayOfMonth(day), pai.id),
        row(8, dayOfMonth(day + 1), avo.id),
      ]);
      await armOn(tester, ds, day);
      expect(tester.widget<ChoiceChip>(memberChip('Carla').last).selected,
          isTrue);
    });

    testWidgets('without the pair, whoever has the child the next day',
        (tester) async {
      final day = futureDay;
      if (day == null ||
          day + 1 > DateUtils.getDaysInMonth(today.year, today.month)) {
        return;
      }
      // No mother in this family: Ana (father) asks; Bruno is first in the
      // roster, Carla (no role) has the next day.
      const carla = Member(
          id: 3, fullName: 'Carla Dias', colorSlot: 3, userId: 'u3');
      final ds = FakeCustodyDataSource(members: [
        pai,
        avo,
        carla
      ], days: [
        row(7, dayOfMonth(day), pai.id),
        row(8, dayOfMonth(day + 1), carla.id),
      ]);
      await armOn(tester, ds, day);
      expect(tester.widget<ChoiceChip>(memberChip('Carla').last).selected,
          isTrue);
      expect(tester.widget<ChoiceChip>(memberChip('Bruno').last).selected,
          isFalse);
    });
  });

  testWidgets('a day already swapped offers no new request entry',
      (tester) async {
    final day = futureDay;
    if (day == null) return;
    final ds = FakeCustodyDataSource(members: [
      ana,
      bruno
    ], days: [
      row(7, dayOfMonth(day), ana.id, actual: bruno.id),
    ]);
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();
    await openDayEditor(tester, day);
    expect(find.byKey(daySheetAskSwapKey), findsNothing);
  });

  testWidgets('the ⋮ "Pedir troca de um dia" asks which day and opens its '
      'sheet with the request armed', (tester) async {
    final ds = FakeCustodyDataSource(
        members: [ana, bruno], days: [row(7, dateOnly(today), ana.id)]);
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(CalendarScreen.askSwapMenuKey));
    await tester.pumpAndSettle();
    expect(find.text(pt[KApp.calAskSwapPick]), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FilledButton, pt[KApp.editorSendRequest]),
        findsOneWidget,
        reason: 'the day sheet opened with the request already armed');
  });

  testWidgets('the Hoje card names the request waiting for MY answer, and '
      '"Responder" opens its approval panel', (tester) async {
    final day = futureDay ?? today.day;
    final ds = FakeCustodyDataSource(
        members: [ana, bruno], days: [row(7, dateOnly(today), ana.id)])
      ..pendingForMe = [swapReq(31, dayOfMonth(day), message: 'Viagem')];
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();

    final strip = find.byKey(CalendarScreen.requestStripKey);
    expect(strip, findsOneWidget);
    // Owner's QA of 3.1.10: one request is one line — the sentence and
    // "Responder" — with no title over it.
    expect(
        find.descendant(
            of: strip,
            matching: find.text(swapRequestSentence(
                l: pt,
                requesterName: 'Bruno',
                date: dayOfMonth(day),
                isRevert: false,
                requesterIsProposed: false))),
        findsOneWidget);
    await tester.tap(find.descendant(
        of: strip, matching: find.text(pt[KApp.cardRequestsAnswer])));
    await tester.pumpAndSettle();
    expect(find.textContaining(pt[K.frozenSwapTitle]), findsOneWidget);
  });

  testWidgets('several requests are one line that says how many and opens '
      'the list', (tester) async {
    final day = futureDay ?? today.day;
    final ds = FakeCustodyDataSource(
        members: [ana, bruno], days: [row(7, dateOnly(today), ana.id)])
      ..pendingForMe = [
        swapReq(31, dayOfMonth(day), message: 'Viagem'),
        swapReq(32, dayOfMonth(day), message: 'Consulta'),
      ];
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();
    final strip = find.byKey(CalendarScreen.requestStripKey);
    expect(
        find.descendant(
            of: strip, matching: find.text(pt.format(KApp.cardRequestsMany, [2]))),
        findsOneWidget);
    expect(
        find.descendant(of: strip, matching: find.text(pt[KApp.cardRequestsSee])),
        findsOneWidget);
    // One row: the action sits beside the sentence, not under it.
    expect(tester.getSize(strip).height, lessThan(60));
  });

  testWidgets('no request waiting: the Hoje card grows by nothing',
      (tester) async {
    final ds = FakeCustodyDataSource(
        members: [ana, bruno], days: [row(7, dateOnly(today), ana.id)]);
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();
    expect(find.byKey(CalendarScreen.requestStripKey), findsNothing);
  });
}

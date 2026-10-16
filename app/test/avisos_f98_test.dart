// F-98 — avisos on the Hoje card: mine never hides theirs, the author reads
// herself in the second person, and "Avisar" sits on the card.
//
// The T-103 audit (04/10/2026): at 8:00 Mom sent "Só avisando: consulta
// médica"; at 16:30 Dad asked "alguém pode buscar a criança?" — and Mom's card
// showed only "Seu aviso de hoje está aberto", with Dad's question and its
// "Responder" hidden. When an aviso closes is still F-52's rule.
import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:entrelares_db_contracts/models/care_schedule.dart';
import 'package:entrelares_db_contracts/models/day_notice.dart';
import 'package:entrelares_app/screens/calendar_screen.dart';

import 'calendar_slice_test.dart';

final _pt = Localization(AppLanguage.ptBr);

DayNotice _notice({
  required int id,
  required int sender,
  String reason = 'atraso',
  int? eta,
  String request = 'pickup',
}) =>
    DayNotice.fromJson({
      'id': id,
      'family_id': 1,
      'schedule_date': CareSchedule.isoDate(today),
      'sender_profile_id': sender,
      'reason': reason,
      'eta_minutes': eta,
      'request': request,
      'note': null,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'day_notice_outcomes': <dynamic>[],
    });

void main() {
  testWidgets('with both open, theirs (the one asking) comes first and keeps '
      'its "Responder"; mine follows, in the second person', (tester) async {
    final ds = FakeCustodyDataSource(
        members: [ana, bruno], days: [row(1, dayOfMonth(today.day), ana.id)])
      ..dayNotices = [
        _notice(id: 1, sender: ana.id, request: 'info', eta: 15),
        _notice(id: 2, sender: bruno.id, request: 'pickup'),
      ];
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();

    final theirs = find.byKey(const ValueKey('notice-strip-2'));
    final mine = find.byKey(const ValueKey('notice-strip-1'));
    expect(theirs, findsOneWidget);
    expect(mine, findsOneWidget);
    expect(tester.getTopLeft(theirs).dy, lessThan(tester.getTopLeft(mine).dy),
        reason: 'the aviso that asks for an answer comes first');
    expect(
        find.descendant(
            of: theirs, matching: find.text(_pt[KApp.noticeAnswerTitle])),
        findsOneWidget);
    expect(
        find.descendant(
            of: mine, matching: find.textContaining('Você avisou que')),
        findsOneWidget);
    expect(find.descendant(of: mine, matching: find.textContaining('Ana Souza')),
        findsNothing,
        reason: 'the author never reads her own name in the third person');
  });

  testWidgets('nothing open: the card offers "Avisar" to today\'s carer',
      (tester) async {
    final ds = FakeCustodyDataSource(
        members: [ana, bruno], days: [row(1, dayOfMonth(today.day), ana.id)]);
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();
    final avisar = find.byKey(CalendarScreen.noticeQuickActionKey);
    expect(avisar, findsOneWidget);
    await tester.tap(avisar);
    await tester.pumpAndSettle();
    expect(find.text(_pt[KApp.noticeTitle]), findsOneWidget,
        reason: 'the same aviso sheet the ⋮ opens');
  });

  testWidgets('a carer with no part in today gets no "Avisar"', (tester) async {
    // Bruno reads (first member); Ana has today and tomorrow — no handoff.
    final ds = FakeCustodyDataSource(members: [
      bruno,
      ana
    ], days: [
      row(1, dayOfMonth(today.day), ana.id),
      if (futureDay != null) row(2, dayOfMonth(futureDay!), ana.id),
    ]);
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();
    if (futureDay == null) return;
    expect(find.byKey(CalendarScreen.noticeQuickActionKey), findsNothing);
  });
}

// F-52 — the aviso de imprevisto, against the fake data source.
//
// What is worth a widget test here is not "the sheet renders": it is the two
// places where a wrong pixel costs a real day.
//
// 1. **The action is offered to the day's three ends and to nobody else.** The
//    server refuses the rest, but an action that always ends in a refusal is a
//    worse product than no action, and the rule is computed from three
//    different rows.
// 2. **Stating an estimate takes "alguém pode ficar com a criança" off the
//    table, and SAYS SO.** That is the whole safety argument of the item: an
//    aviso with a deadline can never hand today to whoever answers. If the
//    option stayed tappable — or vanished with no sentence — the sender would
//    either give the day away by accident or go looking for a feature they
//    were told about.
import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:entrelares_db_contracts/models/care_schedule.dart';
import 'package:entrelares_db_contracts/models/day_notice.dart';

import 'calendar_slice_test.dart';

final _pt = Localization(AppLanguage.ptBr);

DayNotice _notice({
  int id = 1,
  int sender = 1,
  String reason = 'transito',
  int? eta,
  String request = 'pickup',
  String? note,
  String? outcome,
}) =>
    DayNotice.fromJson({
      'id': id,
      'family_id': 1,
      'schedule_date': CareSchedule.isoDate(today),
      'sender_profile_id': sender,
      'reason': reason,
      'eta_minutes': eta,
      'request': request,
      'note': note,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'day_notice_outcomes': outcome == null
          ? <dynamic>[]
          : [
              {
                'outcome': outcome,
                'actor_profile_id': sender,
                'created_at': DateTime.now().toUtc().toIso8601String(),
              }
            ],
    });

Future<void> _openMenu(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.more_vert));
  await tester.pumpAndSettle();
}

/// Opens the ⋮ menu and taps "Enviar um aviso".
Future<void> _openNoticeSheet(WidgetTester tester) async {
  await _openMenu(tester);
  await tester.tap(find.text(_pt[KApp.noticeAction]));
  await tester.pumpAndSettle();
}

void main() {
  group('who is offered the action', () {
    // Ana has today. She is the most obvious end and the only one who may put
    // the day itself on offer.
    testWidgets('today\'s carer is offered it', (tester) async {
      final ds = FakeCustodyDataSource(
          members: [ana, bruno], days: [row(1, dayOfMonth(today.day), 1)]);
      await tester.pumpWidget(app(ds));
      await tester.pumpAndSettle();
      await _openMenu(tester);
      expect(find.text(_pt[KApp.noticeAction]), findsOneWidget);
    });

    // Nobody's day, no next handoff, no yesterday: Ana is not an end of
    // anything, so the menu must not carry an action the server would refuse.
    testWidgets('a carer with no part in the day is not', (tester) async {
      final ds = FakeCustodyDataSource(members: [ana, bruno], days: const []);
      await tester.pumpWidget(app(ds));
      await tester.pumpAndSettle();
      await _openMenu(tester);
      expect(find.text(_pt[KApp.noticeAction]), findsNothing);
    });

    // Today is Bruno's; the next different day is Ana's. Ana is the one
    // COLLECTING at the next handover, and that is an end — this is the case
    // the card's own file list would have missed, because Ana appears nowhere
    // in today's row.
    testWidgets('the carer of the next handoff is', (tester) async {
      final tomorrow = today.day + 1 >
              DateTime(today.year, today.month + 1, 0).day
          ? null
          : today.day + 1;
      if (tomorrow == null) return;
      final ds = FakeCustodyDataSource(members: [ana, bruno], days: [
        row(1, dayOfMonth(today.day), 2),
        row(2, dayOfMonth(tomorrow), 1),
      ]);
      await tester.pumpWidget(app(ds));
      await tester.pumpAndSettle();
      await _openMenu(tester);
      expect(find.text(_pt[KApp.noticeAction]), findsOneWidget);
    });
  });

  group('the sheet says what each choice will do', () {
    testWidgets('an estimate blocks "ficar com a criança" AND explains it',
        (tester) async {
      final ds = FakeCustodyDataSource(
          members: [ana, bruno], days: [row(1, dayOfMonth(today.day), 1)]);
      await tester.pumpWidget(app(ds));
      await tester.pumpAndSettle();
      await _openNoticeSheet(tester);

      // The sheet opens on the shortest estimate, so the day is NOT on offer
      // and the row says exactly why rather than disappearing.
      expect(find.text(_pt[KApp.noticeRequestKeep]), findsOneWidget);
      expect(find.text(_pt[KApp.noticeConsequenceKeepBlocked]), findsOneWidget);
      expect(find.text(_pt[KApp.noticeConsequenceKeep]), findsNothing);

      // "Sem previsão" is what unlocks it — and then the consequence becomes
      // the promise the owner asked to be spelled out: an already-approved
      // swap, with no second confirmation.
      await tester.tap(find.widgetWithText(ChoiceChip, _pt[KApp.noticeEtaNone]));
      await tester.pumpAndSettle();
      expect(find.text(_pt[KApp.noticeConsequenceKeep]), findsOneWidget);
      expect(find.text(_pt[KApp.noticeConsequenceKeepBlocked]), findsNothing);
    });

    // Today is Bruno's. Ana may warn (she collects next), but the day is not
    // hers to give — a different fact from "you stated an estimate", and it
    // reads as a different sentence.
    testWidgets('somebody else\'s day blocks it for another reason',
        (tester) async {
      final tomorrow = today.day + 1 >
              DateTime(today.year, today.month + 1, 0).day
          ? null
          : today.day + 1;
      if (tomorrow == null) return;
      final ds = FakeCustodyDataSource(members: [ana, bruno], days: [
        row(1, dayOfMonth(today.day), 2),
        row(2, dayOfMonth(tomorrow), 1),
      ]);
      await tester.pumpWidget(app(ds));
      await tester.pumpAndSettle();
      await _openNoticeSheet(tester);

      await tester.tap(find.widgetWithText(ChoiceChip, _pt[KApp.noticeEtaNone]));
      await tester.pumpAndSettle();
      expect(
          find.text(_pt[KApp.noticeConsequenceKeepNotMyDay]), findsOneWidget);
      expect(find.text(_pt[KApp.noticeConsequenceKeep]), findsNothing);
    });

    // Selecting the day-offering request and THEN stating an estimate must not
    // leave an impossible pair armed behind a disabled row.
    testWidgets('choosing an estimate after "ficar" falls back to "buscar"',
        (tester) async {
      final ds = FakeCustodyDataSource(
          members: [ana, bruno], days: [row(1, dayOfMonth(today.day), 1)]);
      await tester.pumpWidget(app(ds));
      await tester.pumpAndSettle();
      await _openNoticeSheet(tester);

      await tester.tap(find.widgetWithText(ChoiceChip, _pt[KApp.noticeEtaNone]));
      await tester.pumpAndSettle();
      await tester.tap(find.text(_pt[KApp.noticeRequestKeep]));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(
          ChoiceChip, _pt.format(KApp.noticeEtaMinutes, [30])));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, _pt[KApp.noticeSend]));
      await tester.pumpAndSettle();
      expect(ds.sentNotices.single.request, 'pickup');
      expect(ds.sentNotices.single.etaMinutes, 30);
    });
  });

  testWidgets('sending carries the wire values, never a sentence',
      (tester) async {
    final ds = FakeCustodyDataSource(
        members: [ana, bruno], days: [row(1, dayOfMonth(today.day), 1)]);
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();
    await _openNoticeSheet(tester);

    await tester
        .tap(find.widgetWithText(ChoiceChip, _pt[KApp.noticeReasonTraffic]));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(
        ChoiceChip, _pt.format(KApp.noticeEtaMinutes, [60])));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_pt[KApp.noticeRequestPickup]));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'na Marginal');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, _pt[KApp.noticeSend]));
    await tester.pumpAndSettle();

    final sent = ds.sentNotices.single;
    expect(sent.reason, 'transito');
    expect(sent.etaMinutes, 60);
    expect(sent.request, 'pickup');
    expect(sent.note, 'na Marginal');
  });

  group('the strip on the Hoje card', () {
    // The half of the owner's answer the card keeps: an aviso that is OPEN
    // earns the height, and it says the same sentence the notification does.
    testWidgets('somebody else\'s open aviso is read on the card',
        (tester) async {
      final ds = FakeCustodyDataSource(
          members: [ana, bruno], days: [row(1, dayOfMonth(today.day), 1)])
        ..dayNotices = [_notice(sender: 2, reason: 'medico', request: 'pickup')];
      await tester.pumpWidget(app(ds));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Bruno Lima avisou que teve um imprevisto médico'),
        findsOneWidget,
      );
    });

    testWidgets('my own open aviso offers the way to withdraw it',
        (tester) async {
      final ds = FakeCustodyDataSource(
          members: [ana, bruno], days: [row(1, dayOfMonth(today.day), 1)])
        ..dayNotices = [_notice(sender: 1)];
      await tester.pumpWidget(app(ds));
      await tester.pumpAndSettle();

      expect(find.text(_pt[KApp.noticeOpenMine]), findsOneWidget);
      await tester.tap(find.text(_pt[KApp.noticeCancel]).last);
      await tester.pumpAndSettle();

      // U-38: the question replaces the action row, and it says the two things
      // a person would otherwise learn by surprise — the others are told, and
      // the cap does not give the slot back.
      expect(find.text(_pt[KApp.noticeCancelConfirm]), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, _pt[KApp.noticeCancel]));
      await tester.pumpAndSettle();
      expect(ds.cancelledNotices, [1]);
    });

    // An answered or withdrawn aviso is history, not a live call for help.
    testWidgets('a closed aviso shows no strip', (tester) async {
      final ds = FakeCustodyDataSource(
          members: [ana, bruno], days: [row(1, dayOfMonth(today.day), 1)])
        ..dayNotices = [_notice(sender: 2, outcome: 'cancelled')];
      await tester.pumpWidget(app(ds));
      await tester.pumpAndSettle();
      expect(find.textContaining('avisou que'), findsNothing);
    });

    // While mine is open, the menu stops offering a second one: the strip is
    // where that aviso is dealt with.
    testWidgets('an open aviso of mine removes the menu action',
        (tester) async {
      final ds = FakeCustodyDataSource(
          members: [ana, bruno], days: [row(1, dayOfMonth(today.day), 1)])
        ..dayNotices = [_notice(sender: 1)];
      await tester.pumpWidget(app(ds));
      await tester.pumpAndSettle();
      await _openMenu(tester);
      expect(find.text(_pt[KApp.noticeAction]), findsNothing);
    });
  });

  // The cap is stated before it blocks — a limit that only announces itself by
  // refusing reads as a bug.
  testWidgets('the cap is said, then it blocks', (tester) async {
    final ds = FakeCustodyDataSource(
        members: [ana, bruno], days: [row(1, dayOfMonth(today.day), 1)])
      ..dayNotices = [
        _notice(id: 1, sender: 1, outcome: 'cancelled'),
        _notice(id: 2, sender: 1, outcome: 'cancelled'),
      ];
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();
    await _openNoticeSheet(tester);

    expect(
      find.text(
          _pt.format(KApp.noticeCapReached, [noticeMaxPerSenderPerDay])),
      findsOneWidget,
    );
    final send = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, _pt[KApp.noticeSend]));
    expect(send.onPressed, isNull);
    expect(ds.sentNotices, isEmpty);
  });
}

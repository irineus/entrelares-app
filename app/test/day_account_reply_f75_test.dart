// F-75 — the reply to a relato in the day sheet and in the Histórico,
// against the fake data source. What the tests pin: another caregiver's
// relato offers "Responder" (the module on), the reader's own does not, a
// Visualizador is never offered it and the flag off hides it; the reply is
// recorded under the relato it answers; the second text is a CORRECTION,
// never an edit, and the corrected one stays struck, saying when.
import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:entrelares_app/screens/day_sheet.dart';
import 'package:entrelares_db_contracts/models/day_account_reply.dart';
import 'package:entrelares_db_contracts/models/member.dart';

import 'calendar_slice_test.dart';
import 'day_account_test.dart' show account;

final pt = Localization(AppLanguage.ptBr);
const on = {'feature.day_account_replies': 'true'};

Finder replyButton(int accountId) => find.byKey(Key(daySheetReplyKey(accountId)));
Finder get saveReply => find.text(pt[KApp.dayAccountReplySave]);

FakeCustodyDataSource source(int yesterday,
        {List<Member>? members, Map<String, String> settings = on}) =>
    FakeCustodyDataSource(
        members: members ?? [ana, bruno],
        days: [row(7, dayOfMonth(yesterday), 2)])
      ..publicSettings = settings
      // Bruno's relato about yesterday, written an hour ago.
      ..dayAccounts = [
        account(500, dayOfMonth(yesterday), 2, 'Buscou às 17h.',
            at: DateTime.now().subtract(const Duration(hours: 1))),
      ];

Future<void> replyWith(WidgetTester tester, String text) async {
  await tapSheet(tester, replyButton(500));
  await tester.enterText(
      find.descendant(
          of: find.byKey(daySheetReplyFieldKey),
          matching: find.byType(TextField)),
      text);
  await tester.pump();
  await tapSheet(tester, saveReply);
}

void main() {
  testWidgets('the other caregiver answers a relato, under the relato it '
      'answers, and it never touches the day', (tester) async {
    if (today.day == 1) return; // yesterday is last month
    final yesterday = today.day - 1;
    final ds = source(yesterday);
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();
    await openDay(tester, yesterday);

    expect(replyButton(500), findsOneWidget);
    await tapSheet(tester, replyButton(500));
    // The relato being answered, and the sentence that cannot be undone.
    expect(find.text('Buscou às 17h.'), findsOneWidget);
    expect(find.text(pt[KApp.dayAccountReplyAppendOnly]), findsOneWidget);
    await tester.enterText(
        find.descendant(
            of: find.byKey(daySheetReplyFieldKey),
            matching: find.byType(TextField)),
        '  Foi às 18h.  ');
    await tester.pump();
    await tapSheet(tester, saveReply);

    final saved = ds.dayAccountReplies.single;
    expect(saved.accountId, 500);
    expect(saved.body, 'Foi às 18h.');
    expect(saved.correctsId, isNull);
    expect(ds.updated, isEmpty, reason: 'a reply never writes the day');
    expect(ds.inserted, isEmpty);

    expect(find.text('Foi às 18h.'), findsOneWidget);
    expect(find.textContaining('Resposta de Ana Souza'), findsOneWidget);
    // Answered once: the second text is a correction, not a second reply.
    expect(replyButton(500), findsNothing);
    await settleSnack(tester);
  });

  testWidgets('an empty reply is refused upfront, nothing written',
      (tester) async {
    if (today.day == 1) return;
    final yesterday = today.day - 1;
    final ds = source(yesterday);
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();
    await openDay(tester, yesterday);
    await replyWith(tester, '   ');
    expect(ds.dayAccountReplies, isEmpty);
    expect(find.text(pt[KApp.dayAccountReplyErrEmpty]), findsOneWidget);
  });

  testWidgets('a reply is CORRECTED, never edited: both stay, the first struck',
      (tester) async {
    if (today.day == 1) return;
    final yesterday = today.day - 1;
    final ds = source(yesterday)
      ..dayAccountReplies = [
        DayAccountReply(
          id: 70,
          familyId: 1,
          accountId: 500,
          authorProfileId: 1,
          body: 'Foi às 18h.',
          createdAt: DateTime.now().toUtc(),
        ),
      ];
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();
    await openDay(tester, yesterday);

    final correct = find.byKey(Key(daySheetCorrectReplyKey(70)));
    expect(correct, findsOneWidget);
    await tapSheet(tester, correct);
    await tester.enterText(
        find.descendant(
            of: find.byKey(daySheetReplyFieldKey),
            matching: find.byType(TextField)),
        'Foi às 18h10.');
    await tester.pump();
    await tapSheet(tester, saveReply);

    expect(ds.dayAccountReplies, hasLength(2));
    expect(ds.dayAccountReplies.last.correctsId, 70);
    expect(find.text('Foi às 18h.'), findsOneWidget);
    expect(find.text('Foi às 18h10.'), findsOneWidget);
    expect(find.textContaining('Corrigido em'), findsOneWidget);
    // Once: neither text offers a second correction.
    expect(correct, findsNothing);
    await settleSnack(tester);
  });

  testWidgets('the relato\'s own author is never offered a reply to it',
      (tester) async {
    if (today.day == 1) return;
    final yesterday = today.day - 1;
    final ds = source(yesterday, members: [bruno, ana]);
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();
    await openDay(tester, yesterday);
    expect(find.text('Buscou às 17h.'), findsOneWidget);
    expect(replyButton(500), findsNothing);
  });

  testWidgets('with the module off there is no reply button', (tester) async {
    if (today.day == 1) return;
    final yesterday = today.day - 1;
    final ds = source(yesterday, settings: const {});
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();
    await openDay(tester, yesterday);
    expect(find.text('Buscou às 17h.'), findsOneWidget);
    expect(replyButton(500), findsNothing);
  });

  testWidgets('a Visualizador reads the reply and is never offered one',
      (tester) async {
    if (today.day == 1) return;
    final yesterday = today.day - 1;
    const vera = Member(
        id: 3,
        fullName: 'Vera Vó',
        userId: 'u3',
        membershipType: 'viewer');
    final ds = source(yesterday, members: [vera, ana, bruno])
      ..dayAccountReplies = [
        DayAccountReply(
          id: 71,
          familyId: 1,
          accountId: 500,
          authorProfileId: 1,
          body: 'Foi às 18h.',
          createdAt: DateTime.now().toUtc(),
        ),
      ];
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();
    await openDay(tester, yesterday);
    expect(find.text('Foi às 18h.'), findsOneWidget);
    expect(replyButton(500), findsNothing);
  });
}

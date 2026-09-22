// F-67 Part A — the relato do dia in the day sheet, against the fake data
// source. What the tests pin: a past day inside the window offers "Relatar o
// que aconteceu" to the member; the relato is recorded without touching the
// day; an empty text is refused upfront; a relato the reader wrote can be
// CORRECTED (never edited), and the corrected one stays, struck, saying when;
// somebody else's relato offers no correction; today offers no relato; the
// daily cap is said before it blocks.
import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:entrelares_app/screens/day_sheet.dart';
import 'package:entrelares_db_contracts/models/day_account.dart';

import 'calendar_slice_test.dart';

final pt = Localization(AppLanguage.ptBr);

DayAccount account(int id, DateTime date, int author, String body,
        {int? corrects, DateTime? at}) =>
    DayAccount(
      id: id,
      familyId: 1,
      accountDate: DateTime(date.year, date.month, date.day),
      authorProfileId: author,
      body: body,
      correctsId: corrects,
      createdAt: (at ?? DateTime.now()).toUtc(),
    );

Future<void> report(WidgetTester tester, String text) async {
  await tapSheet(tester, reportButton);
  await tester.enterText(find.descendant(
      of: find.byKey(daySheetReportFieldKey),
      matching: find.byType(TextField)), text);
  await tester.pump();
}

Finder get reportButton => find.text(pt[KApp.dayAccountAction]);
Finder get saveButton => find.text(pt[KApp.dayAccountSave]);

void main() {
  testWidgets('a past day offers the relato and records it, the day untouched',
      (tester) async {
    if (today.day == 1) return; // yesterday is last month
    final yesterday = today.day - 1;
    final ds = FakeCustodyDataSource(
        members: [ana, bruno], days: [row(7, dayOfMonth(yesterday), 2)]);
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();

    await openDay(tester, yesterday);
    expect(find.text(pt[K.editorPastReadonly]), findsOneWidget);
    expect(reportButton, findsOneWidget);

    await tapSheet(tester, reportButton);
    // The sentence that cannot be undone, said BEFORE the tap.
    expect(find.text(pt[KApp.dayAccountAppendOnly]), findsOneWidget);
    await tester.enterText(
        find.descendant(
            of: find.byKey(daySheetReportFieldKey),
            matching: find.byType(TextField)),
        '  Bruno buscou no aeroporto às 17h  ');
    await tapSheet(tester, saveButton);

    final saved = ds.dayAccounts.single;
    expect(saved.body, 'Bruno buscou no aeroporto às 17h');
    expect(saved.correctsId, isNull);
    expect(saved.accountDate, dayOfMonth(yesterday));
    expect(ds.updated, isEmpty, reason: 'a relato never writes the day');
    expect(ds.inserted, isEmpty);

    // Back on the summary, with the relato and its dated byline.
    expect(find.text('Bruno buscou no aeroporto às 17h'), findsOneWidget);
    expect(find.text(pt[KApp.dayAccountSection]), findsOneWidget);
    expect(find.textContaining('Registrado por Ana Souza'), findsOneWidget);
    await settleSnack(tester);
  });

  testWidgets('an empty relato is refused upfront, nothing written',
      (tester) async {
    if (today.day == 1) return;
    final yesterday = today.day - 1;
    final ds = FakeCustodyDataSource(members: [ana, bruno], days: []);
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();

    await openDay(tester, yesterday);
    await tapSheet(tester, reportButton);
    await tapSheet(tester, saveButton);
    expect(find.text(pt[KApp.dayAccountErrEmpty]), findsOneWidget);
    expect(ds.dayAccounts, isEmpty);
  });

  testWidgets('my relato is corrected — never edited — and the old one stays '
      'struck, saying when', (tester) async {
    if (today.day == 1) return;
    final yesterday = today.day - 1;
    final ds = FakeCustodyDataSource(members: [ana, bruno], days: [])
      ..dayAccounts = [
        account(1, dayOfMonth(yesterday), 1, 'buscou às 17h',
            at: DateTime.now().subtract(const Duration(hours: 2))),
        account(2, dayOfMonth(yesterday), 2, 'foi às 18h',
            at: DateTime.now().subtract(const Duration(hours: 1))),
      ];
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();

    await openDay(tester, yesterday);
    // Mine can be corrected; Bruno's cannot — he wrote it.
    expect(find.byKey(Key(daySheetCorrectAccountKey(1))), findsOneWidget);
    expect(find.byKey(Key(daySheetCorrectAccountKey(2))), findsNothing);

    await tapSheet(tester, find.byKey(Key(daySheetCorrectAccountKey(1))));
    // The field starts from the text being corrected.
    expect(find.widgetWithText(TextField, 'buscou às 17h'), findsOneWidget);
    await tester.enterText(
        find.descendant(
            of: find.byKey(daySheetReportFieldKey),
            matching: find.byType(TextField)),
        'buscou às 17h30');
    await tapSheet(tester, saveButton);

    final fix = ds.dayAccounts.last;
    expect(fix.correctsId, 1);
    expect(ds.dayAccounts, hasLength(3), reason: 'both texts stay');

    final old = tester.widget<Text>(find.text('buscou às 17h'));
    expect(old.style?.decoration, TextDecoration.lineThrough);
    expect(find.textContaining('Corrigido em'), findsOneWidget);
    // A corrected relato is not offered for a second correction.
    expect(find.byKey(Key(daySheetCorrectAccountKey(1))), findsNothing);
    expect(find.byKey(Key(daySheetCorrectAccountKey(fix.id))), findsOneWidget);
    await settleSnack(tester);
  });

  testWidgets('today offers no relato — it has the Observação and the aviso',
      (tester) async {
    final ds = FakeCustodyDataSource(
        members: [ana, bruno], days: [row(7, dayOfMonth(today.day), 1)]);
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();

    await openDay(tester, today.day);
    expect(reportButton, findsNothing);
  });

  testWidgets('the cap is said before it blocks, and at the cap the save is '
      'gone', (tester) async {
    if (today.day == 1) return;
    final yesterday = today.day - 1;
    final ds = FakeCustodyDataSource(members: [ana, bruno], days: [])
      ..writtenToday = 8;
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();

    await openDay(tester, yesterday);
    await tapSheet(tester, reportButton);
    expect(find.text(pt.format(KApp.dayAccountCapLeftMany, [2])),
        findsOneWidget);
    await tapSheet(tester, find.text(pt[K.commonCancel]).last);

    ds.writtenToday = 10;
    await tapSheet(tester, reportButton);
    expect(find.text(pt.format(KApp.dayAccountCapReached, [10])),
        findsOneWidget);
    final save = tester.widget<FilledButton>(
        find.ancestor(of: saveButton, matching: find.byType(FilledButton)));
    expect(save.onPressed, isNull);
  });

  testWidgets('a server refusal is shown in the sheet, the draft kept',
      (tester) async {
    if (today.day == 1) return;
    final yesterday = today.day - 1;
    final ds = FakeCustodyDataSource(members: [ana, bruno], days: [])
      ..throwOnDayAccount = Exception('{"code":"23514","message":"Relatos '
          'podem ser registrados até 30 dias depois do dia."}');
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();

    await openDay(tester, yesterday);
    await report(tester, 'algo');
    await tapSheet(tester, saveButton);
    expect(find.textContaining('até 30 dias depois do dia'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'algo'), findsOneWidget);
  });
}

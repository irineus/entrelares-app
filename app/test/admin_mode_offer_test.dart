// F-67 Part B — the admin mode offered where it is needed, against the fake
// data source. What the tests pin, per entry point of `AdminModeAction`: an
// ADMIN with the mode off is ASKED (never switched silently), "Ativar" turns
// the mode on and carries the action through in the same sheet, "Cancelar"
// leaves everything as it was, and a member who is not an admin never sees
// the question. The F-40 gate and limit replace the question on a past day
// the mode would not reach.
import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:entrelares_app/screens/day_sheet.dart';
import 'package:entrelares_app/services/admin_mode.dart';
import 'package:entrelares_app/widgets/admin_mode_offer.dart';
import 'package:entrelares_db_contracts/models/family.dart';
import 'package:entrelares_db_contracts/models/member.dart';

import 'bulk_edit_test.dart' show longPressDay;
import 'calendar_slice_test.dart';

const anaAdmin = Member(
    id: 1, fullName: 'Ana Souza', colorSlot: 1, userId: 'u1', isAdmin: true);

final pt = Localization(AppLanguage.ptBr);

const premium = Family(id: 1, name: 'Família', plan: 'premium');
const free = Family(id: 1, name: 'Família', plan: 'free');

Finder get offer => find.byKey(adminModeOfferKey);

Future<void> activate(WidgetTester tester) =>
    tapSheet(tester, find.text(pt[K.navAdminEnter]).last);

Future<void> openMenu(WidgetTester tester) async {
  await tester.tap(find.byTooltip(pt[K.calActionsMenu]));
  await tester.pumpAndSettle();
}

void main() {
  group('past day', () {
    testWidgets('an admin with the mode off is asked, and "Ativar" opens the '
        'editor in the same sheet', (tester) async {
      if (today.day == 1) return; // yesterday is last month
      final yesterday = today.day - 1;
      final mode = AdminMode();
      final ds = FakeCustodyDataSource(
          members: [anaAdmin, bruno], days: [row(7, dayOfMonth(yesterday), 1)])
        ..family = premium;
      await tester.pumpWidget(app(ds, adminMode: mode));
      await tester.pumpAndSettle();

      await openDay(tester, yesterday);
      expect(find.text(pt[K.editorPastReadonly]), findsOneWidget);
      expect(find.byKey(daySheetEditKey), findsNothing);
      expect(offer, findsNothing);

      await tapSheet(tester, find.byKey(daySheetCorrectPlanKey));
      expect(offer, findsOneWidget);
      // The question names the action and what the record will print.
      expect(find.text(pt[KApp.adminOfferEditPastDay]), findsOneWidget);
      expect(mode.isActive, isFalse, reason: 'asking is not switching');

      await activate(tester);
      expect(mode.isActive, isTrue);
      expect(offer, findsNothing);
      // The editor, with the override banner — the sheet never closed.
      expect(find.text(pt[K.editorAdminOverride]), findsOneWidget);
      expect(find.text(pt[K.commonSave]), findsOneWidget);
    });

    testWidgets('"Cancelar" leaves the mode off and the summary as it was',
        (tester) async {
      if (today.day == 1) return;
      final yesterday = today.day - 1;
      final mode = AdminMode();
      final ds = FakeCustodyDataSource(
          members: [anaAdmin, bruno], days: [row(7, dayOfMonth(yesterday), 1)])
        ..family = premium;
      await tester.pumpWidget(app(ds, adminMode: mode));
      await tester.pumpAndSettle();

      await openDay(tester, yesterday);
      await tapSheet(tester, find.byKey(daySheetCorrectPlanKey));
      await tapSheet(tester, find.text(pt[K.commonCancel]).last);

      expect(mode.isActive, isFalse);
      expect(offer, findsNothing);
      expect(find.byKey(daySheetCorrectPlanKey), findsOneWidget);
      expect(find.text(pt[K.commonSave]), findsNothing);
    });

    testWidgets('a member who is not an admin gets no door and no question',
        (tester) async {
      if (today.day == 1) return;
      final yesterday = today.day - 1;
      final ds = FakeCustodyDataSource(
          members: [bruno, anaAdmin], days: [row(7, dayOfMonth(yesterday), 2)])
        ..family = premium;
      await tester.pumpWidget(app(ds));
      await tester.pumpAndSettle();

      await openDay(tester, yesterday);
      expect(find.text(pt[K.editorPastReadonly]), findsOneWidget);
      expect(find.byKey(daySheetCorrectPlanKey), findsNothing);
      expect(offer, findsNothing);
    });

    testWidgets('free tier beyond seven days: the Premium gate, not the '
        'question', (tester) async {
      if (today.day <= 8) return; // needs a day 8+ back in this month
      final day = today.day - 8;
      final ds = FakeCustodyDataSource(
          members: [anaAdmin, bruno], days: [row(7, dayOfMonth(day), 1)])
        ..family = free;
      await tester.pumpWidget(app(ds));
      await tester.pumpAndSettle();

      await openDay(tester, day);
      expect(find.byKey(daySheetCorrectPlanKey), findsNothing);
      expect(
          find.text(pt.format(KApp.editorRetroBeyondFree, [7, 6])),
          findsOneWidget);
      // The calendar wired no `onOpenPlan` here, so the gate stays a
      // sentence rather than offering a CTA that goes nowhere.
      expect(find.text(pt[K.famSeePremium]), findsNothing);
    });

    testWidgets('free tier inside seven days is asked like Premium',
        (tester) async {
      if (today.day == 1) return;
      final yesterday = today.day - 1;
      final ds = FakeCustodyDataSource(
          members: [anaAdmin, bruno], days: [row(7, dayOfMonth(yesterday), 1)])
        ..family = free;
      await tester.pumpWidget(app(ds));
      await tester.pumpAndSettle();

      await openDay(tester, yesterday);
      expect(find.byKey(daySheetCorrectPlanKey), findsOneWidget);
    });
  });

  group('a day ahead', () {
    testWidgets('"Limpar dia" is offered to an admin and cleared after '
        '"Ativar"', (tester) async {
      final future = futureDay;
      if (future == null) return;
      final mode = AdminMode();
      final ds = FakeCustodyDataSource(
          members: [anaAdmin, bruno], days: [row(7, dayOfMonth(future), 1)]);
      await tester.pumpWidget(app(ds, adminMode: mode));
      await tester.pumpAndSettle();

      await openDayEditor(tester, future);
      await tapSheet(tester, find.text(pt[K.editorClearDay]));
      expect(offer, findsOneWidget);
      expect(find.text(pt[KApp.adminOfferClearDay]), findsOneWidget);
      expect(ds.deleted, isEmpty, reason: 'nothing is written before yes');

      await activate(tester);
      expect(mode.isActive, isTrue);
      expect(ds.deleted, [7]);
      await settleSnack(tester);
    });

    testWidgets('a non-admin editor has no "Limpar dia"', (tester) async {
      final future = futureDay;
      if (future == null) return;
      final ds = FakeCustodyDataSource(
          members: [bruno, anaAdmin], days: [row(7, dayOfMonth(future), 2)]);
      await tester.pumpWidget(app(ds));
      await tester.pumpAndSettle();

      await openDayEditor(tester, future);
      expect(find.text(pt[K.editorClearDay]), findsNothing);
    });

    testWidgets('the locked planned parent asks, and "Ativar" picks the '
        'chip that was tapped', (tester) async {
      final future = futureDay;
      if (future == null) return;
      final mode = AdminMode();
      final ds = FakeCustodyDataSource(
          members: [anaAdmin, bruno], days: [row(7, dayOfMonth(future), 1)]);
      await tester.pumpWidget(app(ds, adminMode: mode));
      await tester.pumpAndSettle();

      await openDayEditor(tester, future);
      final brunoChip = memberChip('Bruno').first;
      await tapSheet(tester, brunoChip);
      expect(find.text(pt[KApp.adminOfferChangePlanned]), findsOneWidget);

      await activate(tester);
      expect(mode.isActive, isTrue);
      expect(tester.widget<ChoiceChip>(brunoChip).selected, isTrue);
    });
  });

  testWidgets('bulk: the banner says what the edit leaves alone, and '
      '"Ativar" turns the mode on with the selection intact', (tester) async {
    final future = futureDay;
    if (future == null) return;
    final mode = AdminMode();
    final ds = FakeCustodyDataSource(
        members: [anaAdmin, bruno], days: [row(7, dayOfMonth(future), 1)]);
    await tester.pumpWidget(app(ds, adminMode: mode));
    await tester.pumpAndSettle();

    await longPressDay(tester, future);
    await tester.tap(find.text(pt.format(K.selectionEdit, [1])));
    await tester.pumpAndSettle();

    final banner = find.byKey(const Key('bulkAdminOffer'));
    expect(banner, findsOneWidget);
    await tapSheet(
        tester,
        find.descendant(
            of: banner, matching: find.text(pt[K.navAdminEnter])));
    expect(find.text(pt[KApp.adminOfferBulkOverwrite]), findsOneWidget);

    await activate(tester);
    expect(mode.isActive, isTrue);
    expect(banner, findsNothing);
    expect(find.text(pt.format(K.bulkTitleOne, [1])), findsOneWidget);
  });

  testWidgets('wizard: ticking "substituir" asks, and "Ativar" ticks it',
      (tester) async {
    final mode = AdminMode();
    final ds = FakeCustodyDataSource(members: [anaAdmin, bruno], days: []);
    await tester.pumpWidget(app(ds, adminMode: mode));
    await tester.pumpAndSettle();

    await openMenu(tester);
    await tester.tap(find.text(pt[K.calWizard]));
    await tester.pumpAndSettle();

    final box = find.byKey(const Key('wizReplaceExisting'));
    await tapSheet(tester, box);
    expect(find.text(pt[KApp.adminOfferWizardReplace]), findsOneWidget);
    expect(tester.widget<Checkbox>(box).value, isFalse);

    await activate(tester);
    expect(mode.isActive, isTrue);
    expect(tester.widget<Checkbox>(box).value, isTrue);
  });

  testWidgets('"Limpar mês": an admin with the mode off is asked first, then '
      'the month\'s own question', (tester) async {
    final future = futureDay;
    if (future == null) return;
    final mode = AdminMode();
    final ds = FakeCustodyDataSource(
        members: [anaAdmin, bruno], days: [row(7, dayOfMonth(future), 1)]);
    await tester.pumpWidget(app(ds, adminMode: mode));
    await tester.pumpAndSettle();

    await openMenu(tester);
    await tester.tap(find.text(pt[K.calClearMonth]));
    await tester.pumpAndSettle();
    expect(find.text(pt[KApp.adminOfferClearMonth]), findsOneWidget);
    expect(find.text(pt[K.calClearMonthTitle]), findsNothing);

    await tester.tap(find.text(pt[K.navAdminEnter]).last);
    await tester.pumpAndSettle();
    expect(mode.isActive, isTrue);
    expect(find.text(pt[K.calClearMonthTitle]), findsOneWidget);
    expect(ds.clearedRanges, isEmpty, reason: 'activating deletes nothing');
  });

  group('the menu names the mode', () {
    testWidgets('an admin toggles it from the ⋮ menu, in words',
        (tester) async {
      final mode = AdminMode();
      final ds = FakeCustodyDataSource(members: [anaAdmin, bruno], days: []);
      await tester.pumpWidget(app(ds, adminMode: mode));
      await tester.pumpAndSettle();

      await openMenu(tester);
      await tester.tap(find.text(pt[K.navAdminEnter]));
      await tester.pumpAndSettle();
      expect(mode.isActive, isTrue);

      await openMenu(tester);
      await tester.tap(find.text(pt[K.navAdminExit]));
      await tester.pumpAndSettle();
      expect(mode.isActive, isFalse);
    });

    testWidgets('a non-admin menu has no such item', (tester) async {
      final ds = FakeCustodyDataSource(members: [bruno, anaAdmin], days: []);
      await tester.pumpWidget(app(ds));
      await tester.pumpAndSettle();

      await openMenu(tester);
      expect(find.text(pt[K.navAdminEnter]), findsNothing);
    });
  });
}

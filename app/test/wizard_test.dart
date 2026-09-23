// Lote 2 PR 4 — the Rotation Wizard against the fake data source: the 7/7
// preset expansion, existing days preserved (insert-only write), the T-27
// transition-only handoff, the F-39 free-tier clamp and the block validation.
import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:entrelares_db_contracts/models/care_schedule.dart';
import 'package:entrelares_db_contracts/models/family.dart';

import 'package:entrelares_db_contracts/models/member.dart';
import 'package:entrelares_app/services/admin_mode.dart';
import 'package:entrelares_app/widgets/ui/ui.dart';

import 'calendar_slice_test.dart';

/// The admin of the fake roster — the shield only shows for a real admin.
const anaAdmin = Member(
    id: 1, fullName: 'Ana Souza', colorSlot: 1, userId: 'u1', isAdmin: true);

final pt = Localization(AppLanguage.ptBr);

/// U-36: the wizard is an item of the calendar's ⋮ menu — two taps, both by
/// the text a person reads, never by the icon.
Future<void> openWizard(WidgetTester tester) async {
  await tester.tap(find.byTooltip(pt[K.calActionsMenu]));
  await tester.pumpAndSettle();
  await tester.tap(find.text(pt[K.calWizard]));
  await tester.pumpAndSettle();
}

/// U-55: "Gerar" needs an answer about the handoff time. The flows that are
/// not about it answer "não temos horário fixo" — exactly the old null.
Future<void> answerNoFixedTime(WidgetTester tester) async {
  final chip = find.byKey(const Key('wizHandoffNone'));
  await tester.ensureVisible(chip);
  await tester.pumpAndSettle();
  await tester.tap(chip);
  await tester.pumpAndSettle();
}

Future<void> generate(WidgetTester tester, {bool answer = true}) async {
  // A picked time is left alone. (Not by the prompt text: InputDecorator
  // keeps its hint in the tree, faded out, even while a value shows.)
  final field = tester.widget<AppTimeField>(find.byType(AppTimeField));
  final chip = tester.widget<FilterChip>(find.byKey(const Key('wizHandoffNone')));
  if (answer && field.value == null && !chip.selected) {
    await answerNoFixedTime(tester);
  }
  await tapSheet(tester, find.text(pt[K.wizGenerate]));
}

int daysInThreeMonths() =>
    addMonthsClamped(dateOnly(today), 3).difference(dateOnly(today)).inDays;

void main() {
  testWidgets('the default 7/7 preset expands from today, alternating the '
      'first two members', (tester) async {
    final ds = FakeCustodyDataSource(members: [ana, bruno], days: []);
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();

    await openWizard(tester);
    await generate(tester);

    expect(ds.inserted, hasLength(daysInThreeMonths()));
    expect(ds.inserted.first.scheduleDate, dateOnly(today));
    expect(
        ds.inserted.take(7).every((r) => r.scheduledParentId == 1), isTrue);
    expect(ds.inserted.skip(7).take(7).every((r) => r.scheduledParentId == 2),
        isTrue);
    expect(find.textContaining('dias criados'), findsOneWidget);

    // Closing reloads the calendar behind the sheet.
    await tapSheet(tester, find.text(pt[K.wizClose]));
    expect(find.text(pt[K.wizTitle]), findsNothing);
  });

  testWidgets('already-assigned days are preserved and reported as kept',
      (tester) async {
    final future = futureDay;
    if (future == null) return;
    final ds = FakeCustodyDataSource(
        members: [ana, bruno], days: [row(7, dayOfMonth(future), 2)]);
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();

    await openWizard(tester);
    await generate(tester);

    expect(ds.inserted, hasLength(daysInThreeMonths() - 1));
    expect(
        ds.inserted
            .where((r) =>
                CareSchedule.isoDate(r.scheduleDate) ==
                CareSchedule.isoDate(dayOfMonth(future)))
            .isEmpty,
        isTrue);
    expect(find.textContaining('foram mantidos'), findsOneWidget);
  });

  testWidgets('T-27: the handoff time lands only on transition days — never '
      'the first', (tester) async {
    final ds = FakeCustodyDataSource(members: [ana, bruno], days: []);
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();

    await openWizard(tester);
    await pickTime(tester, find.byKey(const Key('wizHandoff')), hour: 1);
    await generate(tester);

    expect(ds.inserted.first.handoffTime, isNull);
    // Day 8 (index 7) is the first 7/7 transition.
    expect(ds.inserted[7].handoffTime, '01:00:00');
    expect(ds.inserted[8].handoffTime, isNull);
  });

  testWidgets('F-39: the free horizon clamps the plan with the upsell note',
      (tester) async {
    final ds = FakeCustodyDataSource(members: [ana, bruno], days: [])
      ..family = const Family(id: 1, plan: 'free')
      ..publicSettings = const {'calendar_months_free': '1'};
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();

    await openWizard(tester);
    await generate(tester); // duration stays at the default 3 months

    final horizonDays =
        addMonthsClamped(dateOnly(today), 1).difference(dateOnly(today)).inDays;
    expect(ds.inserted, hasLength(horizonDays));
    expect(find.textContaining('limitado ao horizonte'), findsOneWidget);
  });

  testWidgets('a block without a parent refuses to generate', (tester) async {
    // A single-member family: the 7/7 preset's second block has no parent.
    final ds = FakeCustodyDataSource(members: [ana], days: []);
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();

    await openWizard(tester);
    await generate(tester);

    expect(find.textContaining(pt[K.wizErrPickParentPerBlock]),
        findsOneWidget);
    expect(ds.inserted, isEmpty);
  });

  u55HandoffAnswerTests();
  f51ReplaceTests();
}

// ── U-55: the handoff time is asked, never skipped ──────────────────────────

void u55HandoffAnswerTests() {
  testWidgets('U-55: "Gerar" with no answer writes nothing and says why ON '
      'the field', (tester) async {
    final ds = FakeCustodyDataSource(members: [ana, bruno], days: []);
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();

    await openWizard(tester);
    // Nothing pre-selected: no default time, no default "none".
    expect(find.text(pt[K.wizHandoffPick]), findsOneWidget);
    expect(
        tester
            .widget<FilterChip>(find.byKey(const Key('wizHandoffNone')))
            .selected,
        isFalse);

    await generate(tester, answer: false);

    expect(ds.inserted, isEmpty);
    expect(find.text(pt[K.wizHandoffRequired]), findsOneWidget);
    // The field, not the sheet's banner, carries it.
    expect(
        find.descendant(
            of: find.byType(AppTimeField),
            matching: find.text(pt[K.wizHandoffRequired])),
        findsOneWidget);
  });

  testWidgets('U-55: "Não temos horário fixo" clears the message and '
      'generates with no time at all', (tester) async {
    final ds = FakeCustodyDataSource(members: [ana, bruno], days: []);
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();

    await openWizard(tester);
    await generate(tester, answer: false);
    await answerNoFixedTime(tester);
    expect(find.text(pt[K.wizHandoffRequired]), findsNothing);
    expect(find.text(pt[K.editorHandoffEmpty]), findsOneWidget);

    await generate(tester);
    expect(ds.inserted, hasLength(daysInThreeMonths()));
    expect(ds.inserted.every((r) => r.handoffTime == null), isTrue);
  });

  testWidgets('U-55: a time and "none" exclude each other', (tester) async {
    final ds = FakeCustodyDataSource(members: [ana, bruno], days: []);
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();

    await openWizard(tester);
    await answerNoFixedTime(tester);
    await pickTime(tester, find.byKey(const Key('wizHandoff')), hour: 18);
    expect(
        tester
            .widget<FilterChip>(find.byKey(const Key('wizHandoffNone')))
            .selected,
        isFalse);

    await answerNoFixedTime(tester);
    await generate(tester);
    expect(ds.inserted.every((r) => r.handoffTime == null), isTrue);
  });
}

// ── F-51: "substituir os dias já planejados" ────────────────────────────────

Future<void> tapReplaceCheckbox(WidgetTester tester) async {
  final box = find.byKey(const Key('wizReplaceExisting'));
  await tester.ensureVisible(box);
  await tester.pumpAndSettle();
  await tester.tap(box);
  await tester.pumpAndSettle();
}

void f51ReplaceTests() {
  // F-67 Part B: an ADMIN with the mode off now sees the box (ticking it
  // asks) — so the "no replace" reader is a member who is not an admin.
  testWidgets('F-51: a non-admin is offered no replace — the additive path '
      'is untouched', (tester) async {
    final ds = FakeCustodyDataSource(members: [bruno, anaAdmin], days: []);
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();

    await openWizard(tester);
    expect(find.byKey(const Key('wizReplaceExisting')), findsNothing);
    await generate(tester);
    expect(ds.replacedRanges, isEmpty);
    expect(ds.inserted, hasLength(daysInThreeMonths()));
  });

  testWidgets('F-51: admin mode + the box ticked asks the S-09 question with '
      'the planned count, then replaces the range in ONE call',
      (tester) async {
    final future = futureDay;
    if (future == null) return;
    final ds = FakeCustodyDataSource(
        members: [anaAdmin, bruno], days: [row(7, dayOfMonth(future), 2)]);
    await tester.pumpWidget(app(ds, adminMode: AdminMode()..toggle()));
    await tester.pumpAndSettle();

    await openWizard(tester);
    await tapReplaceCheckbox(tester);
    await generate(tester);

    // The bulk edit's own warning, with the count the range holds NOW —
    // and nothing written yet.
    expect(find.text(pt.format(K.bulkOverwriteWarningOne, [1])),
        findsOneWidget);
    expect(ds.replacedRanges, isEmpty);
    expect(ds.inserted, isEmpty);

    await tapSheet(tester, find.text(pt[K.editorYesChange]));

    final call = ds.replacedRanges.single;
    expect(call.from, dateOnly(today));
    // Exactly the generated span: [start, end) → the day before the end.
    final end = addMonthsClamped(dateOnly(today), 3);
    expect(call.to, DateTime(end.year, end.month, end.day - 1));
    expect(call.days, hasLength(daysInThreeMonths()));
    expect(call.days.first.scheduledParentId, 1);
    // The additive write never ran — one transaction, not clear-then-insert.
    expect(ds.inserted, isEmpty);
    expect(find.textContaining('do plano anterior'), findsOneWidget);
  });

  testWidgets('F-51: "não, voltar" on the S-09 question writes nothing and '
      'keeps the form', (tester) async {
    final future = futureDay;
    if (future == null) return;
    final ds = FakeCustodyDataSource(
        members: [anaAdmin, bruno], days: [row(7, dayOfMonth(future), 2)]);
    await tester.pumpWidget(app(ds, adminMode: AdminMode()..toggle()));
    await tester.pumpAndSettle();

    await openWizard(tester);
    await tapReplaceCheckbox(tester);
    await generate(tester);
    await tapSheet(tester, find.text(pt[K.editorNoGoBack]));

    expect(ds.replacedRanges, isEmpty);
    expect(ds.inserted, isEmpty);
    expect(find.text(pt[K.wizGenerate]), findsOneWidget);
  });

  testWidgets('F-51: an empty range asks nothing and still goes through the '
      'replace path', (tester) async {
    final ds = FakeCustodyDataSource(members: [anaAdmin, bruno], days: []);
    await tester.pumpWidget(app(ds, adminMode: AdminMode()..toggle()));
    await tester.pumpAndSettle();

    await openWizard(tester);
    await tapReplaceCheckbox(tester);
    await generate(tester);

    expect(find.text(pt[K.editorYesChange]), findsNothing);
    expect(ds.replacedRanges, hasLength(1));
    expect(find.textContaining('dias criados'), findsOneWidget);
    expect(find.textContaining('do plano anterior'), findsNothing);
  });
}

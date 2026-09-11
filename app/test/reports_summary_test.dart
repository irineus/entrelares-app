// "Resumo do Período" — the screen half of the reports mirror. The counting
// itself is proven in `report_rules_test.dart` (core); what this suite proves
// is that the screen shows THOSE numbers: the right period reaches the query,
// the U-20 toggle changes the reading without a new fetch, and the reader's
// language reaches every label — including the emphasized total, which must
// never render its markup.
import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:entrelares_db_contracts/models/care_schedule.dart';
import 'package:entrelares_db_contracts/models/member.dart';
import 'package:entrelares_db_contracts/models/role.dart';
import 'package:entrelares_app/screens/reports_screen.dart';
import 'package:entrelares_app/screens/reports_summary_tab.dart';
import 'package:entrelares_app/widgets/app_l10n.dart';

import 'calendar_slice_test.dart' show FakeCustodyDataSource;

const roleMother = Role(id: 1, roleName: 'mother');
const roleFather = Role(id: 2, roleName: 'father');

const ana = Member(id: 1, fullName: 'Ana Souza', colorSlot: 1, userId: 'u1', roleId: 1);
const bruno =
    Member(id: 2, fullName: 'Bruno Lima', colorSlot: 2, userId: 'u2', roleId: 2);

final today = DateTime(2026, 8, 19);

CareSchedule day(int d, int scheduled, {int? actual}) => CareSchedule(
      id: 100 + d,
      scheduleDate: DateTime(2026, 8, d),
      scheduledParentId: scheduled,
      actualParentId: actual,
    );

/// Past: 15,16 Ana · 17 Ana→Bruno (a realized swap) · 18 Bruno.
/// Future: 20 Ana · 21 Bruno→Ana (accepted, still ahead).
List<CareSchedule> period() => [
      day(15, 1),
      day(16, 1),
      day(17, 1, actual: 2),
      day(18, 2),
      day(20, 1),
      day(21, 2, actual: 1),
    ];

FakeCustodyDataSource source({List<CareSchedule>? days}) =>
    FakeCustodyDataSource(members: const [ana, bruno], days: days ?? period())
      ..roles = const [roleMother, roleFather];

Future<void> pumpSummary(
  WidgetTester tester,
  FakeCustodyDataSource ds, {
  AppLanguage language = AppLanguage.ptBr,
}) async {
  await tester.binding.setSurfaceSize(const Size(800, 2000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(AppL10n(
    l: Localization(language),
    setLanguage: (_) async {},
    child: MaterialApp(
      home: Scaffold(
        body: ReportsSummaryTab(dataSource: ds, now: () => today),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  final l = Localization(AppLanguage.ptBr);

  group('the cards', () {
    testWidgets('one card per member, named with the role', (tester) async {
      await pumpSummary(tester, source());

      // First name plus role qualifier, as the web card reads.
      expect(find.text('Ana (Mãe)'), findsOne);
      expect(find.text('Bruno (Pai)'), findsOne);
    });

    testWidgets('planned and actual are the realized-day reading',
        (tester) async {
      await pumpSummary(tester, source());

      expect(find.text(l[K.sumPlanned]), findsNWidgets(2));
      // Ana: planned 15,16,17,20 = 4 · actual 15,16 = 2 (the 17th went away).
      expect(find.text(l.format(K.sumDaysMany, [4])), findsOne);
      // "2 dias" three times: Ana's actual, and Bruno's planned (18,21) and
      // actual (the 17th he received, plus the 18th).
      expect(find.text(l.format(K.sumDaysMany, [2])), findsNWidgets(3));
      // U-07 split — given and received are their own paired stats now
      // (U-29 F29). Ana gave the 17th; Bruno received it.
      expect(find.text(l[K.sumGiven]), findsNWidgets(2));
      expect(find.text(l[K.sumReceived]), findsNWidgets(2));
      expect(find.text(l.format(K.sumDaysOne, [1])), findsNWidgets(2));
      expect(find.text(l.format(K.sumDaysMany, [0])), findsNWidgets(2));
    });

    testWidgets('the projected row appears only with the U-20 toggle on',
        (tester) async {
      final ds = source();
      await pumpSummary(tester, ds);

      expect(find.text(l[K.sumProjected]), findsNothing);
      final fetchesBefore = ds.activityOffsets.length;

      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();

      expect(find.text(l[K.sumProjected]), findsNWidgets(2));
      // The toggle is a READING of rows already loaded — no new query.
      expect(ds.activityOffsets.length, fetchesBefore);
    });

    testWidgets('the projection brings the accepted future swap into the count',
        (tester) async {
      await pumpSummary(tester, source());

      // Default: one realized swap.
      expect(find.textContaining('1'), findsWidgets);
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();

      // Bruno gave the 21st away, Ana received it — on top of the 17th:
      // all four give/receive stats now read one day each.
      expect(find.text(l.format(K.sumDaysOne, [1])), findsNWidgets(4));
    });
  });

  group('the total', () {
    testWidgets('renders the emphasis as text, never as markup',
        (tester) async {
      await pumpSummary(tester, source());

      expect(find.textContaining('<strong>'), findsNothing);
      expect(
        find.textContaining(stripRichText(l.format(K.sumTotalSwaps, [1]))),
        findsOne,
      );
    });

    testWidgets('the projected total is its own sentence', (tester) async {
      await pumpSummary(tester, source());
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();

      expect(
        find.textContaining(
            stripRichText(l.format(K.sumTotalSwapsProjected, [2]))),
        findsOne,
      );
    });
  });

  group('the period', () {
    testWidgets('opens on the whole year and reloads when the filter changes',
        (tester) async {
      final ds = source();
      await pumpSummary(tester, ds);

      expect(ds.periodReads.first, (DateTime(2026, 1, 1), DateTime(2026, 12, 31)));

      await tester.tap(find.text(l[K.repByMonth]));
      await tester.pumpAndSettle();

      // August 2026, ending on the 31st — no "Filtrar" tap needed.
      expect(ds.periodReads.last, (DateTime(2026, 8, 1), DateTime(2026, 8, 31)));
    });

    testWidgets('an empty period shows the empty state, not a wall of zeros',
        (tester) async {
      await pumpSummary(tester, source(days: const []));

      expect(find.text(l[K.sumEmptyTitle]), findsOne);
      expect(find.text('Ana (Mãe)'), findsNothing);
    });
  });

  group('failures and language', () {
    testWidgets('a dead session says so instead of leaking the error',
        (tester) async {
      final ds = source()..throwOnMembers = 'permission denied for function x';
      await pumpSummary(tester, ds);

      expect(find.text(l[KApp.sessionExpired]), findsOne);
      expect(find.text(l[K.repErrorTitle]), findsNothing);
      expect(find.textContaining(l[K.repErrorTitle], skipOffstage: false),
          findsOne);
    });

    testWidgets('any other failure propagates the server text', (tester) async {
      final ds = source()..throwOnMembers = 'boom';
      await pumpSummary(tester, ds);

      expect(find.textContaining('boom'), findsOne);
    });

    testWidgets('an English session reads the whole screen in English',
        (tester) async {
      final en = Localization(AppLanguage.en);
      await pumpSummary(tester, source(), language: AppLanguage.en);

      expect(find.text(en[K.sumSubtitle]), findsOne);
      expect(find.text('Ana (Mother)'), findsOne);
      expect(find.text(en.format(K.sumDaysMany, [4])), findsOne);
    });
  });

  group('the hub', () {
    testWidgets('three tabs, each with its own report', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 2000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(AppL10n(
        l: Localization(AppLanguage.ptBr),
        setLanguage: (_) async {},
        child: MaterialApp(home: ReportsScreen(dataSource: source())),
      ));
      await tester.pumpAndSettle();

      // U-28: the tab labels dropped their emoji for the app's own icons.
      expect(find.text(l[K.repTabSummary]), findsOne);
      expect(find.text(l[K.repTabHistory]), findsOne);
      expect(find.text(l[K.repTabPdf]), findsOne);
      expect(find.byIcon(Icons.picture_as_pdf_outlined), findsOne);
      // The Resumo is the landing tab, as `/reports` redirects in the web.
      expect(find.text(l[K.sumSubtitle]), findsOne);

      await tester.tap(find.text(l[K.repTabHistory]));
      await tester.pumpAndSettle();
      expect(find.text(l[K.auditSubtitle]), findsOne);

      await tester.tap(find.text(l[K.repTabPdf]));
      await tester.pumpAndSettle();
      expect(find.text(l[K.pdfHeading]), findsOne);
    });
  });
}

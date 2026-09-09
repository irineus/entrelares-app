// F-33 — the batch's redesign: a real PDF composed on the device instead of
// the browser's print(). Two things this suite has to prove, because they are
// what a redesign can quietly get wrong: the GATE still fails closed (the
// server's is_premium is the word, the mirror only decides what the UI
// offers), and the document carries the same numbers as the Resumo screen plus
// the F-45 motivation — as REAL text inside the PDF, not just in the model.
import 'dart:typed_data';

import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:entrelares_db_contracts/models/activity_log.dart';
import 'package:entrelares_db_contracts/models/care_schedule.dart';
import 'package:entrelares_db_contracts/models/family.dart';
import 'package:entrelares_db_contracts/models/member.dart';
import 'package:entrelares_db_contracts/models/role.dart';
import 'package:entrelares_app/screens/reports_pdf_tab.dart';
import 'package:entrelares_app/services/report_pdf.dart';
import 'package:entrelares_app/widgets/app_l10n.dart';

import 'calendar_slice_test.dart' show FakeCustodyDataSource;

const roleMother = Role(id: 1, roleName: 'mother');
const roleFather = Role(id: 2, roleName: 'father');

const ana =
    Member(id: 1, fullName: 'Ana Souza', colorSlot: 1, userId: 'u1', roleId: 1);
const bruno =
    Member(id: 2, fullName: 'Bruno Lima', colorSlot: 2, userId: 'u2', roleId: 2);

final today = DateTime(2026, 8, 19, 21, 5);

CareSchedule day(int d, int scheduled, {int? actual}) => CareSchedule(
      id: 100 + d,
      scheduleDate: DateTime(2026, 8, d),
      scheduledParentId: scheduled,
      actualParentId: actual,
    );

FakeCustodyDataSource source({
  String plan = 'premium',
  DateTime? trialEndsAt,
  List<ActivityLog> logs = const [],
  Map<int, SwapOrigin> origins = const {},
}) =>
    FakeCustodyDataSource(
      members: const [ana, bruno],
      days: [day(15, 1), day(16, 1), day(17, 1, actual: 2), day(18, 2)],
    )
      ..roles = const [roleMother, roleFather]
      ..family =
          Family(id: 7, name: 'Souza', plan: plan, trialEndsAt: trialEndsAt)
      ..activityLogs = logs
      ..resolutionOrigins = origins;

Future<void> pumpPdf(
  WidgetTester tester,
  FakeCustodyDataSource ds, {
  AppLanguage language = AppLanguage.ptBr,
  void Function(Uint8List bytes, String fileName)? onShare,
  void Function(Uint8List bytes, String fileName)? onPrint,
}) async {
  await tester.binding.setSurfaceSize(const Size(800, 2000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(AppL10n(
    l: Localization(language),
    setLanguage: (_) async {},
    child: MaterialApp(
      home: Scaffold(
        body: ReportsPdfTab(
          dataSource: ds,
          now: () => today,
          onShare: onShare == null
              ? null
              : (b, f) async => onShare(b, f),
          onPrint: onPrint == null
              ? null
              : (b, f) async => onPrint(b, f),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  final l = Localization(AppLanguage.ptBr);

  group('the F-32 gate', () {
    testWidgets('a free family sees the neutral upsell and no generator',
        (tester) async {
      await pumpPdf(tester, source(plan: 'free'));

      expect(find.text(l[K.pdfUpsellTitle]), findsOne);
      expect(find.text(l[K.pdfGenerate]), findsNothing);
      // T-38: the neutral paywall carries NO checkout affordance.
      expect(find.text(l[K.pdfUpsellButton]), findsNothing);
    });

    testWidgets('a family inside its trial is premium', (tester) async {
      await pumpPdf(
        tester,
        source(plan: 'free', trialEndsAt: DateTime.utc(2026, 9, 1)),
      );

      expect(find.text(l[K.pdfGenerate]), findsOne);
      expect(find.text(l[K.pdfUpsellTitle]), findsNothing);
    });

    testWidgets('an RLS-blocked family row fails CLOSED', (tester) async {
      final ds = source()..family = null;
      await pumpPdf(tester, ds);

      expect(find.text(l[K.pdfUpsellTitle]), findsOne);
    });
  });

  group('generating', () {
    testWidgets('produces a document and offers share and print',
        (tester) async {
      Uint8List? shared;
      String? sharedName;
      await pumpPdf(tester, source(), onShare: (b, f) {
        shared = b;
        sharedName = f;
      });

      await tester.tap(find.text(l[K.pdfGenerate]));
      await tester.pumpAndSettle();

      expect(find.text(l[K.pdfDocTitle]), findsOne);
      await tester.tap(find.text(l[KApp.commonShare]));
      await tester.pumpAndSettle();

      expect(shared, isNotNull);
      // A real PDF, not an empty buffer.
      expect(String.fromCharCodes(shared!.take(5)), '%PDF-');
      expect(sharedName, 'entrelares-relatorio-2026-08-01_2026-08-31.pdf');
    });

    testWidgets('printing hands over the same bytes', (tester) async {
      Uint8List? printed;
      await pumpPdf(tester, source(), onPrint: (b, _) => printed = b);

      await tester.tap(find.text(l[K.pdfGenerate]));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l[K.pdfPrintButton]));
      await tester.pumpAndSettle();

      expect(printed, isNotNull);
      expect(String.fromCharCodes(printed!.take(5)), '%PDF-');
    });

    testWidgets('a custom period ending before it starts is refused',
        (tester) async {
      final ds = source();
      await pumpPdf(tester, ds);

      await tester.tap(find.text(l[K.pdfCustom]));
      await tester.pumpAndSettle();
      // "De" opens on the 1st and "Até" on today (the 19th) — move the START
      // past the end so the pair is impossible.
      await tester.tap(find.textContaining(l[K.pdfFrom]));
      await tester.pumpAndSettle();
      await tester.tap(find.text('25'));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      final readsBefore = ds.periodReads.length;
      await tester.tap(find.text(l[K.pdfGenerate]));
      await tester.pumpAndSettle();

      expect(find.textContaining(l[K.pdfErrEndBeforeStart]), findsOne);
      expect(ds.periodReads.length, readsBefore);
    });

    testWidgets('a failure propagates the server text', (tester) async {
      final ds = source()..throwOnMembers = 'boom';
      await pumpPdf(tester, ds);

      await tester.tap(find.text(l[K.pdfGenerate]));
      await tester.pumpAndSettle();

      expect(find.textContaining('boom'), findsOne);
    });
  });

  group('the document itself', () {
    /// The page text, readable. Two deliberate deviations from production, and
    /// only for the sake of reading the bytes: no compression, and the built-in
    /// WinAnsi faces instead of the embedded Roboto (an embedded TrueType font
    /// writes GLYPH INDICES, so no assertion could see a word). Production
    /// embeds Roboto precisely because Helvetica drops accents — which is why
    /// every fixture below is spelled without them.
    Future<String> render(
        CustodyReport report, Localization localization) async {
      final bytes = await buildReportPdf(
        report,
        localization,
        compress: false,
        fonts: ReportFonts(pw.Font.helvetica(), pw.Font.helveticaBold()),
      );
      return String.fromCharCodes(bytes.where((b) => b < 128));
    }

    CustodyReport report({
      bool future = false,
      String? childName,
      Map<int, SwapOrigin> origins = const {},
      List<AuditLogView> logs = const [],
      Localization? localization,
    }) {
      final loc = localization ?? l;
      return buildCustodyReport(
        familyName: 'Souza',
        childName: childName,
        start: DateTime(2026, 8, 1),
        end: DateTime(2026, 8, 31),
        today: today,
        days: [
          ReportDay(scheduleDate: DateTime(2026, 8, 15), scheduledParentId: 1),
          ReportDay(
              scheduleDate: DateTime(2026, 8, 17),
              scheduledParentId: 1,
              actualParentId: 2),
        ],
        members: const [
          MemberView(id: 1, fullName: 'Ana Souza'),
          MemberView(id: 2, fullName: 'Bruno Lima'),
        ],
        auditLogs: logs,
        roleLabelOf: (id) => id == 1 ? 'Mae' : 'Pai',
        diffFor: (log) => computeAuditDiff(
          log: log,
          profiles: const [
            MemberView(id: 1, fullName: 'Ana Souza'),
            MemberView(id: 2, fullName: 'Bruno Lima'),
          ],
          l: loc,
        ),
        generatedBy: 'Ana Souza',
        generatedAtLocal: today,
        appVersion: '0.2.23+25',
        l: loc,
        resolutionOrigins: origins,
        includeAcceptedFutureSwaps: future,
      );
    }

    test('carries the caregiver table and the honest copy', () async {
      final text = await render(report(), l);

      expect(text, contains('Ana Souza'));
      expect(text, contains('Souza'));
      // The immutability paragraph and the footer ship verbatim — with the
      // markup stripped, never printed.
      expect(text, contains('append-only'));
      expect(text, contains('0.2.23+25'));
      expect(text, isNot(contains('<strong>')));
    });

    test('the child name appears only when it was typed', () async {
      expect(await render(report(childName: 'Lia'), l), contains('Lia'));
      expect(await render(report(childName: '  '), l),
          isNot(contains('Lia')));
    });

    test('F-45: the origin sentence and the F-44 texts reach the page',
        () async {
      final text = await render(
        report(
          logs: [
            AuditLogView(
              id: 5,
              affectedDate: DateTime(2026, 8, 17),
              createdAtLocal: DateTime(2026, 8, 16, 9),
              action: 'UPDATE',
              performedById: 1,
              newData: const {'actual_parent_id': 2},
            )
          ],
          origins: {
            5: const SwapOrigin(
              requestingProfileId: 1,
              targetProfileId: 2,
              status: 'approved',
              resolvedBy: 'user',
              requestMessage: 'consulta medica',
              approvalNote: 'sem problema',
            ),
          },
        ),
        l,
      );

      // Single tokens only: the layout places words one by one, so a phrase
      // does not survive as one string in the page operators.
      expect(text, contains('consulta'));
      expect(text, contains('medica'));
      expect(text, contains('problema'));
      expect(text, contains('originada'));
    });

    test('F-61: the authorship facts reach the page as real text', () async {
      final text = await render(
        report(
          logs: [
            AuditLogView(
              id: 6,
              affectedDate: DateTime(2026, 8, 15),
              createdAtLocal: DateTime(2026, 8, 10, 9),
              action: 'UPDATE',
              performedById: 1,
              oldData: const {'scheduled_parent_id': 1},
              newData: const {'scheduled_parent_id': 2},
              context: const AuditContext(
                  scheduledParentHasAccount: false, adminOverride: true),
            ),
          ],
        ),
        l,
      );

      // Single ASCII tokens, as everywhere in this group: "ainda" belongs to
      // the no-account sentence and "administradora" to the override one.
      expect(text, contains('ainda'));
      expect(text, contains('administradora'));
    });

    test('F-61: a row without context prints no authorship line', () async {
      final text = await render(
        report(
          logs: [
            AuditLogView(
              id: 6,
              affectedDate: DateTime(2026, 8, 15),
              createdAtLocal: DateTime(2026, 8, 10, 9),
              action: 'INSERT',
              performedById: 1,
              newData: const {'scheduled_parent_id': 2},
            ),
          ],
        ),
        l,
      );

      expect(text, isNot(contains('ainda')));
      expect(text, isNot(contains('administradora')));
    });

    test('the U-20 criterion line is printed only with the projection on',
        () async {
      // Only whole ASCII tokens are safe to assert: the page text is WinAnsi
      // and the layout breaks lines at spaces.
      expect(await render(report(future: true), l), contains('Inclui'));
      expect(await render(report(), l), isNot(contains('Inclui')));
    });

    test('the document follows the READER language (U-13)', () async {
      final en = Localization(AppLanguage.en);
      final text = await render(report(localization: en), en);

      expect(text, contains('Summary'));
      expect(text, isNot(contains('Resumo')));
    });

    test('the file name is dated so a folder of them sorts', () {
      expect(reportFileName(report()),
          'entrelares-relatorio-2026-08-01_2026-08-31.pdf');
    });
  });
}

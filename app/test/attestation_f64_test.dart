// F-64 (PR 2) — the verifiable report on screen.
//
// The server attests and answers; these pin what the client adds: the PDF
// asks for the attestation BEFORE it is built (the QR is inside the bytes it
// fingerprints), the fingerprint it sends is the one of the bytes it hands
// over, a refusal leaves a PDF without QR, and the public page says each
// state — and never shows a blank.
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;
import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:entrelares_db_contracts/models/care_schedule.dart';
import 'package:entrelares_db_contracts/models/family.dart';
import 'package:entrelares_db_contracts/models/member.dart';
import 'package:entrelares_db_contracts/models/report_attestation.dart';
import 'package:entrelares_db_contracts/models/role.dart';
import 'package:entrelares_app/screens/reports_pdf_tab.dart';
import 'package:entrelares_app/screens/verify_report_screen.dart';
import 'package:entrelares_app/widgets/app_l10n.dart';

import 'calendar_slice_test.dart' show FakeCustodyDataSource;

const ana = Member(
    id: 1,
    fullName: 'Ana Souza',
    colorSlot: 1,
    userId: 'u1',
    roleId: 1,
    isAdmin: true);
const bruno =
    Member(id: 2, fullName: 'Bruno Lima', colorSlot: 2, userId: 'u2', roleId: 1);
const id = '3f2c9a1e-7b4d-4c2a-9e8f-0a1b2c3d4e5f';
final today = DateTime(2026, 8, 19, 21, 5);

FakeCustodyDataSource source({Map<String, String> settings = const {
  'feature.report_attestation': 'true'
}}) =>
    FakeCustodyDataSource(members: const [ana, bruno], days: [
      CareSchedule(
          id: 1, scheduleDate: DateTime(2026, 8, 15), scheduledParentId: 1),
    ])
      ..roles = const [Role(id: 1, roleName: 'mother')]
      ..family = const Family(id: 7, name: 'Souza', plan: 'premium')
      ..publicSettings = settings;

Future<void> pumpPdf(WidgetTester tester, FakeCustodyDataSource ds,
    {void Function(Uint8List bytes)? onShare}) async {
  await tester.binding.setSurfaceSize(const Size(800, 2000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(AppL10n(
    l: Localization(AppLanguage.ptBr),
    setLanguage: (_) async {},
    child: MaterialApp(
      home: Scaffold(
        body: ReportsPdfTab(
          dataSource: ds,
          now: () => today,
          onShare: onShare == null ? null : (b, f) async => onShare(b),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

Future<void> pumpVerify(
    WidgetTester tester, FakeCustodyDataSource ds, String theId) async {
  await tester.binding.setSurfaceSize(const Size(420, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(AppL10n(
    l: Localization(AppLanguage.ptBr),
    setLanguage: (_) async {},
    child: MaterialApp(home: VerifyReportScreen(id: theId, dataSource: ds)),
  ));
  await tester.pumpAndSettle();
}

void main() {
  final l = Localization(AppLanguage.ptBr);

  group('the PDF', () {
    testWidgets('asks for the attestation, then sends the fingerprint of the '
        'bytes it hands over', (tester) async {
      final ds = source();
      Uint8List? shared;
      await pumpPdf(tester, ds, onShare: (b) => shared = b);
      await tester.tap(find.text(l[K.pdfGenerate]));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l[KApp.commonShare]));
      await tester.pumpAndSettle();

      expect(shared, isNotNull);
      expect(ds.attestWrites,
          ['issue', 'hash:${sha256.convert(shared!).toString()}']);
    });

    testWidgets('flag OFF: no attestation is asked for', (tester) async {
      final ds = source(settings: const {});
      await pumpPdf(tester, ds);
      await tester.tap(find.text(l[K.pdfGenerate]));
      await tester.pumpAndSettle();
      expect(ds.attestWrites, isEmpty);
      expect(find.text(l[K.pdfDocTitle]), findsOne);
    });

    testWidgets('a refused attestation still produces the PDF, without QR',
        (tester) async {
      final ds = source()..throwOnIssue = Exception('recurso Premium');
      await pumpPdf(tester, ds);
      await tester.tap(find.text(l[K.pdfGenerate]));
      await tester.pumpAndSettle();
      expect(ds.attestWrites, isEmpty);
      expect(find.text(l[K.pdfDocTitle]), findsOne);
    });

    testWidgets('the admin sees the issued reports and may revoke one',
        (tester) async {
      final ds = source()
        ..attestations = [
          ReportAttestation(
            id: id,
            periodFrom: DateTime(2026, 8, 1),
            periodTo: DateTime(2026, 8, 31),
            issuedAt: DateTime.utc(2026, 8, 19),
            expiresAt: DateTime.utc(2027, 8, 19),
            sha256: 'ab' * 32,
          ),
        ];
      await pumpPdf(tester, ds);
      expect(find.byKey(const ValueKey('attestations-card')), findsOne);
      await tester.tap(find.byKey(const ValueKey('attestation-revoke-$id')));
      await tester.pumpAndSettle();
      expect(ds.attestWrites, isEmpty);
      await tester.tap(find.text(l[KApp.attestRevoke]).last);
      await tester.pumpAndSettle();
      expect(ds.attestWrites, ['revoke:$id']);
    });
  });

  group('the public page', () {
    testWidgets('valid: the summary by initials and the fingerprint',
        (tester) async {
      final ds = source()
        ..verifyAnswer = {
          'state': 'valid',
          'issued_at': '2026-08-19T12:00:00Z',
          'expires_at': '2027-08-19T12:00:00Z',
          'period_from': '2026-08-01',
          'period_to': '2026-08-31',
          'summary': {
            'days_planned': 31,
            'days_by_caregiver': [
              {'initials': 'AS', 'days': 16},
              {'initials': 'BL', 'days': 15},
            ],
            'days_changed_by_swap': 2,
            'swaps': {'approved': 2, 'rejected': 1},
            'day_accounts': 3,
          },
          'sha256': 'ab' * 32,
        };
      await pumpVerify(tester, ds, id);
      expect(find.byKey(const ValueKey('verify-state-valid')), findsOne);
      expect(find.text(l.format(KApp.attestDaysBy, ['AS', '16'])), findsOne);
      expect(find.text(l.format(KApp.attestSwaps, ['3'])), findsOne);
      expect(find.byKey(const ValueKey('verify-fingerprint')), findsOne);
      // Off the web there is no picker: the page says how to compare instead.
      expect(find.text(l[KApp.attestNoPicker]), findsOne);
    });

    testWidgets('revoked and expired say so; a malformed id is "unknown"',
        (tester) async {
      final ds = source()
        ..verifyAnswer = {
          'state': 'revoked',
          'issued_at': '2026-08-19T12:00:00Z',
          'revoked_at': '2026-08-25T12:00:00Z',
        };
      await pumpVerify(tester, ds, id);
      expect(find.byKey(const ValueKey('verify-state-revoked')), findsOne);
      expect(find.byKey(const ValueKey('verify-fingerprint')), findsNothing);

      await pumpVerify(tester, ds, 'not-an-id');
      expect(find.byKey(const ValueKey('verify-state-unknown')), findsOne);
    });
  });
}

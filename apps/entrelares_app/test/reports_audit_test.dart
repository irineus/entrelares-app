// "Histórico de Ajustes" — the two trails the screen reads (the calendar's
// activity_logs and the S-10 account_logs), the F-45 origin enrichment that
// lote 3 deferred to here, and the incremental "Carregar mais".
//
// The rules themselves are proven in `audit_rules_test.dart` (core). What this
// suite proves is what only a screen can get wrong: paging keeps what it
// already had, a failed origin lookup costs the origin line and NOT the
// timeline, and the synthetic trial-end entry lands in chronological order.
import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:entrelares_db_contracts/models/account_log.dart';
import 'package:entrelares_db_contracts/models/activity_log.dart';
import 'package:entrelares_db_contracts/models/family.dart';
import 'package:entrelares_db_contracts/models/member.dart';
import 'package:entrelares_db_contracts/models/role.dart';
import 'package:entrelares_app/screens/reports_audit_tab.dart';
import 'package:entrelares_app/widgets/app_l10n.dart';

import 'calendar_slice_test.dart' show FakeCustodyDataSource;

const roleMother = Role(id: 1, roleName: 'mother');
const roleFather = Role(id: 2, roleName: 'father');

const ana =
    Member(id: 1, fullName: 'Ana Souza', colorSlot: 1, userId: 'u1', roleId: 1);
const bruno =
    Member(id: 2, fullName: 'Bruno Lima', colorSlot: 2, userId: 'u2', roleId: 2);

final today = DateTime(2026, 8, 19, 12);

ActivityLog activity({
  required int id,
  int day = 20,
  String action = 'UPDATE',
  int? performedById = 1,
  Map<String, dynamic>? oldData,
  Map<String, dynamic>? newData,
  int hour = 10,
}) =>
    ActivityLog(
      id: id,
      affectedDate: DateTime(2026, 8, day),
      createdAt: DateTime.utc(2026, 8, 18, hour),
      action: action,
      performedById: performedById,
      oldData: oldData,
      newData: newData,
    );

AccountLog account({
  required int id,
  String action = 'role_changed',
  int? actor = 1,
  int? target = 2,
  String? oldValue,
  String? newValue,
  DateTime? at,
}) =>
    AccountLog(
      id: id,
      familyId: 7,
      action: action,
      actorProfileId: actor,
      targetProfileId: target,
      oldValue: oldValue,
      newValue: newValue,
      createdAt: at ?? DateTime.utc(2026, 8, 18, 9),
    );

FakeCustodyDataSource source({
  List<ActivityLog> logs = const [],
  List<AccountLog> accountLogs = const [],
  Map<int, SwapOrigin> origins = const {},
  Family? family,
}) =>
    FakeCustodyDataSource(members: const [ana, bruno], days: const [])
      ..roles = const [roleMother, roleFather]
      ..activityLogs = logs
      ..accountLogs = accountLogs
      ..resolutionOrigins = origins
      ..family = family;

Future<void> pumpAudit(
  WidgetTester tester,
  FakeCustodyDataSource ds, {
  AppLanguage language = AppLanguage.ptBr,
}) async {
  await tester.binding.setSurfaceSize(const Size(800, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(AppL10n(
    l: Localization(language),
    setLanguage: (_) async {},
    child: MaterialApp(
      home: Scaffold(
        body: ReportsAuditTab(dataSource: ds, now: () => today),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  final l = Localization(AppLanguage.ptBr);

  group('the calendar trail', () {
    testWidgets('an entry names the day, the actor and the field diff',
        (tester) async {
      await pumpAudit(
        tester,
        source(logs: [
          activity(
            id: 1,
            oldData: const {'actual_parent_id': null},
            newData: const {'actual_parent_id': 2},
          )
        ]),
      );

      expect(
          find.text(l.format(K.auditDayLabel, [l.formatDate(DateTime(2026, 8, 20))])),
          findsOne);
      expect(
        find.textContaining(stripRichText(
            l.format(K.auditScheduleChange, ['Ana Souza', l[K.auditUpdatedSchedule]]))),
        findsOne,
      );
      expect(find.textContaining(l[K.auditFieldActualParent]), findsOne);
      expect(find.textContaining('Bruno Lima'), findsWidgets);
    });

    testWidgets('a trigger-written row falls back to the system actor',
        (tester) async {
      await pumpAudit(tester,
          source(logs: [activity(id: 1, performedById: null)]));

      expect(find.textContaining(l[K.auditSystemTrigger]), findsOne);
    });

    testWidgets('an empty period shows the empty state', (tester) async {
      await pumpAudit(tester, source());

      expect(find.text(l[K.auditEmptyTitle]), findsOne);
    });
  });

  group('F-45 — the origin of a change', () {
    testWidgets('names the origin and carries both F-44 texts',
        (tester) async {
      await pumpAudit(
        tester,
        source(
          logs: [activity(id: 1, newData: const {'actual_parent_id': 2})],
          origins: {
            1: const SwapOrigin(
              requestingProfileId: 1,
              targetProfileId: 2,
              status: 'approved',
              resolvedBy: 'user',
              requestMessage: 'Tenho consulta médica',
              approvalNote: 'Sem problema',
            ),
          },
        ),
      );

      expect(
        find.textContaining(l.format(
            K.auditOriginSwapManual, ['Ana Souza', 'Bruno Lima'])),
        findsOne,
      );
      expect(find.textContaining('Tenho consulta médica'), findsOne);
      expect(find.textContaining('Sem problema'), findsOne);
    });

    testWidgets('a manual edit carries no origin line at all', (tester) async {
      await pumpAudit(tester,
          source(logs: [activity(id: 1, newData: const {'notes': 'x'})]));

      expect(find.textContaining('Alteração originada'), findsNothing);
    });

    testWidgets('a failed lookup costs the origin, never the timeline',
        (tester) async {
      final ds = source(logs: [activity(id: 1, newData: const {'notes': 'x'})])
        ..throwOnOrigins = 'network down';
      await pumpAudit(tester, ds);

      expect(find.textContaining('Alteração originada'), findsNothing);
      expect(find.textContaining(l[K.auditUpdatedSchedule]), findsOne);
      expect(find.text(l[K.repErrorTitle]), findsNothing);
    });
  });

  group('F-61 — authorship on the line', () {
    testWidgets('a stamped row says who had no account and the admin change',
        (tester) async {
      await pumpAudit(
        tester,
        source(logs: [
          ActivityLog(
            id: 1,
            affectedDate: DateTime(2026, 9, 12),
            createdAt: DateTime.utc(2026, 9, 9, 13),
            action: 'UPDATE',
            performedById: 1,
            oldData: const {'scheduled_parent_id': 1},
            newData: const {'scheduled_parent_id': 2},
            context: const AuditContext(
                scheduledParentHasAccount: false,
                actorIsAdmin: true,
                adminOverride: true),
          ),
        ]),
      );

      expect(
        find.textContaining(
            l.format(K.auditAuthorshipNoAccount, ['Bruno Lima'])),
        findsOne,
      );
      expect(
        find.textContaining(
            l.format(K.auditAuthorshipAdminOverride, ['Ana Souza'])),
        findsOne,
      );
    });

    testWidgets('a row without context (older than F-61) says nothing',
        (tester) async {
      await pumpAudit(
        tester,
        source(logs: [activity(id: 1, newData: const {'scheduled_parent_id': 2})]),
      );

      expect(find.textContaining('ainda não tinha conta'), findsNothing);
      expect(find.textContaining('Alteração direta'), findsNothing);
    });
  });

  group('Carregar mais', () {
    List<ActivityLog> fullPage() => [
          for (var i = 0; i < auditPageSize; i++)
            activity(id: i + 1, day: 1 + i, newData: {'notes': 'nota $i'})
        ];

    testWidgets('a full page offers more; the next page is appended',
        (tester) async {
      final ds = source(logs: [...fullPage(), activity(id: 99, day: 28)]);
      await pumpAudit(tester, ds);

      expect(find.text(l[K.auditLoadMore]), findsOne);
      expect(ds.activityOffsets, [0]);

      await tester.tap(find.text(l[K.auditLoadMore]));
      await tester.pumpAndSettle();

      // Asked for the next page, and a SHORT page ends the paging.
      expect(ds.activityOffsets, [0, auditPageSize]);
      expect(find.text(l[K.auditLoadMore]), findsNothing);
      // The first page is still there — appended, not replaced.
      expect(find.textContaining('nota 0'), findsOne);
    });

    testWidgets('a short first page never offers to load more',
        (tester) async {
      await pumpAudit(tester, source(logs: [activity(id: 1)]));

      expect(find.text(l[K.auditLoadMore]), findsNothing);
    });
  });

  group('the period tabs', () {
    testWidgets('Por Mês reads the month, Por Ano the year', (tester) async {
      final ds = source(logs: [activity(id: 1)]);
      await pumpAudit(tester, ds);

      await tester.tap(find.text(l[K.repByMonth]));
      await tester.pumpAndSettle();
      expect(ds.periodLogReads.last,
          (DateTime(2026, 8, 1), DateTime(2026, 8, 31)));

      await tester.tap(find.text(l[K.repByYear]));
      await tester.pumpAndSettle();
      expect(ds.periodLogReads.last,
          (DateTime(2026, 1, 1), DateTime(2026, 12, 31)));
    });
  });

  group('the S-10 account trail', () {
    testWidgets('an entry names actor, action and target, translating roles',
        (tester) async {
      await pumpAudit(
        tester,
        source(accountLogs: [
          account(id: 1, oldValue: 'mother', newValue: 'father')
        ]),
      );

      await tester.tap(find.text(l[K.auditTabAccount]));
      await tester.pumpAndSettle();

      expect(find.textContaining(l[K.auditActionRoleChanged]), findsOne);
      expect(find.textContaining('Bruno Lima'), findsOne);
      // role_changed is the ONLY action whose stored value translates.
      expect(find.textContaining('Mãe'), findsOne);
      expect(find.textContaining('Pai'), findsOne);
    });

    testWidgets('a value that is not a role passes through as stored',
        (tester) async {
      await pumpAudit(
        tester,
        source(accountLogs: [
          account(
              id: 1,
              action: 'name_changed',
              oldValue: 'mother',
              newValue: 'Ana S.')
        ]),
      );

      await tester.tap(find.text(l[K.auditTabAccount]));
      await tester.pumpAndSettle();

      expect(find.textContaining('mother'), findsOne);
      expect(find.textContaining('Mãe'), findsNothing);
    });

    testWidgets('an unknown action shows its raw key — the record, not an '
        'invention', (tester) async {
      await pumpAudit(tester,
          source(accountLogs: [account(id: 1, action: 'something_new')]));

      await tester.tap(find.text(l[K.auditTabAccount]));
      await tester.pumpAndSettle();

      expect(find.textContaining('something_new'), findsOne);
    });

    testWidgets('an empty trail has its own empty state', (tester) async {
      await pumpAudit(tester, source());

      await tester.tap(find.text(l[K.auditTabAccount]));
      await tester.pumpAndSettle();

      expect(find.text(l[K.auditEmptyAccountTitle]), findsOne);
    });
  });

  group('F-58 QA 2 — the trial that simply ran out', () {
    testWidgets('lands in chronological order among the real rows',
        (tester) async {
      final ds = source(
        accountLogs: [
          account(id: 2, at: DateTime.utc(2026, 8, 10)),
          account(id: 1, at: DateTime.utc(2026, 7, 1)),
        ],
        family: Family(
          id: 7,
          name: 'Souza',
          plan: 'free',
          trialEndsAt: DateTime.utc(2026, 8, 1),
        ),
      );
      await pumpAudit(tester, ds);
      await tester.tap(find.text(l[K.auditTabAccount]));
      await tester.pumpAndSettle();

      expect(find.textContaining(l[K.auditTrialEnded]), findsOne);

      // Between the 10/08 row and the 01/07 one.
      final entryY = tester
          .getTopLeft(find.textContaining(l[K.auditTrialEnded]))
          .dy;
      final newest = tester
          .getTopLeft(find.textContaining(l.formatDateTime(
              DateTime.utc(2026, 8, 10).toLocal())))
          .dy;
      final oldest = tester
          .getTopLeft(find.textContaining(l.formatDateTime(
              DateTime.utc(2026, 7, 1).toLocal())))
          .dy;
      expect(entryY, greaterThan(newest));
      expect(entryY, lessThan(oldest));
    });

    testWidgets('a premium family never sees the loss narrated',
        (tester) async {
      final ds = source(
        accountLogs: [account(id: 1)],
        family: Family(
          id: 7,
          name: 'Souza',
          plan: 'premium',
          trialEndsAt: DateTime.utc(2026, 8, 1),
        ),
      );
      await pumpAudit(tester, ds);
      await tester.tap(find.text(l[K.auditTabAccount]));
      await tester.pumpAndSettle();

      expect(find.textContaining(l[K.auditTrialEnded]), findsNothing);
    });
  });

  group('failures and language', () {
    testWidgets('a dead session says so instead of leaking the error',
        (tester) async {
      final ds = source()..throwOnMembers = 'permission denied for function x';
      await pumpAudit(tester, ds);

      expect(find.text(l[KApp.sessionExpired]), findsOne);
    });

    testWidgets('an English session reads the timeline in English',
        (tester) async {
      final en = Localization(AppLanguage.en);
      await pumpAudit(
        tester,
        source(logs: [
          activity(id: 1, action: 'INSERT', newData: const {'notes': 'x'})
        ]),
        language: AppLanguage.en,
      );

      expect(find.text(en[K.auditSubtitle]), findsOne);
      expect(find.textContaining(en[K.auditCreatedSchedule]), findsOne);
      expect(find.textContaining(l[K.auditCreatedSchedule]), findsNothing);
    });
  });
}

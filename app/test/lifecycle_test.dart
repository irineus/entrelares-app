// S-11 and S-15 — leaving the family, deleting one, and the re-consent gate.
//
// The property that carries the file: **silence never deletes a family**. A
// missing answer reads "aguardando", one refusal ends the request, and only an
// explicit unanimity unlocks "delete it now" — which is still sudo-gated and
// still recounted by the database.
import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:entrelares_db_contracts/models/family.dart';
import 'package:entrelares_db_contracts/models/family_deletion.dart';
import 'package:entrelares_db_contracts/models/member.dart';
import 'package:entrelares_db_contracts/models/role.dart';
import 'package:entrelares_app/screens/family_screen.dart';
import 'package:entrelares_app/screens/leaving_screen.dart';
import 'package:entrelares_app/screens/policy_update_screen.dart';
import 'package:entrelares_app/screens/profile_screen.dart';
import 'package:entrelares_app/services/admin_mode.dart';
import 'package:entrelares_app/services/custody_data_source.dart';
import 'package:entrelares_app/services/sudo_service.dart';
import 'package:entrelares_app/widgets/app_l10n.dart';

import 'calendar_slice_test.dart' show FakeCustodyDataSource;

const roleMother = Role(id: 1, roleName: 'mother');

const ana = Member(
    id: 1,
    fullName: 'Ana Souza',
    userId: 'u1',
    isAdmin: true,
    roleId: 1,
    email: 'ana@example.com');
const bruno = Member(
    id: 2,
    fullName: 'Bruno Lima',
    userId: 'u2',
    roleId: 1,
    email: 'bruno@example.com');
const carla = Member(
    id: 3,
    fullName: 'Carla Dias',
    userId: 'u3',
    roleId: 1,
    email: 'carla@example.com');

PendingFamilyDeletion deletion({
  int requestedBy = 1,
  List<FamilyDeletionResponse> responses = const [],
}) =>
    PendingFamilyDeletion(
      FamilyDeletionRequest(
        id: 1,
        requestedBy: requestedBy,
        scheduledFor: DateTime.utc(2026, 9, 18),
        requestedAt: DateTime.utc(2026, 8, 19),
        status: 'pending',
      ),
      responses,
    );

FakeCustodyDataSource source({
  List<Member> members = const [ana, bruno],
  PendingFamilyDeletion? pending,
  String plan = 'premium',
}) =>
    FakeCustodyDataSource(members: members, days: [])
      ..family = Family(id: 7, name: 'Souza', plan: plan)
      ..roles = const [roleMother]
      ..sudoPassword = 'segredo123'
      ..pendingDeletion = pending;

Future<void> pumpFamily(WidgetTester tester, FakeCustodyDataSource ds,
    {Future<void> Function()? onFamilyDeleted}) async {
  await tester.binding.setSurfaceSize(const Size(800, 3000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(AppL10n(
    l: Localization(AppLanguage.ptBr),
    setLanguage: (_) async {},
    child: MaterialApp(
      home: FamilyScreen(
        dataSource: ds,
        adminMode: AdminMode(),
        sudo: SudoService(ds),
        onFamilyDeleted: onFamilyDeleted,
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

Future<void> confirmSudo(WidgetTester tester) async {
  final l = Localization(AppLanguage.ptBr);
  expect(find.text(l[K.sudoTitle]), findsOne,
      reason: 'the destructive act must ask for the password');
  await tester.enterText(find.byType(TextField).last, 'segredo123');
  await tester.pump();
  await tester.tap(find.text(l[K.sudoConfirm]));
  await tester.pumpAndSettle();
}

void main() {
  final l = Localization(AppLanguage.ptBr);

  group('requesting the family deletion', () {
    testWidgets('an admin with company may open it, behind two steps',
        (tester) async {
      final ds = source();
      await pumpFamily(tester, ds);

      expect(find.text(l[K.famDelReqTitle]), findsOne);
      await tester.tap(find.text(l[K.famDelReqOpen]));
      await tester.pumpAndSettle();
      expect(find.text(l[K.famDelReqConfirmText]), findsOne);
      expect(ds.deletionRequests, 0);

      await tester.tap(find.text(l[K.famDelReqConfirm]));
      await tester.pumpAndSettle();
      await confirmSudo(tester);

      expect(ds.deletionRequests, 1);
      expect(ds.accountEmails, contains('family_deletion_requested'));
    });

    testWidgets('a LONE member gets no request panel — they delete the family '
        'by leaving instead', (tester) async {
      await pumpFamily(tester, source(members: const [ana]));

      expect(find.text(l[K.famDelReqTitle]), findsNothing);
    });

    testWidgets('a non-admin gets none either', (tester) async {
      await pumpFamily(tester, source(members: const [bruno, ana]));

      expect(find.text(l[K.famDelReqTitle]), findsNothing);
    });
  });

  group('the pending panel', () {
    testWidgets('shows waiting for an answer that was never given',
        (tester) async {
      await pumpFamily(
          tester, source(members: const [ana, bruno, carla], pending: deletion()));

      expect(find.text(l[K.famDelTitle]), findsOne);
      expect(find.textContaining(l[K.famDelVoteWaiting]), findsNWidgets(2));
    });

    testWidgets('the requester withdraws, under sudo', (tester) async {
      final ds = source(pending: deletion());
      await pumpFamily(tester, ds);

      await tester.tap(find.text(l[K.famDelWithdraw]));
      await tester.pumpAndSettle();
      await confirmSudo(tester);

      expect(ds.withdrawals, 1);
      expect(ds.accountEmails, contains('family_deletion_withdrawn'));
    });

    testWidgets('anyone else may agree — WITHOUT a password, because agreeing '
        'is not the destructive act', (tester) async {
      final ds = source(members: const [bruno, ana], pending: deletion());
      await pumpFamily(tester, ds);

      await tester.tap(find.text(l[K.famDelAgree]));
      await tester.pumpAndSettle();

      expect(find.text(l[K.sudoTitle]), findsNothing);
      expect(ds.deletionResponses, [true]);
    });

    testWidgets('refusing ends it, also without a password', (tester) async {
      final ds = source(members: const [bruno, ana], pending: deletion());
      await pumpFamily(tester, ds);

      await tester.tap(find.text(l[K.famDelRefuseKeep]));
      await tester.pumpAndSettle();

      expect(ds.deletionResponses, [false]);
      expect(ds.accountEmails, contains('family_deletion_refused'));
    });

    testWidgets('undoing an agreement sends NULL — back to waiting, which is '
        'not the same as refusing', (tester) async {
      final ds = source(
        members: const [bruno, ana],
        pending: deletion(
            responses: const [FamilyDeletionResponse(profileId: 2, agreed: true)]),
      );
      await pumpFamily(tester, ds);

      await tester.tap(find.text(l[K.famDelUndoAgreement]));
      await tester.pumpAndSettle();

      expect(ds.deletionResponses, [null]);
    });
  });

  group('execute now', () {
    testWidgets('is offered only once every voter agreed explicitly',
        (tester) async {
      // Two voters, one answer — no unanimity, no button.
      await pumpFamily(
        tester,
        source(
          members: const [ana, bruno, carla],
          pending: deletion(
              responses: const [
                FamilyDeletionResponse(profileId: 2, agreed: true)
              ]),
        ),
      );

      expect(find.text(l[K.famDelExecuteNowOpen]), findsNothing);
    });

    testWidgets('appears with full unanimity, and runs behind two steps plus '
        'the password', (tester) async {
      final ds = source(
        members: const [ana, bruno],
        pending: deletion(
            responses: const [
              FamilyDeletionResponse(profileId: 2, agreed: true)
            ]),
      );
      var ended = false;
      await pumpFamily(tester, ds, onFamilyDeleted: () async => ended = true);

      expect(find.textContaining('Todos os responsáveis concordaram'), findsOne);
      await tester.tap(find.text(l[K.famDelExecuteNowOpen]));
      await tester.pumpAndSettle();
      expect(ds.executions, 0);

      await tester.tap(find.text(l[K.famDelExecuteNow]));
      await tester.pumpAndSettle();
      await confirmSudo(tester);

      expect(ds.executions, 1);
      expect(ds.purges, 1);
      expect(ended, isTrue, reason: 'every session ends with the family');
    });

    testWidgets('a refusal in the set keeps it hidden', (tester) async {
      await pumpFamily(
        tester,
        source(
          members: const [ana, bruno],
          pending: deletion(
              responses: const [
                FamilyDeletionResponse(profileId: 2, agreed: false)
              ]),
        ),
      );

      expect(find.text(l[K.famDelExecuteNowOpen]), findsNothing);
    });
  });

  group('leaving the family', () {
    Future<void> pumpProfile(WidgetTester tester, FakeCustodyDataSource ds,
        {VoidCallback? onLeaving}) async {
      await tester.binding.setSurfaceSize(const Size(800, 3000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(AppL10n(
        l: Localization(AppLanguage.ptBr),
        setLanguage: (_) async {},
        child: MaterialApp(
          home: ProfileScreen(
            dataSource: ds,
            sudo: SudoService(ds),
            onLeaving: onLeaving,
            deliverExport: (_, _) async {},
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('the only admin must name a successor before the button works',
        (tester) async {
      final ds = source();
      await pumpProfile(tester, ds);

      expect(find.text(l[K.profLeaveTitle]), findsOne);
      await tester.tap(find.text(l[K.profLeaveOpen]));
      await tester.pumpAndSettle();

      final button = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, l[K.profLeaveConfirm]));
      expect(button.onPressed, isNull,
          reason: 'a family with no admin could never invite or rename again');

      await tester.tap(find.byType(DropdownButtonFormField<int>).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bruno Lima').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text(l[K.profLeaveConfirm]));
      await tester.pumpAndSettle();
      await confirmSudo(tester);

      expect(ds.accountDeletions, [2]);
      expect(ds.accountEmails, contains('member_left'));
    });

    testWidgets('the LAST member is told they are deleting the family',
        (tester) async {
      await pumpProfile(tester, source(members: const [ana]));

      expect(find.text(l[K.profLeaveTitleLast]), findsOne);
      expect(find.text(l[K.profLeaveOpenLast]), findsOne);
    });

    testWidgets('a non-admin needs no successor', (tester) async {
      final ds = source(members: const [bruno, ana]);
      await pumpProfile(tester, ds);

      await tester.tap(find.text(l[K.profLeaveOpen]));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l[K.profLeaveConfirm]));
      await tester.pumpAndSettle();
      await confirmSudo(tester);

      expect(ds.accountDeletions, [null]);
    });

    testWidgets('leaving is BLOCKED while the family itself is on the way out',
        (tester) async {
      await pumpProfile(tester, source(pending: deletion()));

      expect(find.text(l[K.profLeaveBlocked]), findsOne);
      expect(find.text(l[K.profLeaveOpen]), findsNothing);
    });
  });

  group('/leaving', () {
    const leaving = Member(
      id: 1,
      fullName: 'Ana Souza',
      userId: 'u1',
      roleId: 1,
      email: 'ana@example.com',
      leftAt: '2026-08-19T10:00:00Z',
    );

    Future<void> pumpLeaving(WidgetTester tester, FakeCustodyDataSource ds,
        {VoidCallback? onReturned}) async {
      await tester.pumpWidget(AppL10n(
        l: Localization(AppLanguage.ptBr),
        setLanguage: (_) async {},
        child: MaterialApp(
          home: LeavingScreen(
            dataSource: ds,
            sudo: SudoService(ds),
            onSignOut: () async {},
            onReturned: onReturned ?? () {},
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('the account variant names the deadline', (tester) async {
      const withDeadline = Member(
        id: 1,
        fullName: 'Ana Souza',
        userId: 'u1',
        roleId: 1,
        leftAt: '2026-08-19T10:00:00Z',
      );
      await pumpLeaving(
          tester, source(members: const [withDeadline, bruno]));

      expect(find.text(l[K.leaveTitle]), findsOne);
      // No stamped date yet — the generic window stands in for it.
      expect(find.textContaining(l[K.leaveIn30Days]), findsOne);
    });

    testWidgets('the LAST member reads the family-removal copy instead',
        (tester) async {
      await pumpLeaving(tester, source(members: const [leaving]));

      expect(find.text(l[K.leaveFamilyRemovalTitle]), findsOne);
    });

    testWidgets('cancelling is sudo-gated and brings the member back',
        (tester) async {
      final ds = source(members: const [leaving, bruno]);
      var returned = false;
      await pumpLeaving(tester, ds, onReturned: () => returned = true);

      await tester.tap(find.text(l[K.leaveCancelAndReturn]));
      await tester.pumpAndSettle();
      expect(ds.cancelledExits, 0);

      await confirmSudo(tester);

      expect(ds.cancelledExits, 1);
      expect(ds.accountEmails, contains('member_returned'));
      expect(returned, isTrue);
    });

    testWidgets('nothing pending is a dead end, not an error', (tester) async {
      await pumpLeaving(tester, source());

      expect(find.text(l[K.leaveNonePending]), findsOne);
      expect(find.text(l[K.leaveCancelAndReturn]), findsNothing);
    });

    testWidgets('the server\'s "seat already filled" refusal is shown verbatim',
        (tester) async {
      final ds = source(members: const [leaving, bruno])
        ..throwOnLifecycle = Exception(
            '{"code":"23514","message":"A família já preencheu a vaga; não é '
            'possível cancelar a saída."}');
      await pumpLeaving(tester, ds);

      await tester.tap(find.text(l[K.leaveCancelAndReturn]));
      await tester.pumpAndSettle();
      await confirmSudo(tester);

      expect(find.textContaining('já preencheu a vaga'), findsOne);
    });
  });

  group('/policy-update (S-15)', () {
    Future<void> pumpPolicy(WidgetTester tester, FakeCustodyDataSource ds,
        {VoidCallback? onAccepted,
        AppLanguage language = AppLanguage.ptBr}) async {
      await tester.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(AppL10n(
        l: Localization(language),
        setLanguage: (_) async {},
        child: MaterialApp(
          home: PolicyUpdateScreen(
            dataSource: ds,
            onSignOut: () async {},
            onAccepted: onAccepted ?? () {},
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('renders the change summary — nobody accepts a diff they '
        'cannot see', (tester) async {
      await pumpPolicy(tester, source());

      expect(find.text(l[K.policyWhatChanged]), findsOne);
      // U-29: the summary renders through AppBulletList — the glyph is its
      // own widget, so the assertion is on the change text itself.
      for (final change in PolicyVersions.changeSummary) {
        expect(find.text(change), findsOne);
      }
    });

    testWidgets('a FOUNDER sees the A-1.1 declaration', (tester) async {
      await pumpPolicy(tester, source());

      expect(find.text(ConsentDeclarations.creator), findsOne);
    });

    testWidgets('an INVITEE sees the A-1.2 one — the persisted marker is what '
        'the gate has left to go on', (tester) async {
      const invited = Member(
          id: 1,
          fullName: 'Bruno Lima',
          userId: 'u1',
          roleId: 1,
          joinedViaInvite: true);
      await pumpPolicy(tester, source(members: const [invited]));

      expect(find.text(ConsentDeclarations.invitee), findsOne);
    });

    testWidgets('the accept button is dead until the box is ticked',
        (tester) async {
      final ds = source();
      await pumpPolicy(tester, ds);

      final before = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, l[K.policyAcceptAndContinue]));
      expect(before.onPressed, isNull);

      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tester.tap(find.text(l[K.policyAcceptAndContinue]));
      await tester.pumpAndSettle();

      expect(ds.policyAccepts, 1);
    });

    testWidgets('an outdated client fails LOUDLY instead of stamping an '
        'unconsented version', (tester) async {
      final ds = source()
        ..throwOnLifecycle = Exception(
            '{"code":"22023","message":"Seu aplicativo está desatualizado e '
            'não pode registrar o aceite."}');
      await pumpPolicy(tester, ds);

      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tester.tap(find.text(l[K.policyAcceptAndContinue]));
      await tester.pumpAndSettle();

      expect(find.textContaining('desatualizado'), findsOne);
    });

    testWidgets('an English reader gets the courtesy summary', (tester) async {
      await pumpPolicy(tester, source(), language: AppLanguage.en);

      expect(find.text(PolicyVersions.changeSummaryEn.first), findsOne);
    });
  });
}

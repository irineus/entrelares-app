// F-50 (PR 2) — the Visualizador on screen.
//
// The server is the rule (the viewer guard on every table, the caps, the
// notification filter); these pin what the client OFFERS: the badge and the
// admin's two moves, the viewers' own section with its caps, and — for the
// viewer — no write door where the server would refuse.
import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:entrelares_db_contracts/models/family.dart';
import 'package:entrelares_db_contracts/models/member.dart';
import 'package:entrelares_db_contracts/models/role.dart';
import 'package:entrelares_app/screens/family_screen.dart';
import 'package:entrelares_app/services/admin_mode.dart';
import 'package:entrelares_app/services/sudo_service.dart';
import 'package:entrelares_app/widgets/app_l10n.dart';
import 'package:entrelares_app/widgets/day_agenda.dart';

import 'calendar_slice_test.dart' show FakeCustodyDataSource;

const admin = Member(
    id: 1, fullName: 'Ana Souza', userId: 'u1', isAdmin: true, roleId: 1);
const plain = Member(id: 2, fullName: 'Bruno Lima', userId: 'u2', roleId: 2);
const vo = Member(
    id: 3,
    fullName: 'Vó Cida',
    userId: 'u3',
    roleId: 3,
    membershipType: 'viewer');

const on = {'feature.viewers': 'true'};

FakeCustodyDataSource source({
  List<Member> members = const [admin, plain],
  Map<String, String> settings = on,
  String plan = 'free',
}) =>
    FakeCustodyDataSource(members: members, days: [])
      ..family = Family(id: 7, name: 'Souza', plan: plan)
      ..publicSettings = settings
      ..roles = const [
        Role(id: 1, roleName: 'mother'),
        Role(id: 3, roleName: 'grandmother'),
      ];

Future<void> pumpFamily(WidgetTester tester, FakeCustodyDataSource ds) async {
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
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  final l = Localization(AppLanguage.ptBr);

  group('the family page, as the admin', () {
    testWidgets('a viewer wears its badge; flag OFF hides the viewers section',
        (tester) async {
      await pumpFamily(
          tester, source(members: const [admin, plain, vo], settings: const {}));
      expect(find.byKey(const ValueKey('viewer-badge-3')), findsOne);
      expect(find.byKey(const ValueKey('viewer-section')), findsNothing);
    });

    testWidgets('free family with its viewer: the cap says the key, no form',
        (tester) async {
      await pumpFamily(tester, source(members: const [admin, plain, vo]));
      expect(find.byKey(const ValueKey('viewer-section')), findsOne);
      expect(find.byKey(const ValueKey('viewer-free-cap')), findsOne);
      expect(find.text(l.format(KApp.viewerFreeCapOne, [1])), findsOne);
      expect(find.byKey(const ValueKey('viewer-invite')), findsNothing);
    });

    testWidgets('inviting a viewer needs the e-mail, then sends it',
        (tester) async {
      final ds = source();
      await pumpFamily(tester, ds);
      await tester.tap(find.byKey(const ValueKey('viewer-invite')));
      await tester.pumpAndSettle();
      expect(find.text(l[KApp.viewerInviteNeedsEmail]), findsOne);
      expect(ds.viewerWrites, isEmpty);

      await tester.enterText(
          find.byKey(const ValueKey('viewer-email')), 'cida@example.com');
      await tester.tap(find.byKey(const ValueKey('viewer-role')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Avó').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('viewer-invite')));
      await tester.pumpAndSettle();
      expect(ds.viewerWrites, ['invite:cida@example.com:3']);
      expect(ds.mailedInvitations, [901]);
    });

    testWidgets('promoting asks first, then promotes', (tester) async {
      final ds = source(members: const [admin, plain, vo], plan: 'premium');
      await pumpFamily(tester, ds);
      await tester.tap(find.byKey(FamilyScreen.memberMenuKey(3)));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l[KApp.viewerPromote]));
      await tester.pumpAndSettle();
      expect(ds.viewerWrites, isEmpty);
      await tester.tap(find.text(l[KApp.viewerPromote]).last);
      await tester.pumpAndSettle();
      expect(ds.viewerWrites, ['promote:3']);
    });
  });

  testWidgets('a viewer is offered no agenda door', (tester) async {
    final ds = source(members: const [admin, vo])
      ..publicSettings = const {'feature.child_agenda': 'true'};
    await tester.binding.setSurfaceSize(const Size(420, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(AppL10n(
      l: Localization(AppLanguage.ptBr),
      setLanguage: (_) async {},
      child: MaterialApp(
        home: Scaffold(
          body: DayAgendaSection(
            date: DateTime(2026, 9, 25),
            today: DateTime(2026, 9, 24),
            dataSource: ds,
            settings: const PublicSettings({'feature.child_agenda': 'true'}),
            isPremium: true,
            me: vo,
            allProfiles: const [admin, vo],
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('day-agenda')), findsOne);
    expect(find.byKey(const ValueKey('day-agenda-add')), findsNothing);
  });

  test('a viewer is never assignable, and holds no caregiver seat', () {
    expect(vo.isViewer, isTrue);
    expect(vo.toView().isAssignable, isFalse);
    expect(admin.toView().isAssignable, isTrue);
  });
}

// The admin-mode page (`/family/admin-mode`, U-35 — a section of Família
// until then). The card is F-14's: the tier-aware F-40 copy, the amber toggle
// and the Premium gate CTA, which now NAVIGATES to the plan page.
import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:entrelares_db_contracts/models/family.dart';
import 'package:entrelares_db_contracts/models/member.dart';
import 'package:entrelares_db_contracts/models/role.dart';
import 'package:entrelares_app/screens/family_admin_mode_screen.dart';
import 'package:entrelares_app/services/admin_mode.dart';
import 'package:entrelares_app/widgets/app_l10n.dart';

import 'calendar_slice_test.dart' show FakeCustodyDataSource;
import 'family_page_test.dart' show FakeFunnel;

const _admin = Member(
  id: 1,
  fullName: 'Ana Souza',
  colorSlot: 1,
  userId: 'u1',
  isAdmin: true,
  roleId: 1,
  email: 'ana@example.com',
);
const _plain = Member(
  id: 2,
  fullName: 'Bruno Lima',
  colorSlot: 2,
  userId: 'u2',
  roleId: 1,
  email: 'bruno@example.com',
);

FakeCustodyDataSource _source({
  String plan = 'free',
  List<Member> members = const [_admin, _plain],
}) =>
    FakeCustodyDataSource(members: members, days: [])
      ..family = Family(id: 7, name: 'Souza', plan: plan)
      ..roles = const [Role(id: 1, roleName: 'mother')];

Future<void> _pump(
  WidgetTester tester,
  FakeCustodyDataSource ds, {
  AdminMode? adminMode,
  VoidCallback? onOpenPlan,
  FakeFunnel? funnel,
}) async {
  await tester.pumpWidget(AppL10n(
    l: Localization(AppLanguage.ptBr),
    setLanguage: (_) async {},
    child: MaterialApp(
      home: FamilyAdminModeScreen(
        dataSource: ds,
        adminMode: adminMode ?? AdminMode(),
        analytics: funnel?.service,
        onOpenPlan: onOpenPlan,
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  final l = Localization(AppLanguage.ptBr);

  testWidgets('an admin can turn it on, and the tier copy explains F-40',
      (tester) async {
    final mode = AdminMode();
    await _pump(tester, _source(), adminMode: mode);

    expect(find.text(l[K.famAdminSection]), findsOne);
    expect(find.textContaining('plano gratuito'), findsWidgets);

    await tester.tap(find.text(l[K.famAdminActivate]));
    await tester.pumpAndSettle();

    expect(mode.isActive, isTrue);
    expect(find.text(l[K.famAdminActiveNote]), findsOne);
  });

  testWidgets('a premium family reads the months, not the days',
      (tester) async {
    await _pump(tester, _source(plan: 'premium'));

    expect(find.textContaining('Administrador (Premium)'), findsOne);
    expect(find.text(l[K.famActivatePremiumLink]), findsNothing);
  });

  testWidgets('the free-tier gate records the intent and opens the plan page',
      (tester) async {
    final funnel = FakeFunnel();
    var opened = false;
    await _pump(tester, _source(),
        funnel: funnel, onOpenPlan: () => opened = true);

    await tester.tap(find.text(l[K.famActivatePremiumLink]));
    await tester.pumpAndSettle();

    expect(funnel.dataOf('premium-gate-click'), {'gate': 'admin-mode'});
    expect(opened, isTrue);
  });

  testWidgets('a non-admin reaching the page by URL gets no toggle',
      (tester) async {
    await _pump(tester, _source(members: const [_plain, _admin]));

    expect(find.text(l[K.famAdminActivate]), findsNothing);
    expect(find.text(l[K.famOnlyAdminsInvite]), findsOne);
  });
}

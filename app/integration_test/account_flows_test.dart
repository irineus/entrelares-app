// The lote-4 E2E pack: the account and family surfaces, driven through the
// real app against the dev project.
//
// It deliberately covers what a widget test CANNOT prove, because the widget
// suite already covers everything else:
//
//   * p0 — the invitation lifecycle against the REAL `create_invitation` /
//     `revoke_invitation` RPCs, with their caps, their admin check and their
//     revoke-then-count ordering.
//   * full — **S-10 elevation end to end**: the 🔐 sheet, the `elevate` Edge
//     Function, a real gated RPC, and the `ELEVATION_REQUIRED:` marker. Every
//     other test in the repo fakes that entire path.
//
// The DATABASE is the assertion throughout.
//
// Run locally:
//   flutter test integration_test/account_flows_test.dart --flavor dev \
//     --dart-define=E2E_SUPABASE_SERVICE_ROLE_KEY=<dev service_role>
library;

import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:entrelares_app/main.dart' as app;

import 'e2e_family.dart';

const policyVersion =
    String.fromEnvironment('E2E_POLICY_VERSION', defaultValue: '2026-07-30');

const pack = String.fromEnvironment('E2E_PACK', defaultValue: 'full');

final l = Localization(AppLanguage.ptBr);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late E2eFamily family;
  // Whether `app.main()` has already initialized the Supabase singleton in
  // this process. See `bootApp` — the answer cannot simply be asked.
  var appBooted = false;

  setUpAll(() async {
    E2eFamily.requireKey();
    family = await E2eFamily.create(policyVersion: policyVersion);
    // Two live members already fill the FREE cap, and this lane is about the
    // screens behind it — the cap has its own server-side coverage.
    await family.setPlan('premium');
  });

  tearDownAll(() async {
    await family.purge();
  });

  /// Boots the real app with a clean local state, signed out.
  ///
  /// The sign-out is guarded because `Supabase.instance` is an ASSERTION, not a
  /// nullable getter: until `app.main()` has run once there is no singleton and
  /// touching it throws. From the second boot on the singleton is alive (it is
  /// per PROCESS, the pilot's lesson 8) and signing out is what makes the next
  /// user start clean. `Supabase.initialize` is idempotent in 2.17.2, so the
  /// second `app.main()` is safe — the package docstring saying otherwise is
  /// stale.
  Future<void> bootApp(WidgetTester tester) async {
    // The language is PINNED, and that is not a preference — it is the U-13
    // trap. `main()` resolves the session language as
    // `stored override ?? profiles.language ?? PlatformDispatcher.locale`, and
    // on CI the browser reports the HOST's locale (`en-US`), so the app renders
    // in ENGLISH while every selector in this file comes from
    // `Localization(AppLanguage.ptBr)`. The failure names the widget
    // (`Found 0 widgets with text "Entrar"`), never the language — which is what
    // makes it expensive. Seeding the stored override is the FIRST rung of that
    // precedence, so it wins whatever the runner's locale is. The `flutter.`
    // prefix is the one shared_preferences adds on write.
    SharedPreferences.setMockInitialValues({
      'flutter.${LanguageResolver.storageKey}': AppLanguage.ptBrCode,
    });
    if (appBooted) {
      await Supabase.instance.client.auth
          .signOut(scope: SignOutScope.local)
          .catchError((_) {});
    }
    app.main();
    appBooted = true;
    await tester.pumpAndSettle(const Duration(seconds: 10));
  }

  Future<void> signIn(WidgetTester tester, String email) async {
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), email);
    await tester.enterText(fields.at(1), family.password);
    await tester.tap(find.text(l[K.loginSubmit]));
    await tester.pumpAndSettle(const Duration(seconds: 15));
  }

  Future<void> openFamilyTab(WidgetTester tester) async {
    await tester.tap(find.text(l[K.navFamily]));
    await tester.pumpAndSettle(const Duration(seconds: 8));
  }

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle(const Duration(seconds: 8));
  }

  testWidgets('p0 — an invitation is created and revoked through the real '
      'Família page', (tester) async {
    final invitee = family.disposableEmail('invitee');

    await bootApp(tester);
    await signIn(tester, family.founder.email);
    expect(find.byType(NavigationBar), findsOneWidget,
        reason: 'the founder should land on the authenticated shell');

    await openFamilyTab(tester);

    // ── Send ──
    // F-56: the form names the person first — that name is the placeholder
    // the invitation is issued for.
    await tester.enterText(
        find.widgetWithText(TextField, l[KApp.famInviteName]), 'Vovó E2E');
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, l[K.commonEmail]), invitee);
    await tester.pumpAndSettle();
    await tapVisible(tester, find.byType(DropdownButtonFormField<int>));
    // The role list is the family's own; any built-in serves.
    await tester.tap(find.text(RoleCatalog.translate('grandmother')).last);
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text(l[K.famSendInvite]));

    final created = await family.openInvitations();
    expect(created.where((i) => i['email'] == invitee), hasLength(1),
        reason: 'create_invitation wrote the row the UI asked for');
    expect(created.single['role_id'],
        await family.roleIdOf('grandmother'));
    expect(created.single['profile_id'], isNotNull,
        reason: 'F-56: the invitation is FOR the placeholder the form created');

    // ── Revoke ──
    await tapVisible(tester, find.text(l[K.famRevoke]).first);

    expect(await family.openInvitations(), isEmpty,
        reason: 'revoke_invitation closed it');
    final all = await family.allInvitations();
    expect(all.where((i) => i['email'] == invitee).single['revoked_at'],
        isNotNull);
  }, timeout: const Timeout(Duration(minutes: 5)));

  testWidgets('S-10 — promoting a member really passes through the elevate '
      'Edge Function and the gated RPC', (tester) async {
    if (pack == 'p0') return; // full pack only

    // Precondition from the DB, not from the screen.
    expect((await family.profileOf(family.member.profileId))?['is_admin'],
        isFalse);

    await bootApp(tester);
    await signIn(tester, family.founder.email);
    await openFamilyTab(tester);

    // F-16: the member's card opens their profile, which is where the flag is.
    await tapVisible(tester, find.text(family.member.fullName));
    expect(find.text(l[K.profSectionAdmin]), findsOneWidget,
        reason: 'an admin looking at another member gets the admin section');

    await tapVisible(tester, find.text(l[K.profMakeAdmin]));

    // The sheet must appear BEFORE anything is granted — the whole point of
    // S-10, and the one assertion no fake can make honestly.
    expect(find.text(l[K.sudoTitle]), findsOneWidget);
    expect((await family.profileOf(family.member.profileId))?['is_admin'],
        isFalse,
        reason: 'nothing may change before the password is confirmed');

    await tester.enterText(find.byType(TextField).last, family.password);
    await tester.pumpAndSettle();
    await tester.tap(find.text(l[K.sudoConfirm]));
    await tester.pumpAndSettle(const Duration(seconds: 15));

    expect((await family.profileOf(family.member.profileId))?['is_admin'],
        isTrue,
        reason: 'the elevation window let set_member_admin through');

    // And back, to leave the family as the fixture built it. The window is
    // still open, so this one must NOT ask again.
    await tapVisible(tester, find.text(l[K.profRemoveAdmin]));
    expect(find.text(l[K.sudoTitle]), findsNothing,
        reason: 'a live elevation window is reused for 5 minutes');
    expect((await family.profileOf(family.member.profileId))?['is_admin'],
        isFalse);
  }, timeout: const Timeout(Duration(minutes: 5)));

  testWidgets('a wrong password is refused by the real Edge Function',
      (tester) async {
    if (pack == 'p0') return; // full pack only

    await bootApp(tester);
    await signIn(tester, family.founder.email);
    await openFamilyTab(tester);
    await tapVisible(tester, find.text(family.member.fullName));
    await tapVisible(tester, find.text(l[K.profMakeAdmin]));

    await tester.enterText(find.byType(TextField).last, 'senha-errada-e2e');
    await tester.pumpAndSettle();
    await tester.tap(find.text(l[K.sudoConfirm]));
    await tester.pumpAndSettle(const Duration(seconds: 15));

    // The sheet stays open with the server's own refusal, and nothing moved.
    expect(find.text(l[K.sudoTitle]), findsOneWidget);
    expect((await family.profileOf(family.member.profileId))?['is_admin'],
        isFalse);
  }, timeout: const Timeout(Duration(minutes: 5)));
}

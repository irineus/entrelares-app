// The E2E lane the parity map opens with the first TWO-USER flow (T-54 +
// lote 3): the swap workflow driven through the real app, on a real emulator,
// against the dev project. One member requests, the app reboots as the other
// member, who approves — and the DATABASE is the assertion, not the UI.
//
// Pack filter (same convention as the web gate): `--dart-define=E2E_PACK=p0`
// runs the smoke only; the full pack runs on demand.
//
// Run locally:
//   flutter test integration_test/swap_workflow_test.dart --flavor dev \
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

/// S-15: the consent version the sign-up trigger stamps. Kept as a define so
/// a policy bump does not need a code change in the lane.
const policyVersion =
    String.fromEnvironment('E2E_POLICY_VERSION', defaultValue: '2026-07-30');

const pack = String.fromEnvironment('E2E_PACK', defaultValue: 'full');

final l = Localization(AppLanguage.ptBr);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late E2eFamily family;
  late DateTime targetDay;
  // Whether `app.main()` has already initialized the Supabase singleton in
  // this process. See `bootApp` for why the answer cannot simply be asked.
  var appBooted = false;

  setUpAll(() async {
    E2eFamily.requireKey();
    family = await E2eFamily.create(policyVersion: policyVersion);
    // A day the founder owns, comfortably inside the visible month.
    targetDay = DateTime.now().add(const Duration(days: 3));
    await family.seedDay(
        date: targetDay, scheduledParentId: family.founder.profileId);
  });

  tearDownAll(() async {
    // Always — green or red. The RPC's double-signature guard is what makes
    // this safe to run against the shared dev project.
    await family.purge();
  });

  /// Boots the real app with a clean local state, signed out.
  ///
  /// The sign-out is guarded because `Supabase.instance` is an ASSERTION, not
  /// a nullable getter: until `app.main()` has run once there is no singleton,
  /// and touching it throws *"You must initialize the supabase instance"* —
  /// which is what killed the FIRST boot of this test, i.e. every run.
  /// From the second boot on the singleton is alive (it is per PROCESS, the
  /// pilot's lesson 8), and signing out is precisely what makes the next user
  /// start clean. `Supabase.initialize` itself is idempotent in 2.17.2 — it
  /// logs and returns the existing instance — so calling `app.main()` again is
  /// safe; the package's own docstring still claims otherwise and is stale.
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

  /// Opens [target]'s day sheet, advancing the calendar to its MONTH first.
  ///
  /// Taking a full date rather than a day NUMBER is the whole fix. The lane's
  /// target is `now + 3 days`, the grid opens on the current month, and it
  /// renders blanks then `1..daysInMonth` — no tail of any neighbouring month.
  /// So on the last three days of any month the target rolls over: on
  /// 29/08/2026 the seeded day was 01/09 and `openDay(1)` found exactly one
  /// cell reading '1' — **01/08**, a PAST day, which opens the sheet in READ
  /// mode with no chips at all. The failure surfaced as "Bad state: No element"
  /// on a ChoiceChip finder, which names the widget and hides the cause, and
  /// the lane was green until 21:48 on the 28th purely because `now + 3` had
  /// not yet crossed a month.
  ///
  /// The same trap is waiting for every future date this file picks, so the
  /// navigation lives HERE and not at the call sites.
  Future<void> openDay(WidgetTester tester, DateTime target) async {
    final now = DateTime.now();
    final monthsAhead =
        (target.year - now.year) * 12 + (target.month - now.month);
    for (var i = 0; i < monthsAhead; i++) {
      await tester.tap(find.byTooltip(l[K.calNextMonth]));
      await tester.pumpAndSettle(const Duration(seconds: 2));
    }

    // SCOPED to the month grid, and that is the whole point. `find.text('28')`
    // over the entire tree also matches the day number wherever else it is
    // printed — the next-handoff card, the upcoming list — and those grow as
    // the family gains state, so a bare `.last` silently changes target
    // mid-test. It changed here: the founder's tap landed on the grid, and the
    // member's, with a pending request on screen, did not.
    //
    // `.last` INSIDE the grid stays, as the belt to that brace: within one
    // month's GridView the day number is unique, so it selects the only match.
    final cell = find
        .descendant(
            of: find.byType(GridView), matching: find.text('${target.day}'))
        .last;
    await tester.ensureVisible(cell);
    await tester.pumpAndSettle();
    await tester.tap(cell);
    await tester.pumpAndSettle(const Duration(seconds: 3));
  }

  testWidgets('p0 — a swap request travels between two real users and the '
      'approval moves the day', (tester) async {
    // ── User 1 (founder): propose the member as the day's actual parent ──
    await bootApp(tester);
    await signIn(tester, family.founder.email);
    expect(find.byType(NavigationBar), findsOneWidget,
        reason: 'the founder should land on the authenticated shell');

    await openDay(tester, targetDay);
    final memberChip =
        find.widgetWithText(ChoiceChip, family.member.fullName.split(' ').first);
    await tester.ensureVisible(memberChip.last);
    await tester.pumpAndSettle();
    await tester.tap(memberChip.last);
    await tester.pumpAndSettle();

    // F-44: the message rides the request.
    final message = find.widgetWithText(TextField, l[K.editorMessagePlaceholder]);
    if (message.evaluate().isNotEmpty) {
      await tester.enterText(message, 'E2E: preciso trocar');
      await tester.pumpAndSettle();
    }
    final save = find.widgetWithText(FilledButton, l[K.commonSave]);
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle(const Duration(seconds: 10));

    // The DB is the assertion: one open request targeted at the member.
    final opened = await family.openRequests();
    expect(opened, hasLength(1));
    expect(opened.single['status'], 'pending');
    expect(opened.single['target_profile_id'], family.member.profileId);
    expect(opened.single['proposed_actual_parent_id'], family.member.profileId);

    // The day itself must NOT have moved yet — the approval does that.
    final beforeApproval = await family.dayOf(targetDay);
    expect(beforeApproval?['actual_parent_id'], isNull);

    // ── User 2 (member): the frozen day awaits them; approve it ──
    await bootApp(tester);
    await signIn(tester, family.member.email);

    await openDay(tester, targetDay);
    // The `reason` carries the DIAGNOSIS, not just the claim. Two runs died
    // here saying only "found 0 widgets", which names the symptom and hides
    // every candidate cause: the request may have resolved, the tap may have
    // opened the ordinary editor, or no sheet may be open at all. The reason
    // string is the one channel guaranteed to reach the `flutter drive` log on
    // web, so it answers those three at once.
    // `textContaining`, and that is the whole defect. `find.text` matches the
    // widget's ENTIRE string, and the sheet renders `'$headerIcon '` before the
    // catalogue sentence — the app keeps its emoji inside the sentences it
    // writes (`screens/frozen_day_sheet.dart`). So the screen said
    // "⏳ Solicitação de troca pendente" while the finder asked for
    // "Solicitação de troca pendente", and the panel that was RIGHT THERE,
    // with the requester, the proposed carer and both buttons correct, read as
    // absent. Any assertion built from a catalogue key against a decorated
    // title has this shape.
    final panel = find.textContaining(l[K.frozenSwapTitle]);
    if (panel.evaluate().isEmpty) {
      final stillOpen = await family.openRequests();
      final onScreen = find
          .byType(Text)
          .evaluate()
          .map((e) => (e.widget as Text).data)
          .whereType<String>()
          .toList();
      fail('the approver taps a frozen day and gets the panel — '
          'open requests at this moment: $stillOpen | '
          'texts on screen: $onScreen');
    }
    expect(panel, findsOneWidget,
        reason: 'exactly one frozen panel, never two sheets stacked');
    await tester.tap(find.text(l[K.frozenApprove]));
    await tester.pumpAndSettle(const Duration(seconds: 10));

    // The approval applied the change and closed the request.
    expect(await family.openRequests(), isEmpty);
    final afterApproval = await family.dayOf(targetDay);
    expect(afterApproval?['actual_parent_id'], family.member.profileId);
  }, timeout: const Timeout(Duration(minutes: 5)));

  testWidgets('the approver sees the request on the Notifications page',
      (tester) async {
    if (pack == 'p0') return; // full pack only
    final day = DateTime.now().add(const Duration(days: 5));
    await family.seedDay(
        date: day, scheduledParentId: family.founder.profileId);

    await bootApp(tester);
    await signIn(tester, family.founder.email);
    await openDay(tester, day);
    final memberChip =
        find.widgetWithText(ChoiceChip, family.member.fullName.split(' ').first);
    await tester.ensureVisible(memberChip.last);
    await tester.pumpAndSettle();
    await tester.tap(memberChip.last);
    await tester.pumpAndSettle();
    final save = find.widgetWithText(FilledButton, l[K.commonSave]);
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle(const Duration(seconds: 10));

    await bootApp(tester);
    await signIn(tester, family.member.email);

    // The bell badge counts the request awaiting this member.
    await tester.tap(find.text(l[K.navNotificationsShort]));
    await tester.pumpAndSettle(const Duration(seconds: 8));
    expect(find.text(l[K.notifPageTitle]), findsOneWidget);
    expect(find.text(l[K.notifBtnApprove]), findsWidgets);

    await tester.tap(find.text(l[K.notifBtnReject]).first);
    await tester.pumpAndSettle(const Duration(seconds: 10));

    final requests = await family.openRequests();
    expect(requests.where((r) => r['schedule_date'].toString().endsWith(
        '-${day.day.toString().padLeft(2, '0')}')), isEmpty,
        reason: 'the rejection closed the request');
  }, timeout: const Timeout(Duration(minutes: 5)));
}

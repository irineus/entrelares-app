// U-49 — consistency polish #2, PR 1: the stragglers OUTSIDE the family
// screen (that file is U-47's while this ships, and its four sites come in a
// second PR once U-47 lands).
//
// Each test pins a SITE to the shared component it now uses. The point of the
// item is the sweep, and a sweep only holds if every site it touched is held
// by an assertion — otherwise the drift comes back one screen at a time, the
// way it arrived.
import 'dart:async';
import 'dart:io';

import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:entrelares_db_contracts/models/family.dart';
import 'package:entrelares_db_contracts/models/member.dart';
import 'package:entrelares_db_contracts/models/swap_request.dart';
import 'package:entrelares_app/screens/custom_roles_screen.dart';
import 'package:entrelares_app/screens/frozen_day_sheet.dart';
import 'package:entrelares_app/screens/reports_pdf_tab.dart';
import 'package:entrelares_app/services/sudo_service.dart';
import 'package:entrelares_app/theme/tokens.dart';
import 'package:entrelares_app/widgets/app_l10n.dart';
import 'package:entrelares_app/widgets/onboarding.dart';
import 'package:entrelares_app/widgets/sudo_sheet.dart';
import 'package:entrelares_app/widgets/ui/ui.dart';

import 'calendar_slice_test.dart' show FakeCustodyDataSource, ana, bruno;
import 'custom_roles_test.dart' as roles;
import 'family_page_test.dart' as family;
import 'lifecycle_test.dart' as lifecycle;
import 'profile_test.dart' as profile;
import 'reports_audit_test.dart' as audit;
import 'reports_pdf_test.dart' as pdf;
import 'reports_summary_test.dart' as summary;
import 'sudo_test.dart' as sudo;

final _l = Localization(AppLanguage.ptBr);

Widget _wrap(Widget child) => AppL10n(
  l: _l,
  setLanguage: (_) async {},
  child: MaterialApp(home: Scaffold(body: child)),
);

/// The year selector's options — read off the `DropdownButton` the form field
/// builds, which is the widget that actually carries `items`. The month
/// selector beside it has twelve; the year one never does.
List<int> _yearOptions(WidgetTester tester) => tester
    .widgetList<DropdownButton<int>>(find.byType(DropdownButton<int>))
    .map((d) => d.items!.map((i) => i.value!).toList())
    .firstWhere((values) => values.length != 12);

/// A source whose profile read waits for the test to let it through — the
/// only way to look at a screen WHILE it loads.
class _HeldSource extends FakeCustodyDataSource {
  _HeldSource() : super(members: const [ana, bruno], days: []);

  final gate = Completer<void>();

  @override
  Future<Member?> fetchOwnProfile() async {
    await gate.future;
    return super.fetchOwnProfile();
  }
}

void main() {
  group('AppBanner.action (item 4)', () {
    testWidgets('renders the label with its mark and fires the callback', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) => AppBanner(
              tone: context.tokens.info,
              message: 'gate',
              actionLabel: 'Ver Premium',
              actionIcon: Icons.auto_awesome,
              onAction: () => taps++,
            ),
          ),
        ),
      );

      expect(find.widgetWithText(TextButton, 'Ver Premium'), findsOne);
      expect(find.byIcon(Icons.auto_awesome), findsOne);
      await tester.tap(find.text('Ver Premium'));
      expect(taps, 1);
    });

    testWidgets('a banner with no action draws no button', (tester) async {
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) =>
                AppBanner(tone: context.tokens.info, message: 'plain'),
          ),
        ),
      );

      expect(find.byType(TextButton), findsNothing);
    });

    test('label and callback come together, and the icon needs a label', () {
      expect(
        () => AppBanner(
          tone: AppTokens.light.info,
          message: 'm',
          actionLabel: 'x',
        ),
        throwsAssertionError,
      );
      expect(
        () => AppBanner(
          tone: AppTokens.light.info,
          message: 'm',
          onAction: () {},
        ),
        throwsAssertionError,
      );
      expect(
        () => AppBanner(
          tone: AppTokens.light.info,
          message: 'm',
          actionIcon: Icons.auto_awesome,
        ),
        throwsAssertionError,
      );
    });
  });

  group('gate cards became banners (item 4)', () {
    testWidgets('custom roles: the Premium gate is an AppBanner whose action '
        'opens the plan', (tester) async {
      var opened = false;
      await tester.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _wrap(
          CustomRolesScreen(
            dataSource: roles.source(plan: 'free'),
            onSeePremium: () => opened = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(AppBanner),
          matching: find.text(_l[K.rolesPremiumGate]),
        ),
        findsOne,
      );
      expect(
        tester
            .widgetList<Card>(find.byType(Card))
            .every((card) => card.color == null),
        isTrue,
        reason: 'no Card on this screen is painted by hand any more',
      );

      await tester.tap(find.text(_l[K.famSeePremium]));
      expect(opened, isTrue);
    });

    testWidgets('profile: the frozen notice is a danger AppBanner', (
      tester,
    ) async {
      const departed = Member(
        id: 2,
        fullName: 'Bruno Lima',
        userId: 'u2',
        roleId: 2,
        email: 'bruno@example.com',
        leftAt: '2026-07-01T00:00:00Z',
      );
      await profile.pumpProfile(
        tester,
        profile.source(members: const [profile.adminMember, departed]),
        profileId: 2,
      );

      final banner = tester.widget<AppBanner>(
        find.ancestor(
          of: find.text(_l[K.profFrozenBanner]),
          matching: find.byType(AppBanner),
        ),
      );
      expect(banner.tone, AppTokens.light.danger);
      expect(banner.icon, Icons.lock_outline);
      expect(
        tester
            .widgetList<Card>(find.byType(Card))
            .every((card) => card.color == null),
        isTrue,
      );
    });
  });

  testWidgets('item 7: the profile\'s section title is the shared header', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await profile.pumpProfile(tester, profile.source());

    // The leave section shows its title only once the danger zone is opened.
    await tester.ensureVisible(find.text(_l[K.profLeaveOpen]));
    await tester.tap(find.text(_l[K.profLeaveOpen]));
    await tester.pumpAndSettle();

    expect(
      find.widgetWithText(AppSectionHeader, _l[K.profLeaveTitle]),
      findsOne,
    );
  });

  testWidgets('item 6: the frozen sheet\'s facts are AppListRows, the quoted '
      'message italic', (tester) async {
    final request = SwapRequest(
      id: 5,
      scheduleDate: DateTime(2026, 8, 20),
      requestingProfileId: 2,
      targetProfileId: 1,
      proposedActualParentId: 2,
      proposedHandoffTime: '14:30:00',
      requestMessage: 'Consulta médica',
      status: 'pending',
      createdAt: '2026-08-18T10:00:00Z',
    );
    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showFrozenDaySheet(
              context: context,
              request: request,
              allProfiles: const [ana, bruno],
              ownProfileId: 1,
              dataSource: FakeCustodyDataSource(
                members: const [ana, bruno],
                days: [],
              ),
            ),
            child: const Text('abrir'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    // Requester, proposed parent, time, message, requested at, auto-approval.
    expect(find.byType(AppListRow), findsNWidgets(6));
    expect(
      find.descendant(
        of: find.byType(AppListRow),
        matching: find.text(_l[K.frozenRequester]),
      ),
      findsOne,
    );
    final message = tester.widget<Text>(find.text('Consulta médica'));
    expect(message.style?.fontStyle, FontStyle.italic);
  });

  group('item 8: the sudo sheet is an AppSheetFrame', () {
    testWidgets('title, hint and the pinned action pair', (tester) async {
      final service = SudoService(sudo.fakeSource());
      await tester.pumpWidget(
        sudo.harness(
          sudo: service,
          onTap: (context) => showSudoSheet(context: context, sudo: service),
        ),
      );
      await tester.tap(find.text('gatilho'));
      await tester.pumpAndSettle();

      final frame = tester.widget<AppSheetFrame>(find.byType(AppSheetFrame));
      expect(frame.title, _l[K.sudoTitle]);
      expect(frame.subtitle, _l[K.sudoHint]);
      expect(frame.primaryLabel, _l[K.sudoConfirm]);
      expect(frame.secondaryLabel, _l[K.commonCancel]);
      expect(find.widgetWithText(FilledButton, _l[K.sudoConfirm]), findsOne);

      await tester.tap(find.text(_l[K.commonCancel]));
      await tester.pumpAndSettle();
      expect(find.byType(AppSheetFrame), findsNothing);
    });
  });

  group('item 3: one year range across the three report tabs', () {
    testWidgets('Resumo', (tester) async {
      await summary.pumpSummary(tester, summary.source());
      expect(_yearOptions(tester), reportYearRange(summary.today.year));
    });

    testWidgets('Histórico', (tester) async {
      await audit.pumpAudit(tester, audit.source());
      await tester.tap(find.text(_l[K.repByYear]));
      await tester.pumpAndSettle();
      expect(_yearOptions(tester), reportYearRange(audit.today.year));
    });

    testWidgets('PDF', (tester) async {
      await pdf.pumpPdf(tester, pdf.source());
      expect(_yearOptions(tester), reportYearRange(pdf.today.year));
    });
  });

  testWidgets('item 2 (U-29 R4): the PDF tab waits as a skeleton of its '
      'filter card, heading already in place', (tester) async {
    final ds = _HeldSource()
      ..family = const Family(id: 7, name: 'Souza', plan: 'premium');
    await tester.binding.setSurfaceSize(const Size(800, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _wrap(
        ReportsPdfTab(dataSource: ds, now: () => DateTime(2026, 8, 19, 21, 5)),
      ),
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(AppSkeleton), findsWidgets);
    expect(find.bySemanticsLabel(_l[K.pdfLoading]), findsOne);
    expect(
      find.text(_l[K.pdfHeading]),
      findsOne,
      reason: 'the heading never depended on the read',
    );

    ds.gate.complete();
    await tester.pumpAndSettle();

    expect(find.byType(AppSkeleton), findsNothing);
    expect(find.text(_l[K.pdfGenerate]), findsOne);
  });

  testWidgets(
    'item 10: the onboarding strip is painted with the neutral token',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          OnboardingLauncher(
            signals: const OnboardingSignals(),
            onOpen: () {},
            onDismiss: () {},
          ),
        ),
      );

      final strip = tester.widget<Material>(
        find
            .ancestor(
              of: find.byIcon(Icons.checklist),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(strip.color, AppTokens.light.neutral.container);
      final icon = tester.widget<Icon>(find.byIcon(Icons.checklist));
      expect(icon.color, AppTokens.light.neutral.onContainer);
    },
  );

  group('PR 2 — the family screen (after U-47)', () {
    testWidgets(
      'item 4: the F-37 cap notice is an info AppBanner whose action is '
      'the gate CTA',
      (tester) async {
        var opened = false;
        await family.pumpFamily(
          tester,
          family.source(),
          onOpenPlan: () => opened = true,
        );

        final banner = tester.widget<AppBanner>(
          find.ancestor(
            of: find.text(_l[K.famFreeCapNotice]),
            matching: find.byType(AppBanner),
          ),
        );
        expect(banner.tone, AppTokens.light.info);
        expect(banner.actionLabel, _l[K.famSeePremium]);
        await tester.tap(find.text(_l[K.famSeePremium]));
        expect(opened, isTrue);
      },
    );

    testWidgets('item 4: without a plan door the notice has no action', (
      tester,
    ) async {
      await family.pumpFamily(tester, family.source());

      final banner = tester.widget<AppBanner>(
        find.ancestor(
          of: find.text(_l[K.famFreeCapNotice]),
          matching: find.byType(AppBanner),
        ),
      );
      expect(banner.actionLabel, isNull);
      expect(find.text(_l[K.famSeePremium]), findsNothing);
    });

    testWidgets('item 5: deletion votes are rows with a badge per answer', (
      tester,
    ) async {
      await lifecycle.pumpFamily(
        tester,
        lifecycle.source(
          members: const [lifecycle.ana, lifecycle.bruno, lifecycle.carla],
          pending: lifecycle.deletion(),
        ),
      );

      // Two voters (the requester does not vote on their own request).
      final badges = tester
          .widgetList<AppBadge>(find.byType(AppBadge))
          .toList();
      expect(badges.where((b) => b.text == _l[K.famDelVoteWaiting]).length, 2);
      expect(
        find.descendant(
          of: find.byType(AppListRow),
          matching: find.byType(AppBadge),
        ),
        findsNWidgets(2),
      );
      expect(
        find.textContaining(' — ${_l[K.famDelVoteWaiting]}'),
        findsNothing,
        reason: 'no vote is prose any more',
      );
    });

    testWidgets('item 8: the attach-pending sheet is an AppSheetFrame', (
      tester,
    ) async {
      await family.pumpFamily(
        tester,
        family.source(
          members: const [family.admin],
          invitations: [family.pendingInvite()],
        ),
      );
      await tester.tap(find.text(_l[KApp.famAttachInvite]));
      await tester.pumpAndSettle();

      final frame = tester.widget<AppSheetFrame>(find.byType(AppSheetFrame));
      expect(frame.subtitle, _l[KApp.famAttachHint]);
      expect(frame.primaryLabel, _l[KApp.famAttachInvite]);
      expect(frame.secondaryLabel, _l[K.commonCancel]);
    });

    testWidgets('item 8: the invite-pending sheet is an AppSheetFrame', (
      tester,
    ) async {
      await family.pumpFamily(
        tester,
        family.source(
          members: const [family.admin, family.pending],
          plan: 'premium',
        ),
      );
      await tester.tap(find.text(_l[KApp.famPendingInvite]));
      await tester.pumpAndSettle();

      final frame = tester.widget<AppSheetFrame>(find.byType(AppSheetFrame));
      expect(frame.primaryLabel, _l[K.famSendInvite]);
      expect(frame.secondaryLabel, _l[K.commonCancel]);
    });

    test('the whole sweep: no Card painted by hand is left in lib/', () {
      // The third gate lives in no_color_literal_test; this is the item's
      // own acceptance line, read from source.
      final offenders = <String>[];
      for (final file
          in Directory('lib')
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart'))) {
        final path = file.path.replaceAll('\\', '/');
        if (path.contains('widgets/ui/') || path.contains('/theme/')) continue;
        if (RegExp(r'Card\(\s*color:').hasMatch(file.readAsStringSync())) {
          offenders.add(path);
        }
      }
      expect(offenders, isEmpty);
    });
  });

  test(
    'item 1 (verified, not re-touched): no screen builds a clock by hand',
    () {
      // U-42 already routed the two hand-formatted times through
      // `formatTimeString`. The `padLeft` calls that remain build the WIRE
      // string (`HH:mm:00`) the server stores, never a displayed time — this
      // pins that no display site grows one back.
      final offenders = <String>[];
      for (final path in [
        'lib/screens/notifications_screen.dart',
        'lib/screens/frozen_day_sheet.dart',
      ]) {
        final src = File(path).readAsStringSync();
        if (RegExp(r"\.padLeft\(2, '0'\)").hasMatch(src)) offenders.add(path);
      }
      expect(offenders, isEmpty);
    },
  );
}

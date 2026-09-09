// U-23 — the first-run checklist, the "Como funciona a troca" sheet and the
// 4-stop tour.
//
// The property the whole feature rests on: the checklist reads REAL family
// state. A card that ticked itself off from a "seen" flag would tell someone
// they had finished something they never did — worse than showing no card at
// all, because the card's entire claim is that it describes THEIR family.
//
// The one deliberate exception is understanding, which is nobody's row.
import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:entrelares_db_contracts/models/care_schedule.dart';
import 'package:entrelares_db_contracts/models/member.dart';
import 'package:entrelares_app/screens/calendar_screen.dart';
import 'package:entrelares_app/services/admin_mode.dart';
import 'package:entrelares_app/services/custody_data_source.dart';
import 'package:entrelares_app/services/onboarding_service.dart';
import 'package:entrelares_app/widgets/app_l10n.dart';
import 'package:entrelares_app/widgets/onboarding.dart';

import 'calendar_slice_test.dart' show FakeCustodyDataSource, bruno;

/// A founder alone in a fresh family: nothing done, nothing dismissed.
const fresh = Member(id: 1, fullName: 'Ana Souza', userId: 'u1', colorSlot: 1);

Member seenTour({DateTime? dismissed, DateTime? explained}) => Member(
      id: 1,
      fullName: 'Ana Souza',
      userId: 'u1',
      colorSlot: 1,
      onboardingTourSeenAt: DateTime.utc(2026, 8, 1),
      onboardingDismissedAt: dismissed,
      onboardingSwapExplainedAt: explained,
    );

FakeCustodyDataSource source({
  List<Member> members = const [fresh],
  List<CareSchedule> days = const [],
}) =>
    FakeCustodyDataSource(members: members, days: days.toList());

Future<void> pumpCalendar(
  WidgetTester tester,
  FakeCustodyDataSource ds, {
  OnboardingService? onboarding,
  TourKeys? tourKeys,
  VoidCallback? onOpenFamily,
}) async {
  await tester.binding.setSurfaceSize(const Size(600, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(AppL10n(
    l: Localization(AppLanguage.ptBr),
    setLanguage: (_) async {},
    child: MaterialApp(
      home: CalendarScreen(
        dataSource: ds,
        adminMode: AdminMode(),
        onboarding: onboarding ?? OnboardingService(ds),
        tourKeys: tourKeys,
        onOpenFamily: onOpenFamily,
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  final l = Localization(AppLanguage.ptBr);

  group('the launcher', () {
    testWidgets('a fresh family sees 0 de 3', (tester) async {
      await pumpCalendar(tester, source());

      expect(find.text(l[K.onbChecklistTitle]), findsOne);
      expect(find.text(l.format(K.onbChecklistProgress, [0, 3])), findsOne);
    });

    testWidgets('an invitee arrives with 2 de 3 — it falls out of reading real '
        'state, not a special case', (tester) async {
      final ds = source(
        members: const [fresh, bruno],
        days: [
          CareSchedule(
            id: 1,
            scheduleDate: DateTime.now(),
            scheduledParentId: 1,
            revision: 1,
            revisionToken: 't',
          ),
        ],
      );
      await pumpCalendar(tester, ds);

      expect(find.text(l.format(K.onbChecklistProgress, [2, 3])), findsOne);
    });

    testWidgets('finishing everything removes the card', (tester) async {
      final ds = source(
        members: [seenTour(explained: DateTime.utc(2026, 8, 2)), bruno],
        days: [
          CareSchedule(
            id: 1,
            scheduleDate: DateTime.now(),
            scheduledParentId: 1,
            revision: 1,
            revisionToken: 't',
          ),
        ],
      );
      await pumpCalendar(tester, ds);

      expect(find.text(l[K.onbChecklistTitle]), findsNothing);
    });

    testWidgets('dismissing hides it and stamps the profile', (tester) async {
      final ds = source();
      await pumpCalendar(tester, ds);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(ds.stamps, contains(OnboardingStamp.dismissed));
      expect(find.text(l[K.onbChecklistTitle]), findsNothing);
    });

    testWidgets('a dismissed profile costs NO onboarding queries — the '
        'calendar is the hottest screen in the app', (tester) async {
      final ds = source(members: [seenTour(dismissed: DateTime.utc(2026, 8, 3))]);
      await pumpCalendar(tester, ds);

      expect(ds.onboardingFactReads, isEmpty);
      expect(find.text(l[K.onbChecklistTitle]), findsNothing);
    });
  });

  group('the checklist sheet', () {
    testWidgets('lists the three steps with their marks', (tester) async {
      await pumpCalendar(tester, source());

      await tester.tap(find.text(l[K.onbChecklistTitle]));
      await tester.pumpAndSettle();

      expect(find.text(l[K.onbStepInviteTitle]), findsOne);
      expect(find.text(l[K.onbStepPlanTitle]), findsOne);
      expect(find.text(l[K.onbStepSwapTitle]), findsOne);
      expect(find.text('⬜'), findsNWidgets(3));
    });

    testWidgets('the invite step navigates to the family page', (tester) async {
      var opened = false;
      await pumpCalendar(tester, source(), onOpenFamily: () => opened = true);

      await tester.tap(find.text(l[K.onbChecklistTitle]));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l[K.onbStepInviteAction]));
      await tester.pumpAndSettle();

      expect(opened, isTrue);
    });

    testWidgets('opening the explanation IS completing step 3 — stamped '
        'before the sheet renders', (tester) async {
      final ds = source();
      await pumpCalendar(tester, ds);

      await tester.tap(find.text(l[K.onbChecklistTitle]));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l[K.onbStepSwapAction]));
      await tester.pumpAndSettle();

      expect(ds.stamps, contains(OnboardingStamp.swapExplained));
      expect(find.text(l[K.onbSwapSheetTitle]), findsOne);
      expect(find.text(l[K.onbSwapPlannedTitle]), findsOne);
      expect(find.text(l[K.onbSwapHistoryTitle]), findsOne);
    });

    testWidgets('a completed step keeps its action and swaps the hint',
        (tester) async {
      await pumpCalendar(tester, source(members: const [fresh, bruno]));

      await tester.tap(find.text(l[K.onbChecklistTitle]));
      await tester.pumpAndSettle();

      expect(find.text(l[K.onbStepInviteDoneHint]), findsOne);
      expect(find.text(l[K.onbStepInviteAction]), findsOne);
    });
  });

  group('the guided tour', () {
    testWidgets('runs on the first session and walks the four stops',
        (tester) async {
      await pumpCalendar(tester, source(), tourKeys: TourKeys());

      expect(find.text(l[K.tourTodayTitle]), findsOne);
      expect(find.text(l.format(K.tourProgress, [1, 4])), findsOne);
      // No "previous" on the first stop.
      expect(find.text(l[K.tourPrevious]), findsNothing);

      for (final title in [
        l[K.tourColoursTitle],
        l[K.tourWizardTitle],
        l[K.tourNotificationsTitle],
      ]) {
        await tester.tap(find.text(l[K.tourNext]));
        await tester.pumpAndSettle();
        expect(find.text(title), findsOne);
      }

      // The last stop finishes instead of advancing.
      expect(find.text(l[K.tourNext]), findsNothing);
      expect(find.text(l[K.tourFinish]), findsOne);
    });

    testWidgets('going back is possible from the second stop on',
        (tester) async {
      await pumpCalendar(tester, source(), tourKeys: TourKeys());

      await tester.tap(find.text(l[K.tourNext]));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l[K.tourPrevious]));
      await tester.pumpAndSettle();

      expect(find.text(l[K.tourTodayTitle]), findsOne);
    });

    testWidgets('finishing stamps it and hands over to the checklist',
        (tester) async {
      final ds = source();
      await pumpCalendar(tester, ds, tourKeys: TourKeys());

      await tester.tap(find.text(l[K.tourSkip]));
      await tester.pumpAndSettle();

      expect(ds.stamps, contains(OnboardingStamp.tourSeen));
      // The hand-off: a first-run tour ends on the checklist, not on nothing.
      expect(find.text(l[K.onbChecklistIntro]), findsOne);
    });

    testWidgets('does NOT run for someone who already saw it', (tester) async {
      await pumpCalendar(tester, source(members: [seenTour()]),
          tourKeys: TourKeys());

      expect(find.text(l[K.tourTodayTitle]), findsNothing);
    });

    testWidgets('every stop has a registered target on this screen — the Dart '
        'twin of the web\'s selector-existence test', (tester) async {
      final keys = TourKeys();
      await pumpCalendar(tester, source(members: [seenTour()]), tourKeys: keys);

      // The notifications tab belongs to the shell, which this harness does
      // not build; the other three must be here and measurable.
      for (final target in [
        TourTarget.todayCard,
        TourTarget.calendarLegend,
        TourTarget.wizardButton,
      ]) {
        expect(keys.isMounted(target), isTrue,
            reason: '$target has no widget registered on the calendar');
        expect(keys.rectOf(target), isNotNull);
      }
    });

    testWidgets('a target with no widget degrades to a card with no spotlight',
        (tester) async {
      final keys = TourKeys();
      await pumpCalendar(tester, source(members: [seenTour()]), tourKeys: keys);

      // Never registered by this harness.
      expect(keys.isMounted(TourTarget.notificationsTab), isFalse);
      expect(keys.rectOf(TourTarget.notificationsTab), isNull);
    });
  });

  group('the service', () {
    test('skips the swap-participation read once the explanation is stamped',
        () async {
      final ds = source();
      final service = OnboardingService(ds);

      await service.loadSignals(
          me: seenTour(explained: DateTime.utc(2026, 8, 2)),
          members: const [fresh]);

      expect(ds.onboardingFactReads, [false]);
    });

    test('asks for an open invitation only while nobody holds the second seat',
        () async {
      final ds = source()..openInvitationExists = true;
      final service = OnboardingService(ds);

      final alone =
          await service.loadSignals(me: fresh, members: const [fresh]);
      expect(alone.hasOpenInvitation, isTrue);

      final together =
          await service.loadSignals(me: fresh, members: const [fresh, bruno]);
      expect(together.hasOpenInvitation, isFalse,
          reason: 'a live second member already settles the step');
    });

    test('reopening raises the session flag AND clears the stored dismissal',
        () async {
      final ds = source();
      final service = OnboardingService(ds);

      await service.reopenChecklist();

      expect(service.checklistReopened, isTrue);
      expect(ds.dismissalsCleared, 1);
    });

    test('a reopened checklist loads its signals even while dismissed',
        () async {
      final ds = source();
      final service = OnboardingService(ds)..checklistReopened = true;

      await service.loadSignals(
          me: seenTour(dismissed: DateTime.utc(2026, 8, 3)),
          members: const [fresh]);

      expect(ds.onboardingFactReads, isNotEmpty,
          reason: 'an explicit request must never silently do nothing');
    });
  });

  testWidgets('an English session renders the checklist in English',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final ds = source();
    await tester.pumpWidget(AppL10n(
      l: Localization(AppLanguage.en),
      setLanguage: (_) async {},
      child: MaterialApp(
        home: CalendarScreen(
          dataSource: ds,
          adminMode: AdminMode(),
            onboarding: OnboardingService(ds),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text(Localization(AppLanguage.en)[K.onbChecklistTitle]),
        findsOne);
  });

  group('U-29 regressions (owner-reported)', () {
    testWidgets('dismissing a REOPENED checklist removes it — the session '
        'reopen flag is cleared, not just the stamp', (tester) async {
      // All steps done and previously dismissed: only the reopen flag keeps
      // the launcher visible, which is exactly the state the ✕ could not
      // escape before.
      final ds = source(members: [
        seenTour(
            dismissed: DateTime.utc(2026, 8, 2),
            explained: DateTime.utc(2026, 8, 1)),
      ]);
      final onboarding = OnboardingService(ds)..checklistReopened = true;
      await pumpCalendar(tester, ds, onboarding: onboarding);

      expect(find.text(l[K.onbChecklistTitle]), findsOne);

      await tester.tap(find.byTooltip(l[K.onbChecklistDismissAria]));
      await tester.pumpAndSettle();

      expect(find.text(l[K.onbChecklistTitle]), findsNothing);
      expect(onboarding.checklistReopened, isFalse);
    });

    testWidgets('an explicit tour replay pings the LIVING calendar — no '
        'reload in between, and a second replay still works', (tester) async {
      final keys = TourKeys();
      final ds = source(members: [seenTour()]);
      final onboarding = OnboardingService(ds);
      await pumpCalendar(tester, ds, onboarding: onboarding, tourKeys: keys);

      // Already seen: the tour must not auto-run.
      expect(find.text(l.format(K.tourProgress, [1, 4])), findsNothing);

      onboarding.tourReplayRequested = true;
      await tester.pumpAndSettle();
      expect(find.text(l.format(K.tourProgress, [1, 4])), findsOne);
      await tester.tap(find.text(l[K.tourSkip]));
      await tester.pumpAndSettle();

      // The old `_tourShown` gate blocked any second replay in a session.
      onboarding.tourReplayRequested = true;
      await tester.pumpAndSettle();
      expect(find.text(l.format(K.tourProgress, [1, 4])), findsOne);
      await tester.tap(find.text(l[K.tourSkip]));
      await tester.pumpAndSettle();
    });

    testWidgets('"Rever os primeiros passos" pings the LIVING calendar — the '
        'banner returns with no reload in between (round 3)', (tester) async {
      // Previously dismissed: the banner starts hidden, and the State stays
      // alive in the tab stack, so no reload runs when the user lands back
      // from the profile. The reopen used to rely on exactly that reload.
      final ds = source(members: [
        seenTour(
            dismissed: DateTime.utc(2026, 8, 2),
            explained: DateTime.utc(2026, 8, 1)),
      ]);
      final onboarding = OnboardingService(ds);
      await pumpCalendar(tester, ds, onboarding: onboarding);

      expect(find.text(l[K.onbChecklistTitle]), findsNothing);

      // The profile button's exact call: the service notifies, the calendar
      // reloads its signals AND opens the checklist sheet — the button
      // promises the first steps, not a launcher to tap (round 5).
      await onboarding.reopenChecklist();
      await tester.pumpAndSettle();

      expect(find.text(l[K.onbChecklistIntro]), findsOne,
          reason: 'the sheet itself must open on landing');
      // Banner behind + sheet title.
      expect(find.text(l[K.onbChecklistTitle]), findsNWidgets(2));

      // Closing the sheet leaves the banner as the way back in.
      await tester.tap(find.text(l[K.commonClose]));
      await tester.pumpAndSettle();
      expect(find.text(l[K.onbChecklistTitle]), findsOne);
      expect(find.text(l[K.onbChecklistIntro]), findsNothing);

      // A later ping (a tour replay, say) must NOT reopen the sheet: the
      // open request is one-shot. (No tourKeys here, so the replay itself
      // degrades to nothing — only the notify matters.)
      onboarding.tourReplayRequested = true;
      await tester.pumpAndSettle();
      expect(find.text(l[K.onbChecklistIntro]), findsNothing);
    });

    testWidgets('the spotlight is measured against the OVERLAY, not the '
        'window — the web centres the app in a width-capped box (F-56 QA)',
        (tester) async {
      // A wide surface with the app in a 360px box in the middle: the overlay
      // starts 220px from the window's left edge, exactly the web's shape.
      await tester.binding.setSurfaceSize(const Size(800, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final keys = TourKeys();
      await tester.pumpWidget(AppL10n(
        l: Localization(AppLanguage.ptBr),
        setLanguage: (_) async {},
        child: MaterialApp(
          builder: (context, child) =>
              Center(child: SizedBox(width: 360, child: child)),
          home: Scaffold(
            body: Builder(
              builder: (context) => Column(
                children: [
                  FilledButton(
                    onPressed: () =>
                        showGuidedTour(context: context, keys: keys),
                    child: const Text('go'),
                  ),
                  // Stands in for the today card — the first stop's target.
                  Container(
                    key: keys.keyFor(TourTarget.todayCard),
                    height: 80,
                  ),
                ],
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      final paint = tester.widget<CustomPaint>(find.byWidgetPredicate((w) =>
          w is CustomPaint &&
          w.painter.runtimeType.toString() == '_SpotlightPainter'));
      final hole = (paint.painter as dynamic).target as Rect;
      final overlay = tester.getTopLeft(find.byType(Overlay).last);
      final targetInWindow =
          tester.getRect(find.byKey(keys.keyFor(TourTarget.todayCard)));

      // Before the fix the hole carried the window's x (220px too far right,
      // off the app's own box); now it is the target's rect in overlay space.
      expect(hole.left, closeTo(targetInWindow.left - overlay.dx, 0.5));
      expect(hole.top, closeTo(targetInWindow.top - overlay.dy, 0.5));
      expect(hole.width, closeTo(360, 0.5));
    });

    testWidgets('the tour card flips to the top when the target lives at the '
        'bottom — step 4 spotlights the notifications tab (round 3)',
        (tester) async {
      final keys = TourKeys();
      await tester.pumpWidget(AppL10n(
        l: Localization(AppLanguage.ptBr),
        setLanguage: (_) async {},
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Column(
                children: [
                  FilledButton(
                    onPressed: () =>
                        showGuidedTour(context: context, keys: keys),
                    child: const Text('go'),
                  ),
                  const Spacer(),
                  // Stands in for the bottom navigation's notifications tab.
                  Container(
                    key: keys.keyFor(TourTarget.notificationsTab),
                    height: 56,
                  ),
                ],
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      final screen = tester.getSize(find.byType(MaterialApp));
      Rect card() => tester.getRect(find.byType(Card));

      // Steps 1–3: their targets are not mounted here, so the card keeps its
      // bottom berth.
      expect(card().center.dy, greaterThan(screen.height / 2));
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.text(l[K.tourNext]));
        await tester.pumpAndSettle();
      }

      // Step 4: the target IS the bottom — the card must sit at the top,
      // fully clear of what it is describing.
      expect(card().center.dy, lessThan(screen.height / 2));
      final target = tester
          .getRect(find.byKey(keys.keyFor(TourTarget.notificationsTab)));
      expect(card().bottom, lessThan(target.top),
          reason: 'the card covered the very tab the stop spotlights');
    });
  });
}

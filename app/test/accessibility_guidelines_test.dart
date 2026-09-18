// U-32 — the accessibility that can be MEASURED without a device.
//
// U-11 gave the Blazor client its ARIA pass; the Flutter app never had one,
// and the coverage it did have was whatever each item happened to need. The
// TalkBack pass on a real phone is the owner's (the card's first deliverable
// and the U-32 protocol page); this file is the half a widget test can hold,
// so the next screen cannot silently ship an unnamed button or a 3:1 label.
//
// Three gates, each with the reason its shape is what it is:
//
// 1. TAP TARGETS — our own walk over the semantics tree (the SDK's
//    `androidTapTargetGuideline` cannot take an exception). Material's 48 dp
//    everywhere, with two measured exceptions: inside the month grid the
//    floor is WCAG 2.5.5's 44 dp, because U-28 decided the whole month is on
//    screen at once and that fixes the cell at (360 − 16 − 6·3)/7 = 45.7 dp
//    on a 360 dp phone (44.3 on a 344 dp one; the 3 dp gutter takes the
//    centre-to-centre distance to 48.7); and the Google button is the
//    vendor's own 40 dp at full width (U-45). Both are listed by rect, never
//    by label, so a third small target near them still fails.
// 2. LABELLED TARGETS — the SDK's guideline as is: a tappable node with no
//    label and no tooltip is what TalkBack reads as "button". The first run
//    (17/09/2026) found two: the ✓/✕ of the family rename row.
// 3. CONTRAST — read from the TOKENS, not sampled from pixels. The SDK's
//    `textContrastGuideline` clusters the pixels under a text node's rect,
//    and on 12–14 px anti-aliased text, on a chip whose rect includes its
//    own tint, or on an emoji the test host cannot draw, it measured 2.60 for
//    a pair whose tokens sit at 4.83, 1.00 for every emoji cell and 1.11 for
//    a segmented button — noise that would be silenced with exceptions until
//    it caught nothing. The tokens are exact: every pair a screen writes text
//    with (`text`/`textMuted` on both surfaces, `onSolid`/`solid` and
//    `onContainer`/`container` of every tone, slot and the swap) clears AA
//    (4.5:1) in BOTH themes, and a `solid` used as an icon clears 1.4.11's
//    3:1 on both surfaces. The first run found three light pairs under AA
//    (slot 0 at 2.54 and 4.39, slot 4 at 3.56, success at 3.30); the tokens
//    moved, the screens did not.
//
// 4. WHAT THE DEVICE HEARD — the owner's TalkBack pass (18/09/2026, the
//    other half of U-32) found three things no guideline measures, pinned
//    here so they stay fixed: an avatar's initial read before the name ("I,
//    Irineu…"), the bell badge read as a bare "2" before "Notificações", and an
//    audit diff whose struck (removed) value was read as if current — the
//    strikethrough and the red/green were the only vector.
//
// Every screen is pumped on a 360×740 phone with the real Inter, in light and
// dark, from the fixtures the screen's own suite uses — so a scene here is the
// screen as shipped, not a mock of it. Sheets are opened the way a finger
// opens them. What the file does NOT check, on purpose: reading order,
// live-region timing and what a hint sounds like — only a screen reader on a
// device can, which is the other half of U-32.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:entrelares_app/screens/calendar_screen.dart';
import 'package:entrelares_app/screens/custom_roles_screen.dart';
import 'package:entrelares_app/screens/day_sheet.dart';
import 'package:entrelares_app/screens/family_plan_screen.dart';
import 'package:entrelares_app/screens/family_screen.dart';
import 'package:entrelares_app/screens/home_shell.dart';
import 'package:entrelares_app/screens/login_screen.dart';
import 'package:entrelares_app/screens/notifications_screen.dart';
import 'package:entrelares_app/screens/profile_screen.dart';
import 'package:entrelares_app/screens/register_screen.dart';
import 'package:entrelares_app/screens/reports_audit_tab.dart';
import 'package:entrelares_app/screens/reports_pdf_tab.dart';
import 'package:entrelares_app/screens/reports_screen.dart';
import 'package:entrelares_app/services/account_identity.dart';
import 'package:entrelares_app/services/admin_mode.dart';
import 'package:entrelares_app/services/notification_badge.dart';
import 'package:entrelares_app/services/push_messaging.dart';
import 'package:entrelares_app/services/push_service.dart';
import 'package:entrelares_app/services/sudo_service.dart';
import 'package:entrelares_app/theme/app_theme.dart';
import 'package:entrelares_app/theme/tokens.dart';
import 'package:entrelares_app/widgets/app_l10n.dart';
import 'package:entrelares_app/widgets/google_sign_in_button.dart';
import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'calendar_slice_test.dart' as cal;
import 'custom_roles_test.dart' as roles;
import 'family_page_test.dart' as fam;
import 'frozen_day_test.dart' as frz;
import 'profile_test.dart' as prof;
import 'push_service_test.dart' as psh;
import 'register_test.dart' as reg;
import 'reports_audit_test.dart' as audit;
import 'reports_summary_test.dart' as rep;

final pt = Localization(AppLanguage.ptBr);

// ───────────────────────────────────────────────────────── the host ──

/// The theme's family, so a target's width is the real one (the host's
/// fallback font draws every glyph as a square).
Future<void> _loadRealFonts() async {
  Future<ByteData> bytes(String file) async => ByteData.sublistView(
    Uint8List.fromList(await File('assets/fonts/$file').readAsBytes()),
  );
  final inter = FontLoader('Inter');
  for (final f in [
    'Inter-Regular.ttf',
    'Inter-Medium.ttf',
    'Inter-SemiBold.ttf',
    'Inter-Bold.ttf',
  ]) {
    inter.addFont(bytes(f));
  }
  await inter.load();
}

const _phone = Size(360, 740);

Future<void> _usePhone(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(_phone);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  tester.view.physicalSize = _phone;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Widget _host(Widget home, {required bool dark}) => AppL10n(
  l: pt,
  setLanguage: (_) async {},
  child: MaterialApp(
    theme: AppTheme.light,
    darkTheme: AppTheme.dark,
    themeMode: dark ? ThemeMode.dark : ThemeMode.light,
    home: home,
  ),
);

typedef _Scene = Future<void> Function(WidgetTester tester, bool dark);

/// U-48 — the reader's font setting, as the card names it: 1.3× is the
/// "large" step of both platforms' accessibility settings.
const double _largeText = 1.3;

/// One scene, both themes, and a third pass in light at 1.3× (U-48): the
/// same measurements, plus whatever a screen throws when its layout does not
/// hold — a `RenderFlex overflowed` is a test failure, so "every screen
/// holds at 1.3× on 360 dp" is a fact this suite states, not a hope.
/// Semantics are on before the first frame.
void _scene(String name, _Scene body) {
  for (final (dark, scale) in [
    (false, 1.0),
    (true, 1.0),
    (false, _largeText),
  ]) {
    final variant = scale == 1.0 ? (dark ? 'dark' : 'light') : 'light, $scale×';
    testWidgets('$name ($variant)', (tester) async {
      await _usePhone(tester);
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final handle = tester.ensureSemantics();
      await body(tester, dark);
      handle.dispose();
    });
  }
}

// ──────────────────────────────────────────────────────── the gates ──

const _material = Size(48, 48);
const _wcag = Size(44, 44);
const _google = Size(40, 40);

/// Where a smaller floor applies, as rects on the screen right now.
({List<Rect> grids, List<Rect> google}) _exceptions(WidgetTester tester) => (
  grids: [
    for (final e in find.byType(GridView).evaluate())
      tester.getRect(find.byWidget(e.widget)),
  ],
  google: [
    for (final e in find.byType(GoogleSignInButton).evaluate())
      tester.getRect(find.byWidget(e.widget)),
  ],
);

/// The SDK's `MinimumTapTargetGuideline` walk, with the two floors above.
Future<void> _expectTapTargets(WidgetTester tester, String where) async {
  final ex = _exceptions(tester);
  final offenders = <String>[];
  final view = tester.view;
  final viewRect = Offset.zero & view.physicalSize;

  bool atBoundary(Rect child, Rect parent) =>
      !(child.left - parent.left > 0.001 &&
          parent.right - child.right > 0.001 &&
          child.top - parent.top > 0.001 &&
          parent.bottom - child.bottom > 0.001);

  void visit(SemanticsNode node) {
    node.visitChildren((child) {
      visit(child);
      return true;
    });
    if (node.isMergedIntoParent) return;
    final data = node.getSemanticsData();
    if ((!data.hasAction(ui.SemanticsAction.tap) &&
            !data.hasAction(ui.SemanticsAction.longPress)) ||
        data.flagsCollection.isHidden ||
        data.flagsCollection.isLink) {
      return;
    }
    var bounds = node.rect;
    for (SemanticsNode? cur = node; cur != null; cur = cur.parent) {
      final t = cur.transform;
      if (t != null) bounds = MatrixUtils.transformRect(t, bounds);
      if (cur.flagsCollection.hasImplicitScrolling &&
          atBoundary(bounds, cur.rect)) {
        return;
      }
    }
    if (atBoundary(bounds, viewRect)) return;
    final size = bounds.size / view.devicePixelRatio;

    final floor = ex.grids.any((g) => g.contains(bounds.center))
        ? _wcag
        : ex.google.any((g) => g.contains(bounds.center))
        ? _google
        : _material;
    if (size.width < floor.width - 1e-10 ||
        size.height < floor.height - 1e-10) {
      final what = data.label.isNotEmpty ? data.label : data.tooltip;
      offenders.add(
        '"$what" at $bounds is ${size.width.toStringAsFixed(1)}×'
        '${size.height.toStringAsFixed(1)} (floor ${floor.width.toInt()})',
      );
    }
  }

  for (final rv in tester.binding.renderViews) {
    visit(rv.owner!.semanticsOwner!.rootSemanticsNode!);
  }
  expect(
    offenders,
    isEmpty,
    reason:
        '[$where] a target under its floor: a thumb misses it and a '
        'switch-access user cannot reach it. Material 48 dp; the month '
        'grid 44 dp (WCAG 2.5.5, U-28); the Google button 40 dp (U-45).',
  );
}

Future<void> _expectLabelled(WidgetTester tester, String where) async {
  final r = await labeledTapTargetGuideline.evaluate(tester);
  expect(
    r.passed,
    isTrue,
    reason:
        '[$where] a tappable node with no label and no tooltip is what '
        'TalkBack reads as "button":\n${r.reason}',
  );
}

Future<void> _measure(WidgetTester tester, String where) async {
  await _expectTapTargets(tester, where);
  await _expectLabelled(tester, where);
}

// ───────────────────────────────────────────────────────── contrast ──

double _channel(double v) =>
    v <= 0.03928 ? v / 12.92 : _pow((v + 0.055) / 1.055, 2.4);

double _pow(double base, double exp) {
  // WCAG's gamma, without dart:math in a test that otherwise needs none.
  var result = 1.0;
  var term = 1.0;
  final x = exp * _ln(base);
  for (var i = 1; i < 60; i++) {
    term *= x / i;
    result += term;
  }
  return result;
}

double _ln(double x) {
  final y = (x - 1) / (x + 1);
  var sum = 0.0;
  var power = y;
  for (var k = 0; k < 80; k++) {
    sum += power / (2 * k + 1);
    power *= y * y;
  }
  return 2 * sum;
}

double _luminance(Color c) =>
    0.2126 * _channel(c.r) + 0.7152 * _channel(c.g) + 0.0722 * _channel(c.b);

/// WCAG 2.x contrast ratio, 1.0 (none) to 21.0 (black on white).
double contrastRatio(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

String _hex(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

/// Every pair a screen paints TEXT with, named as the code names it.
List<(String, Color, Color)> _textPairs(AppTokens t) => [
  ('text on surface', t.text, t.surface),
  ('text on surfaceAlt', t.text, t.surfaceAlt),
  ('textMuted on surface', t.textMuted, t.surface),
  ('textMuted on surfaceAlt', t.textMuted, t.surfaceAlt),
  ('white on dangerBar', Colors.white, t.dangerBar),
  ('white on dangerBarDeep', Colors.white, t.dangerBarDeep),
  for (final (name, tone) in [
    ('accent', t.accent),
    ('neutral', t.neutral),
    ('success', t.success),
    ('warning', t.warning),
    ('danger', t.danger),
    ('info', t.info),
    for (var i = 0; i < t.slots.length; i++) ('slot $i', t.slots[i].tone),
    ('swapped', t.swapped.tone),
  ]) ...[
    ('$name onSolid on solid', tone.onSolid, tone.solid),
    ('$name onContainer on container', tone.onContainer, tone.container),
  ],
];

/// A tone's `solid` is also an ICON on the page (a check, a warning mark, the
/// Premium star): WCAG 1.4.11's 3:1 against both surfaces.
List<(String, Color, Color)> _iconPairs(AppTokens t) => [
  for (final (name, tone) in [
    ('accent', t.accent),
    ('success', t.success),
    ('warning', t.warning),
    ('danger', t.danger),
    ('info', t.info),
  ]) ...[
    ('$name solid on surface', tone.solid, t.surface),
    ('$name solid on surfaceAlt', tone.solid, t.surfaceAlt),
  ],
];

List<String> _under(List<(String, Color, Color)> pairs, double floor) => [
  for (final (name, fg, bg) in pairs)
    if (contrastRatio(fg, bg) < floor)
      '$name: ${_hex(fg)} on ${_hex(bg)} = '
          '${contrastRatio(fg, bg).toStringAsFixed(2)}',
];

// ─────────────────────────────────────────────────────── fixtures ──

/// A month with the four things a cell can carry: today with a handoff time,
/// a swapped day, a frozen day (overdue, awaiting the reader) and the rest
/// unplanned.
cal.FakeCustodyDataSource _calendarSource() {
  final d = cal.today.day;
  final other = d < 28 ? d + 1 : d - 1;
  return cal.FakeCustodyDataSource(
    members: [cal.ana, cal.bruno],
    days: [
      cal.row(1, cal.dayOfMonth(d), 1, handoffTime: '18:00'),
      cal.row(2, cal.dayOfMonth(other), 2, actual: 1),
    ],
  )..frozenRequests = [frz.swapReq(10, cal.dayOfMonth(2))];
}

Widget _calendar(cal.FakeCustodyDataSource ds, {required bool dark}) => _host(
  CalendarScreen(dataSource: ds, adminMode: AdminMode()),
  dark: dark,
);

void main() {
  setUpAll(_loadRealFonts);

  group('contrast, read from the tokens', () {
    for (final (name, t) in [
      ('light', AppTokens.light),
      ('dark', AppTokens.dark),
    ]) {
      test('$name: every text pair clears AA (4.5:1)', () {
        expect(
          _under(_textPairs(t), 4.5),
          isEmpty,
          reason:
              'a pair a screen writes text with is under WCAG AA — '
              'move the token, never the screen (U-27: colour lives in '
              'tokens.dart alone)',
        );
      });
      test('$name: every tone icon clears 1.4.11 (3:1) on both surfaces', () {
        expect(
          _under(_iconPairs(t), 3.0),
          isEmpty,
          reason: 'a tone used as an icon or mark is under 3:1',
        );
      });
    }

    test(
      'the ratio is WCAG\'s (black on white is 21, white on white is 1)',
      () {
        expect(contrastRatio(Colors.black, Colors.white), closeTo(21, 0.01));
        expect(contrastRatio(Colors.white, Colors.white), closeTo(1, 0.001));
        // The pair U-26 measured by hand for the e-mail CTA: #4f46e5 under
        // white is 6.3:1.
        expect(
          contrastRatio(const Color(0xFF4F46E5), Colors.white),
          closeTo(6.3, 0.05),
        );
      },
    );
  });

  group('every screen, phone width, both themes', () {
    _scene('login', (tester, dark) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        _host(
          LoginScreen(
            onSignIn: (_, _) async {},
            onForgotPassword: () {},
            onSignUp: () {},
            prefs: prefs,
            googleEnabled: Future.value(true),
            onSignInWithGoogle: () async {},
          ),
          dark: dark,
        ),
      );
      await tester.pumpAndSettle();
      await _measure(tester, 'login');
      // The two legal links are the smallest targets on the first screen
      // every user meets: 18 dp tall before U-32.
      for (final key in [K.commonPrivacyPolicy, K.commonTermsOfUse]) {
        final link = find.widgetWithText(TextButton, pt[key]);
        expect(
          tester.getSize(link).height,
          greaterThanOrEqualTo(48),
          reason: '${pt[key]} must be a 48 dp target',
        );
      }
    });

    _scene('register', (tester, dark) async {
      await tester.pumpWidget(
        _host(
          RegisterScreen(
            dataSource: reg.source(),
            onSignIn: (_, _) async {},
            onBackToLogin: () {},
          ),
          dark: dark,
        ),
      );
      await tester.pumpAndSettle();
      await _measure(tester, 'register step 1');
      await reg.goToFamilyStep(tester);
      await _measure(tester, 'register step 2');
      // The consent box names what it accepts, as one sentence.
      expect(
        find.bySemanticsLabel(
          RegExp(
            '^${pt[K.registerConsentAccept]} ${pt[K.commonPrivacyPolicy]} '
            '${pt[K.registerConsentAnd]} ${pt[K.commonTermsOfUse]}\$',
          ),
        ),
        findsOneWidget,
      );
    });

    _scene('calendar, day sheet summary and editor', (tester, dark) async {
      final ds = _calendarSource();
      await tester.pumpWidget(_calendar(ds, dark: dark));
      await tester.pumpAndSettle();
      await _measure(tester, 'calendar');
      await cal.openDay(tester, cal.today.day);
      await _measure(tester, 'day sheet summary');
      await cal.tapSheet(tester, find.byKey(daySheetEditKey));
      await _measure(tester, 'day sheet editor');
    });

    _scene('frozen day sheet', (tester, dark) async {
      await tester.pumpWidget(_calendar(_calendarSource(), dark: dark));
      await tester.pumpAndSettle();
      await cal.openDay(tester, 2);
      await _measure(tester, 'frozen day sheet');
    });

    _scene('calendar actions menu and wizard', (tester, dark) async {
      await tester.pumpWidget(_calendar(_calendarSource(), dark: dark));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(pt[K.calActionsMenu]));
      await tester.pumpAndSettle();
      await _measure(tester, 'calendar actions menu');
      await tester.tap(find.text(pt[K.calWizard]));
      await tester.pumpAndSettle();
      await _measure(tester, 'wizard');
    });

    _scene('selection bar and bulk sheet', (tester, dark) async {
      await tester.pumpWidget(_calendar(_calendarSource(), dark: dark));
      await tester.pumpAndSettle();
      final d = cal.today.day;
      for (final day in [d, d < 28 ? d + 1 : d - 1]) {
        final f = find.text('$day').last;
        await tester.ensureVisible(f);
        await tester.longPress(f);
        await tester.pumpAndSettle();
      }
      await _measure(tester, 'calendar selection bar');
      await tester.tap(find.text(pt.format(K.selectionEdit, [2])));
      await tester.pumpAndSettle();
      await _measure(tester, 'bulk sheet');
    });

    _scene('shell around the calendar', (tester, dark) async {
      final ds = _calendarSource();
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          StatefulShellRoute.indexedStack(
            builder: (_, _, shell) => HomeShell(
              shell: shell,
              adminMode: AdminMode(),
              identity: AccountIdentity(),
              onSignOut: () async {},
              onOpenProfile: () {},
              badge: NotificationBadge(ds),
            ),
            branches: [
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: '/',
                    builder: (_, _) =>
                        CalendarScreen(dataSource: ds, adminMode: AdminMode()),
                  ),
                ],
              ),
              for (final path in ['/family', '/notifications', '/reports'])
                StatefulShellBranch(
                  routes: [
                    GoRoute(
                      path: path,
                      builder: (_, _) => const Scaffold(body: SizedBox()),
                    ),
                  ],
                ),
            ],
          ),
        ],
      );
      await tester.pumpWidget(
        AppL10n(
          l: pt,
          setLanguage: (_) async {},
          child: MaterialApp.router(
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: dark ? ThemeMode.dark : ThemeMode.light,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _measure(tester, 'shell + calendar');
    });

    _scene('family roster and the rename row', (tester, dark) async {
      final ds = fam.source(
        members: const [fam.admin, fam.plain, fam.pending, fam.departed],
        invitations: [fam.pendingInvite(), fam.expiredInvite(id: 11)],
      );
      await tester.pumpWidget(
        _host(
          FamilyScreen(
            dataSource: ds,
            adminMode: AdminMode(),
            sudo: SudoService(ds),
            onOpenProfile: (_, _) {},
            onOpenPlan: () {},
            onOpenAdminMode: () {},
            onOpenDeletion: () {},
            onOpenCustomRoles: () {},
          ),
          dark: dark,
        ),
      );
      await tester.pumpAndSettle();
      await _measure(tester, 'family');
      await tester.tap(find.byTooltip(pt[K.famRename]));
      await tester.pumpAndSettle();
      await _measure(tester, 'family rename row');
      expect(find.byTooltip(pt[K.commonSave]), findsOneWidget);
      expect(find.byTooltip(pt[K.commonCancel]), findsOneWidget);
    });

    _scene('notifications', (tester, dark) async {
      final ds =
          cal.FakeCustodyDataSource(members: [cal.ana, cal.bruno], days: [])
            ..pendingForMe = [
              frz.swapReq(
                10,
                cal.dayOfMonth(cal.today.day),
                message: 'Consulta',
              ),
            ];
      await tester.pumpWidget(
        _host(
          NotificationsScreen(dataSource: ds, badge: NotificationBadge(ds)),
          dark: dark,
        ),
      );
      await tester.pumpAndSettle();
      await _measure(tester, 'notifications');
    });

    // U-43: the scene above has no push transport, so it measures the quiet
    // line after the list. This one measures the other two shapes — the OFF
    // card, then the app-bar icon and the sheet it opens once push is ON.
    _scene('notifications, push off then on', (tester, dark) async {
      final ds =
          cal.FakeCustodyDataSource(members: [cal.ana, cal.bruno], days: []);
      final messaging = psh.FakeMessaging(current: PushPermission.notAsked);
      final push = PushService(ds, messaging: messaging);
      await tester.runAsync(() => push.start(1));
      await tester.pumpWidget(
        _host(
          NotificationsScreen(
              dataSource: ds, badge: NotificationBadge(ds), push: push),
          dark: dark,
        ),
      );
      await tester.pumpAndSettle();
      await _measure(tester, 'notifications, push off');

      messaging.current = PushPermission.granted;
      await tester.runAsync(push.enable);
      await tester.pumpAndSettle();
      await _measure(tester, 'notifications, push on');

      await tester.tap(find.byKey(NotificationsScreen.pushStatusKey));
      await tester.pumpAndSettle();
      await _measure(tester, 'notifications, push sheet');
    });

    _scene('profile', (tester, dark) async {
      final ds = prof.source();
      await tester.pumpWidget(
        _host(
          ProfileScreen(
            dataSource: ds,
            sudo: SudoService(ds),
            deliverExport: (_, _) async {},
          ),
          dark: dark,
        ),
      );
      await tester.pumpAndSettle();
      await _measure(tester, 'profile');
    });

    _scene('the three report tabs', (tester, dark) async {
      await tester.pumpWidget(
        _host(ReportsScreen(dataSource: rep.source()), dark: dark),
      );
      await tester.pumpAndSettle();
      await _measure(tester, 'reports summary');
      await tester.tap(find.text(pt[K.repTabHistory]));
      await tester.pumpAndSettle();
      expect(find.byType(ReportsAuditTab), findsOneWidget);
      await _measure(tester, 'reports audit');
      await tester.tap(find.text(pt[K.repTabPdf]));
      await tester.pumpAndSettle();
      expect(find.byType(ReportsPdfTab), findsOneWidget);
      await _measure(tester, 'reports pdf');
    });

    _scene('plan', (tester, dark) async {
      await tester.pumpWidget(
        _host(
          FamilyPlanScreen(
            dataSource: fam.source(plan: 'free'),
            isStoreChannel: false,
            openExternal: (_) async {},
          ),
          dark: dark,
        ),
      );
      await tester.pumpAndSettle();
      await _measure(tester, 'plan');
    });

    _scene('custom roles', (tester, dark) async {
      await tester.pumpWidget(
        _host(CustomRolesScreen(dataSource: roles.source()), dark: dark),
      );
      await tester.pumpAndSettle();
      await _measure(tester, 'custom roles');
    });
  });

  group('what TalkBack heard on the device (18/09/2026)', () {
    testWidgets('an avatar initial is never a node of its own: roster and '
        'today card', (tester) async {
      await _usePhone(tester);
      final handle = tester.ensureSemantics();
      final ds = fam.source(members: const [fam.admin, fam.plain]);
      await tester.pumpWidget(
        _host(
          FamilyScreen(
            dataSource: ds,
            adminMode: AdminMode(),
            sudo: SudoService(ds),
            onOpenProfile: (_, _) {},
            onOpenPlan: () {},
            onOpenAdminMode: () {},
            onOpenDeletion: () {},
            onOpenCustomRoles: () {},
          ),
          dark: false,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('A'), findsWidgets, reason: 'the initial is painted');
      expect(
        find.bySemanticsLabel(RegExp(r'^[AB]$')),
        findsNothing,
        reason: 'the reader heard "I" before "Irineu…" on every card',
      );

      // The today card draws its own avatar, by hand.
      await tester.pumpWidget(_calendar(_calendarSource(), dark: false));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel(RegExp(r'^A$')), findsNothing);
      handle.dispose();
    });

    testWidgets('the bell badge is a sentence, never a bare number', (
      tester,
    ) async {
      await _usePhone(tester);
      final handle = tester.ensureSemantics();
      final ds =
          cal.FakeCustodyDataSource(members: [cal.ana, cal.bruno], days: [])
            ..pendingForMe = [
              frz.swapReq(10, cal.dayOfMonth(cal.today.day)),
              frz.swapReq(11, cal.dayOfMonth(cal.today.day)),
            ];
      final badge = NotificationBadge(ds);
      await badge.refresh();
      expect(badge.count, 2);
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          StatefulShellRoute.indexedStack(
            builder: (_, _, shell) => HomeShell(
              shell: shell,
              adminMode: AdminMode(),
              identity: AccountIdentity(),
              onSignOut: () async {},
              onOpenProfile: () {},
              badge: badge,
            ),
            branches: [
              for (final path in ['/', '/family', '/notifications', '/reports'])
                StatefulShellBranch(
                  routes: [
                    GoRoute(
                      path: path,
                      builder: (_, _) => const Scaffold(body: SizedBox()),
                    ),
                  ],
                ),
            ],
          ),
        ],
      );
      await tester.pumpWidget(
        AppL10n(
          l: pt,
          setLanguage: (_) async {},
          child: MaterialApp.router(
            theme: AppTheme.light,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('2'), findsOneWidget, reason: 'the badge is painted');
      expect(
        find.bySemanticsLabel(RegExp(r'^2$')),
        findsNothing,
        reason: 'the reader heard "2" and then "Notificações"',
      );
      expect(
        find.bySemanticsLabel(
          RegExp(pt.format(K.navNotificationsManyPending, [2])),
        ),
        findsWidgets,
      );
      handle.dispose();
    });

    testWidgets('an audit diff says which side each value is', (tester) async {
      await _usePhone(tester);
      final handle = tester.ensureSemantics();
      final ds = audit.source(
        logs: [
          audit.activity(
            id: 1,
            oldData: const {'handoff_time': '19:00:00'},
            newData: const {'handoff_time': null},
          ),
          audit.activity(
            id: 2,
            oldData: const {'actual_parent_id': null},
            newData: const {'actual_parent_id': 2},
          ),
        ],
      );
      await audit.pumpAudit(tester, ds);
      // The removed time and the new carer are painted as chips…
      expect(find.text('19:00'), findsOneWidget);
      expect(find.text('Bruno Lima'), findsOneWidget);
      // …and read with their side, never as a bare value. The entry is ONE
      // merged node (what the device read), so the side rides inside it.
      expect(
        find.bySemanticsLabel(RegExp(r'(^|\n)19:00(\n|$)')),
        findsNothing,
        reason:
            'the reader heard "Horário da troca: 19:00" for a time '
            'that had just been removed',
      );
      expect(
        find.bySemanticsLabel(RegExp('${pt[K.auditAriaBefore]}: 19:00')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp('${pt[K.auditAriaNow]}: Bruno Lima')),
        findsOneWidget,
      );
      handle.dispose();
    });
  });

  group('what the day cell says', () {
    testWidgets('an unplanned day says nobody is set; a tap and a long press '
        'are announced', (tester) async {
      await _usePhone(tester);
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_calendar(_calendarSource(), dark: false));
      await tester.pumpAndSettle();

      // Some day that is neither planned nor frozen in the fixture.
      final d = cal.today.day;
      final other = d < 28 ? d + 1 : d - 1;
      final empty = [
        for (var i = 3; i <= 28; i++) i,
      ].firstWhere((i) => i != d && i != other);
      final node = tester.getSemantics(
        find.bySemanticsLabel(
          RegExp('^$empty, ${pt[K.calAriaNoResponsible]}\$'),
        ),
      );
      // The hints are overrides, not the hint string: TalkBack renders them
      // as "double-tap to <tap>, double-tap and hold to <long press>".
      expect(node.hintOverrides?.onTapHint, pt[K.calAriaTapHint]);
      expect(node.hintOverrides?.onLongPressHint, pt[K.calAriaLongPressHint]);
      // A planned day keeps U-29's sentence — the name, never "nobody".
      expect(
        find.bySemanticsLabel(
          RegExp(
            '^$d, ${pt[K.calToday]}, Ana Souza, ${pt[K.editorHandoffTime]} 18:00\$',
          ),
        ),
        findsOneWidget,
      );
      handle.dispose();
    });
  });
}

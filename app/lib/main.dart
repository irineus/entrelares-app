import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
// T-53 stage 4: real paths instead of `/#/…` on the web. The library resolves
// to a non-web STUB off the web, so the call below is safe on every platform.
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'deep_link_urls.dart';
import 'env.dart';
import 'package:entrelares_db_contracts/models/member.dart';
import 'screens/help_screen.dart';
import 'screens/calendar_screen.dart';
import 'screens/custom_roles_screen.dart';
import 'screens/family_admin_mode_screen.dart';
import 'screens/family_delete_screen.dart';
import 'screens/family_plan_screen.dart';
import 'screens/family_screen.dart';
import 'screens/home_shell.dart';
import 'screens/leaving_screen.dart';
import 'screens/login_screen.dart';
import 'routing/app_route_gate.dart';
import 'screens/not_found_screen.dart';
import 'screens/notifications_screen.dart';
import 'screens/oauth_onboarding_screen.dart';
import 'screens/policy_update_screen.dart';
import 'screens/premium_return_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/register_screen.dart';
import 'screens/reports_screen.dart';
import 'screens/reset_password_screen.dart';
import 'screens/update_password_screen.dart';
import 'services/account_identity.dart';
import 'services/activity_tracker.dart';
import 'services/admin_mode.dart';
import 'services/analytics_service.dart';
import 'services/appearance.dart';
import 'services/boot_handoff.dart';
import 'services/connectivity_status.dart';
import 'services/auth_providers.dart';
import 'services/crash_reporter.dart';
import 'services/custody_data_source.dart';
import 'services/handoff_nudge_prefs.dart';
import 'services/install_hint.dart';
import 'services/installed_app.dart';
import 'services/notification_badge.dart';
import 'services/offline_cache.dart';
import 'services/offline_cache_store.dart';
import 'services/onboarding_service.dart';
import 'services/push_service.dart';
import 'services/session_gate.dart';
import 'services/store_billing.dart';
import 'services/sudo_service.dart';
import 'services/support_service.dart';
import 'services/supabase_custody_data_source.dart';
import 'theme/app_theme.dart';
import 'widgets/app_l10n.dart';
import 'widgets/app_width_cap.dart';
import 'widgets/app_splash.dart';
import 'widgets/onboarding.dart';

/// T-18 — the app's one connectivity state, fed by [ConnectivityHttpClient].
///
/// Process-wide rather than a field of the app's State for the same reason
/// `Supabase.initialize` is guarded below: the client is handed to the
/// singleton ONCE, and a boot that re-runs `main()` (the E2E harness switching
/// users) must keep reporting to the instance that client already holds.
final ConnectivityStatus appConnectivity = ConnectivityStatus();

/// Whether [usePathUrlStrategy] already ran in this PAGE. See its call site.
bool _urlStrategyApplied = false;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // T-66: the two error hooks, before anything that can fail. Until this line
  // existed a crash on a real device reached nobody, on either channel — the
  // only defect reports the product ever had came from a tester with a
  // screenshot. Installed FIRST on purpose: a failure inside `Supabase
  // .initialize` or in the language resolution below is exactly the kind that
  // used to be invisible. It is additive (the console still prints, the red
  // screen still paints) and a no-op where the DSN is blank.
  final crash = CrashReporter()..install();
  // T-66 (PR 2): the handled half. `translateSaveError` is the ONE place where
  // a caught exception becomes a sentence for the reader, and it calls this
  // only when it could not explain the error — the case where the product says
  // "check your connection" about something that has nothing to do with the
  // connection. Hung off the choke point rather than wired at ~25 call sites,
  // the way F-09 hangs push off the single writer.
  saveErrorObserver = crash.reportUnexplainedSaveError;
  // T-66 (PR 2): from here on the Dart hooks are the better watcher, so the
  // boot script in `web/index.html` stands down — otherwise the same failure
  // would travel twice, under two shapes. A no-op off the web.
  markAppBooted();
  // The web channel serves REAL paths (`/family`), not `/#/family`. Three
  // things ride on it: F5 restores the screen the reader was on, the URLs
  // match the ones the Blazor app has always published (so a bookmark survives
  // the cutover), and — the one that would have hurt — an invitation link
  // arriving by e-mail carries its token in the PATH, which a hash router
  // never sees. Cloudflare answers every path with index.html
  // (`web/_redirects`), which is what makes this safe to turn on.
  // GUARDED, and the guard is about the second caller, not the first.
  // `main()` runs ONCE in production. The E2E lane runs it TWICE per execution
  // — one boot per user, which is what a two-party workflow test has to do —
  // and on web `usePathUrlStrategy()` asserts on the second call
  // ("Cannot set URL strategy a second time or after the app has been
  // initialized"), killing the boot that switches users. Guarded rather than
  // moved out of `main()`, because the strategy has to be set BEFORE the first
  // frame and this is the only place that qualifies. Production behaviour is
  // identical: there the flag is only ever false once. Same idempotence the
  // `Supabase.initialize` below already has (T-58, 25/08/2026).
  if (!_urlStrategyApplied) {
    usePathUrlStrategy();
    _urlStrategyApplied = true;
  }
  // publishableKey is just the `apikey` header value — it accepts the legacy
  // anon JWT dev still uses (until S-17) as well as the new sb_publishable_…
  // key prod already has, so the S-16 shape ports for free (stage 0).
  // Incoming App Links with auth tokens (recovery) are consumed here too:
  // supabase_flutter parses them and emits `passwordRecovery`.
  // T-18: every exchange with Supabase reports to [appConnectivity] — the one
  // place the app learns whether it can reach the server at all.
  await Supabase.initialize(
    url: Env.current.supabaseUrl,
    publishableKey: Env.current.supabaseKey,
    httpClient: ConnectivityHttpClient(appConnectivity),
  );
  // U-13: the language is resolved BEFORE the first frame — override beats
  // profile beats device, PT-BR fallback. The profile half is null here (no
  // session yet); it joins after the gate via the adoption rule.
  final prefs = await SharedPreferences.getInstance();
  final language = LanguageResolver.resolve(
    prefs.getString(LanguageResolver.storageKey),
    null,
    PlatformDispatcher.instance.locale.toLanguageTag(),
  );
  // U-12: the theme choice is resolved here too, and for the same reason —
  // the app must not paint one theme and blink into the other on the first
  // frame. One source only (the device is one of the three answers, not a
  // layer under them), so there is nothing to adopt later.
  final appearance = Appearance.fromPrefs(prefs);
  runApp(EntrelaresApp(
      prefs: prefs, initialLanguage: language, appearance: appearance));
}

class EntrelaresApp extends StatefulWidget {
  final SharedPreferences prefs;
  final AppLanguage initialLanguage;

  /// U-12 — built by [main] from the same `prefs`, so the first frame already
  /// wears what the reader chose.
  final Appearance appearance;

  const EntrelaresApp(
      {super.key,
      required this.prefs,
      required this.initialLanguage,
      required this.appearance});

  @override
  State<EntrelaresApp> createState() => _EntrelaresAppState();
}

enum _AuthPhase { gate, anon, onboarding, authed }

/// Pings the router into re-running its redirect when the auth phase moves.
class _RouterRefresh extends ChangeNotifier {
  void ping() => notifyListeners();
}

class _EntrelaresAppState extends State<EntrelaresApp>
    with WidgetsBindingObserver {
  late final SessionGate _gate;
  late final CustodyDataSource _dataSource;
  late final NotificationBadge _badge;
  // F-09: constructed always, useful only where there is a transport. On the
  // web it reports `unsupported` and every call is a no-op, so the screens
  // need no `kIsWeb` branch of their own.
  late final PushService _push;

  /// U-28 — who is signed in, published by the screens that load the member
  /// list and read by the account button in every tab's app bar.
  final AccountIdentity _identity = AccountIdentity();
  /// T-37 — one per process; a no-op unless the flavor carries a website id.
  late final AnalyticsService _analytics;
  // S-10: session-scoped like admin mode, and for a stronger reason — an
  // elevation window must never outlive the session that earned it.
  late final SudoService _sudo;
  // T-48: the store rail exists only where there IS a store. On the web target
  // it is null and the Premium section keeps its neutral note — the same state
  // the master switch off produces, so one missing piece never yields a
  // half-drawn offer.
  final StoreBilling? _storeBilling = kIsWeb ? null : PlayStoreBilling();

  // F-14: session-scoped, like the web's scoped AdminModeService — never
  // persisted; leaving the authenticated phase always deactivates it.
  final _adminMode = AdminMode();
  late Localization _l;
  final _refresh = _RouterRefresh();
  _AuthPhase _phase = _AuthPhase.gate;

  /// F-68: the screen "Ajuda e contato" was opened from, for its diagnostics —
  /// the route is sanitized in core before it can leave the device.
  String? _helpFrom;

  void _openHelp({required String from}) {
    _helpFrom = from;
    _router.push('/help');
  }
  SessionExpiredReason _expiredReason = SessionExpiredReason.none;

  /// True while a sign-out the USER asked for is in flight. Without it the
  /// `signedOut` listener cannot tell "you pressed Sair" from "your session
  /// died" — and since the auth event can land AFTER `_signOut` returns,
  /// pressing Sair announced "sua sessão anterior expirou" on the login
  /// screen: a lie, and precisely the sentence that makes someone believe
  /// they were kicked out.
  bool _userSignOut = false;
  StreamSubscription<AuthState>? _authSub;

  // S-04 — inactivity timeout (mirror in InactivityPolicy). The web resets on
  // click/touch/key/scroll; every one of those starts as a pointer-down here.
  // Background time counts, same as the web's timer running in a hidden tab:
  // the resume hook re-checks immediately.
  DateTime _lastInteraction = DateTime.now();
  Timer? _inactivityTimer;

  /// Second belt of the adoption loop guard (the web's sessionStorage flag):
  /// even if the local persist failed, one process never adopts twice.
  static bool _adoptedThisProcess = false;

  SupabaseClient get _client => Supabase.instance.client;

  /// Built LAZILY, and that laziness is T-64's fix: the first thing a GoRouter
  /// does is read the platform's initial route, and the first thing it does
  /// with it is run [_redirect]. While the session gate has not answered there
  /// is no honest answer to give, and every answer the app used to invent
  /// (park on `/splash`, remember the destination, hand it back) moved the
  /// browser's URL away from what the reader asked for. So the router is not
  /// created — [build] shows the splash instead — and by the time it exists the
  /// phase is known and the URL is still the reader's own.
  ///
  /// `initialLocation` therefore only ever applies where the platform hands the
  /// app no URL of its own: an Android cold start, where it is the calendar.
  late final GoRouter _router = GoRouter(
    initialLocation: RouteRules.home,
    refreshListenable: _refresh,
    redirect: _redirect,
    // T-64: a URL this app does not serve says so. Without it go_router's own
    // error page would be the answer, and before the restore was fixed an
    // unknown path did not even get that far — it was swallowed and the reader
    // landed on the calendar.
    errorBuilder: (_, state) => NotFoundScreen(
      location: state.uri.toString(),
      onBackToStart: () => _router.go('/'),
    ),
    routes: [
      GoRoute(
        path: '/splash',
        // U-28: the product's first frame says what the product is — the
        // web's U-10 animated calendar, ported to Flutter over the tokens.
        builder: (_, _) => const AppSplash(),
      ),
      GoRoute(
        path: '/login',
        builder: (_, _) => LoginScreen(
          onSignIn: _signIn,
          onForgotPassword: () => _router.go('/reset-password'),
          onSignUp: () => _router.go('/register'),
          onHelp: () => _openHelp(from: '/login'),
          prefs: widget.prefs,
          expiredReason: _expiredReason,
          // F-57: the button exists only where the project's GoTrue says the
          // provider does — the fail-closed switch is the console config.
          googleEnabled: AuthProviders.googleEnabled(),
          onSignInWithGoogle: _signInWithGoogle,
        ),
      ),
      GoRoute(
        path: '/register',
        builder: (_, state) => RegisterScreen(
          dataSource: _dataSource,
          analytics: _analytics,
          inviteToken: InviteFormRules.inviteTokenFrom(state.uri),
          onSignIn: _signIn,
          onBackToLogin: () => _router.go('/login'),
          googleEnabled: AuthProviders.googleEnabled(),
          // F-57: the invite branch hands its token over, and the stash has
          // to happen HERE — the OAuth redirect leaves the widget tree behind.
          onSignInWithGoogle: ({String? inviteToken}) =>
              _signInWithGoogle(inviteToken: inviteToken),
        ),
      ),
      // F-57: where a deferred (social-login) session becomes a member —
      // outside the shell like /leaving and /policy-update: a profile-less
      // session has no tabs to browse.
      GoRoute(
        path: '/onboarding',
        builder: (_, _) => OauthOnboardingScreen(
          dataSource: _dataSource,
          analytics: _analytics,
          prefs: widget.prefs,
          onSignOut: _signOut,
          onCompleted: () async {
            await _resolveAuthedPhase();
            if (mounted) _router.go('/');
          },
        ),
      ),
      GoRoute(
        path: '/reset-password',
        builder: (_, _) => ResetPasswordScreen(
          onSendReset: (email) => _client.auth.resetPasswordForEmail(email,
              redirectTo: DeepLinkUrls.updatePasswordFor(_l.current)),
          onBackToLogin: () => _router.go('/login'),
        ),
      ),
      // F-68: "Ajuda e contato" — public AND signed in (RouteRules.help), so it
      // sits outside the shell like the auth screens: it has to render with no
      // family and no tabs.
      GoRoute(
        path: '/help',
        builder: (context, _) {
          final signedIn = _phase == _AuthPhase.authed;
          return HelpScreen(
            accountEmail: signedIn ? _client.auth.currentUser?.email : null,
            diagnostics: currentSupportDiagnostics(
              appVersion: Env.appVersion,
              language: _l.current.code,
              route: _helpFrom ?? (signedIn ? '/' : '/login'),
            ),
            onSend: SupportService(_client).send,
            onClose: () {
              if (_router.canPop()) {
                _router.pop();
              } else {
                _router.go(signedIn ? '/family/profile' : '/login');
              }
            },
          );
        },
      ),
      GoRoute(
        path: '/update-password',
        builder: (_, _) => UpdatePasswordScreen(
          hasSession: _client.auth.currentSession != null,
          onUpdatePassword: (newPassword) async {
            await _client.auth
                .updateUser(UserAttributes(password: newPassword));
          },
          onDone: () => _router.go('/'),
        ),
      ),
      // S-11: outside the shell on purpose — a member on their way out has no
      // tabs to browse.
      GoRoute(
        path: '/leaving',
        builder: (_, _) => LeavingScreen(
          dataSource: _dataSource,
          sudo: _sudo,
          onSignOut: _signOut,
          onReturned: () {
            _isLeaving = false;
            _router.go('/');
          },
        ),
      ),
      // S-15: also outside the shell — past the notice window this is the only
      // screen the app offers.
      // T-39: where the hosted checkout sends the payer back. It is the SAME
      // path the web serves (`appUrl/premium/retorno`, built server-side by
      // billing-checkout), so on a device with the domain verified the App
      // Link opens the app here and anywhere else it stays on the web.
      GoRoute(
        path: '/premium/retorno',
        builder: (_, _) => PremiumReturnScreen(
          dataSource: _dataSource,
          analytics: _analytics,
          // U-35: back to where the plan state lives now.
          onBackToFamily: () => _router.go('/family/plan'),
        ),
      ),
      GoRoute(
        path: '/policy-update',
        builder: (_, _) => PolicyUpdateScreen(
          dataSource: _dataSource,
          onSignOut: _signOut,
          onAccepted: () {
            _consentState = ConsentGateState.upToDate;
            _router.go('/');
          },
        ),
      ),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => HomeShell(
            shell: shell,
            adminMode: _adminMode,
            badge: _badge,
            identity: _identity,
            // U-28: the shell owns sign-out now, so it is reachable from all
            // four tabs — it used to be a CalendarScreen parameter only.
            onSignOut: _signOut,
            onOpenProfile: () => _router.go('/family/profile'),
            onOpenHelp: () => _openHelp(
                from: _router.routeInformationProvider.value.uri.path),
            deletionBanner: _deletionBanner,
            appHandoff: _appHandoff,
            installHint: _installHint,
            connectivity: appConnectivity,
            tourKeys: _tourKeys),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/',
              builder: (_, _) => CalendarScreen(
                  dataSource: _dataSource,
                  connectivity: appConnectivity,
                  offlineCache: _offlineCache,
                  adminMode: _adminMode,
                  analytics: _analytics,
                  onboarding: _onboarding,
                  tourKeys: _tourKeys,
                  onOpenFamily: () => _router.go('/family'),
                  onOpenNotifications: () => _router.go('/notifications'),
                  onOpenPlan: () => _router.go('/family/plan'),
                  handoffNudgePrefs: _handoffNudgePrefs),
            ),
          ]),
          // U-35: the branch's navigator reports to the roster's observer, so
          // a sub-page popping back reloads what its row summarises.
          StatefulShellBranch(observers: [familyRouteObserver], routes: [
            GoRoute(
              path: '/family',
              builder: (_, _) => FamilyScreen(
                dataSource: _dataSource,
                adminMode: _adminMode,
                analytics: _analytics,
                sudo: _sudo,
                onFamilyDeleted: _signOut,
                onOpenCustomRoles: () => _router.go('/family/custom-roles'),
                // F-16: own card opens my profile; another member's opens
                // theirs, and the screen itself re-checks that I may look.
                onOpenProfile: (member, isOwn) => _router.go(
                    isOwn ? '/family/profile' : '/family/profile/${member.id}'),
                // U-35: the three sub-pages behind the roster's rows.
                onOpenPlan: () => _router.go('/family/plan'),
                onOpenAdminMode: () => _router.go('/family/admin-mode'),
                onOpenDeletion: () => _router.go('/family/delete'),
              ),
              routes: [
                // Nested so the bottom bar stays put — the web navigates away
                // to `/custom-roles` and `/profile` because it has no
                // persistent tab shell.
                GoRoute(
                  path: 'custom-roles',
                  builder: (_, _) => CustomRolesScreen(
                    dataSource: _dataSource,
                    analytics: _analytics,
                    // U-35: every gate CTA lands on the plan page.
                    onSeePremium: () => _router.go('/family/plan'),
                  ),
                ),
                // U-35: what used to be three sections of the Família scroll.
                GoRoute(
                  path: 'plan',
                  builder: (_, _) => FamilyPlanScreen(
                    dataSource: _dataSource,
                    analytics: _analytics,
                    storeBilling: _storeBilling,
                  ),
                ),
                GoRoute(
                  path: 'admin-mode',
                  builder: (_, _) => FamilyAdminModeScreen(
                    dataSource: _dataSource,
                    adminMode: _adminMode,
                    analytics: _analytics,
                    onOpenPlan: () => _router.go('/family/plan'),
                  ),
                ),
                GoRoute(
                  path: 'delete',
                  builder: (_, _) => FamilyDeleteScreen(
                    dataSource: _dataSource,
                    sudo: _sudo,
                    // The countdown lives on the roster: back to it, which
                    // reloads on the pop (familyRouteObserver).
                    onRequested: () => _router.go('/family'),
                  ),
                ),
                GoRoute(
                  path: 'profile',
                  builder: (_, _) => ProfileScreen(
                    dataSource: _dataSource,
                    sudo: _sudo,
                    onOpenFamily: () => _router.go('/family'),
                    onReopenOnboarding: ({required bool replayTour}) async {
                      // U-29: "Ver o tour de novo" asks for the TOUR — it no
                      // longer reopens the checklist banner as a side effect,
                      // which is what left an unrelated banner on the
                      // calendar after a replay.
                      if (!replayTour) await _onboarding.reopenChecklist();
                      _onboarding.tourReplayRequested = replayTour;
                      if (mounted) _router.go('/');
                    },
                    onLeaving: () {
                      _isLeaving = true;
                      _router.go('/leaving');
                    },
                    appearance: widget.appearance,
                    onOpenHelp: () => _openHelp(from: '/family/profile'),
                  ),
                  routes: [
                    GoRoute(
                      path: ':id',
                      builder: (_, state) => ProfileScreen(
                        dataSource: _dataSource,
                        sudo: _sudo,
                        profileId:
                            int.tryParse(state.pathParameters['id'] ?? ''),
                        // `/profile/<my own id>` is the same page as
                        // `/profile`, and a setting that appears under one
                        // address and not the other is the reader's problem,
                        // not the router's. The card is `_isOwn`-gated inside.
                        appearance: widget.appearance,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/notifications',
              builder: (_, state) => NotificationsScreen(
                  dataSource: _dataSource,
                  badge: _badge,
                  connectivity: appConnectivity,
                  push: _push,
                  installFacts: _browserFacts,
                  analytics: _analytics,
                  landing: switch (state.uri.queryParameters['tab']) {
                    'incoming' => NotificationLanding.incoming,
                    'history' => NotificationLanding.history,
                    _ => null,
                  },
                  landingNonce: state.uri.queryParameters['n']),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/reports',
              builder: (_, _) => ReportsScreen(
                  dataSource: _dataSource,
                  onOpenCalendar: () => _router.go('/')),
            ),
          ]),
        ],
      ),
    ],
  );

  /// The routing decision, out of this State so a test can drive it (T-64).
  late final AppRouteGate _routeGate = AppRouteGate(
    phase: () => _routePhase,
    isLeaving: () => _isLeaving,
    consentState: () => _consentState,
  );

  /// Whether [_router] has been built — which only happens once the gate has
  /// answered. Guards the listener it owns, so `dispose` on a session that
  /// never got past the splash does not construct a router just to tear it
  /// down.
  bool _routerLive = false;

  /// S-11: this member asked to leave, so the app is closed to them until they
  /// cancel or sign out (mirror of `MainLayout.EnforceLeaving`).
  bool _isLeaving = false;

  /// S-15/B-4: whether the re-consent gate warns, blocks, or says nothing.
  ConsentGateState _consentState = ConsentGateState.upToDate;

  /// S-11: what the shell's persistent deletion banner shows, or null.
  ///
  /// A notifier, not a field read by the shell route's `builder`: go_router
  /// caches the pages a builder produced and re-runs it only on a navigation
  /// or an inherited-widget change, so a `setState` here never reached the
  /// shell. Measured on a device on 13/09/2026 (T-65): the offer was in this
  /// state, correct, and painted only when the reader switched tabs. The shell
  /// listens to the notifier instead, and a late answer paints on its own.
  final _deletionBanner = ValueNotifier<FamilyDeletionBanner?>(null);

  /// T-65: the web→app offer, or null — which is the answer on every native
  /// build and on every browser that did not confirm the app is on this device.
  /// A notifier for the reason [_deletionBanner] gives.
  final _appHandoff = ValueNotifier<AppHandoffBanner?>(null);

  /// Where a dismissal of that offer is remembered. Under the `app.` prefix
  /// the whole client uses, and read through `prefs` rather than
  /// `localStorage` directly so the web and the VM tell the same story in a
  /// test.
  static const String _handoffDismissedKey = 'app.handoff.dismissed';

  /// U-51: the iPhone install hint, or null — the answer on every native
  /// build, on Android, on desktop, in every browser but Safari, and in an app
  /// already on the Home Screen. A notifier for the reason [_deletionBanner]
  /// gives.
  final _installHint = ValueNotifier<InstallHintBanner?>(null);

  /// U-55: the "Definir horário" strip's dismissal, per family, per device.
  late final _handoffNudgePrefs = SharedHandoffNudgePrefs(widget.prefs);

  /// What the browser says about itself (U-51's seam), read ONCE: the shell
  /// strip and the Notificações step (U-54) must agree on the same answer.
  /// Null in the native app.
  late final BrowserInstallFacts? _browserFacts =
      kIsWeb ? readBrowserInstallFacts() : null;

  /// T-78: "this member used the app today, on this channel", once per day.
  /// Touched on entering the authenticated phase, on every resume and on every
  /// pointer-down while authenticated — the tracker turns all but the day's
  /// first success into a string comparison. The installed/tab split is the
  /// same browser fact the U-51 hint reads.
  late final ActivityTracker _activity = ActivityTracker(
      _dataSource.touchActivity,
      channel: ActivityRules.channel(
          isWeb: kIsWeb,
          standalone: _browserFacts != null &&
              InstallHintRules.isStandalone(_browserFacts)));

  void _touchActivity() {
    if (_phase == _AuthPhase.authed) unawaited(_activity.touch());
  }

  /// Where a dismissal of the hint is remembered — per BROWSER, like the
  /// handoff's: it is that Safari that keeps the app as a tab.
  static const String _installHintDismissedKey = 'app.installHint.dismissed';

  /// U-54: how many times, and when last. The U-51 bool above is only read,
  /// as one undated dismissal — never written again.
  static const String _installHintDismissCountKey =
      'app.installHint.dismissCount';
  static const String _installHintLastDismissedKey =
      'app.installHint.lastDismissedAt';

  /// U-23 — the checklist/tour state and the shared registry of tour targets
  /// (they live in two different subtrees: the tab bar and the calendar).
  late final OnboardingService _onboarding;
  final _tourKeys = TourKeys();

  /// T-18 — the device's copy of the current month, Android only (see
  /// [OfflineCache]). Bound to whoever is signed in at the moment of each
  /// call, and wiped on every exit from the authenticated phase.
  late final OfflineCache _offlineCache = OfflineCache(
      createOfflineCacheStore(),
      userId: () => _client.auth.currentUser?.id,
      enabled: !kIsWeb);

  String? _redirect(BuildContext context, GoRouterState state) =>
      _routeGate.redirect(state.matchedLocation);

  AuthPhase get _routePhase => switch (_phase) {
        _AuthPhase.gate => AuthPhase.gate,
        _AuthPhase.anon => AuthPhase.anon,
        _AuthPhase.onboarding => AuthPhase.onboarding,
        _AuthPhase.authed => AuthPhase.authed,
      };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _gate = SessionGate(_client.auth);
    _analytics = AnalyticsService(language: widget.initialLanguage.code);
    _dataSource = SupabaseCustodyDataSource(_client,
        environmentPrefix:
            environmentTitlePrefix(isProduction: Env.current.isProduction),
        analytics: _analytics);
    _badge = NotificationBadge(_dataSource);
    _push = PushService(_dataSource);
    // F-09: brings the transport up, and never fatally. A build whose flavor
    // carries no Firebase config — or a device without the services it needs —
    // simply has no push; the product's whole job works without it, so this
    // must not be allowed to take the boot with it. On the web the transport is
    // a stub that answers "no" to everything, so there is no `kIsWeb` branch
    // here or in any screen.
    unawaited(_push.initialize());
    // A tapped notification lands on the list it came from. Deliberately not
    // the day itself: the payload names an event, and the swap it refers to
    // may already have been answered from the other phone — Notificações is
    // the one screen that is truthful whatever happened in between.
    _push.onOpen = (data) {
      if (_phase != _AuthPhase.authed) return;
      // The tab is chosen from the notice's TYPE (PushRouting): a receipt lands
      // on Todas, which always holds the row that was tapped, while a
      // request awaiting this person lands on "Para você". The notification id
      // rides along so a SECOND tap re-applies the tab — the screen's State
      // survives inside the shell branch.
      // F-52: `kind` rides in the payload so a courtesy aviso lands on
      // "Todas" and a request lands on "Para você".
      final landing =
          PushRouting.landingFor(data['type'], kind: data['kind']);
      final query = {
        'tab': landing == NotificationLanding.incoming ? 'incoming' : 'history',
        if ((data['notificationId'] ?? '').isNotEmpty)
          'n': data['notificationId']!,
      };
      _router.go(Uri(path: '/notifications', queryParameters: query).toString());
    };
    _sudo = SudoService(_dataSource);
    _onboarding = OnboardingService(_dataSource, push: _push);
    _l = Localization(widget.initialLanguage);
    appConnectivity.addListener(_onConnectivityChanged);
    // U-12: the picker sits inside a route go_router caches, so the root only
    // learns of a change by listening — the same reason the connectivity strip
    // is a listenable.
    widget.appearance.addListener(_onAppearanceChanged);
    _openGate();
    _authSub = _client.auth.onAuthStateChange.listen((state) {
      switch (state.event) {
        // Pilot lesson 1.1 (second half): when the session dies MID-USE,
        // return to login instead of letting every call fail 42501.
        case AuthChangeEvent.signedOut:
          _expiredReason = reasonForSignedOut(
            userInitiated: _userSignOut,
            current: _expiredReason,
            wasAuthed: _phase == _AuthPhase.authed,
          );
          _userSignOut = false;
          _setPhase(_AuthPhase.anon);
        // The recovery deep link's session was just created from the e-mail
        // tokens — land on the new-password form wherever the app was.
        case AuthChangeEvent.passwordRecovery:
          _setPhase(_AuthPhase.authed);
          _router.go('/update-password');
        // A session that appeared while we sat anonymous (deep link paths);
        // the explicit flows (_signIn/_openGate) set their phase themselves.
        case AuthChangeEvent.signedIn:
          if (_phase == _AuthPhase.anon) {
            _expiredReason = SessionExpiredReason.none;
            // F-57: the OAuth return lands here (deep link / web redirect) —
            // and an OAuth session may have NO profile yet, so the phase is
            // resolved from the profile, never assumed.
            unawaited(_resolveAuthedPhase());
          }
        default:
          break;
      }
    },
        // T-18: gotrue reports a refresh that could not reach the server as an
        // ERROR on this stream, and keeps the session. With no handler it
        // becomes an uncaught error — a crash report per failed refresh for a
        // reader who merely has no signal. The refusal that matters arrives as
        // `signedOut` above; a transport failure is the strip's to show.
        onError: (Object _) {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    appConnectivity.removeListener(_onConnectivityChanged);
    widget.appearance.removeListener(_onAppearanceChanged);
    _authSub?.cancel();
    if (_routerLive) {
      _router.routeInformationProvider.removeListener(_trackPageView);
      _router.routeInformationProvider.removeListener(_refreshDocumentTitle);
    }
    _inactivityTimer?.cancel();
    _adminMode.dispose();
    _storeBilling?.dispose();
    _onboarding.dispose();
    _sudo.dispose();
    _badge.dispose();
    _push.dispose();
    _refresh.dispose();
    _deletionBanner.dispose();
    _appHandoff.dispose();
    _installHint.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkInactivity();
      _touchActivity();
    }
  }

  void _trackPageView() {
    final location = _router.routeInformationProvider.value.uri.toString();
    // The splash is a gate, not a screen someone visited.
    if (location.startsWith('/splash')) return;
    _analytics.trackPageView(location);
  }

  void _setPhase(_AuthPhase phase) {
    if (!mounted) return;
    // setState, not a bare assignment: leaving the gate phase swaps the splash
    // for the router in [build], and that swap is what CREATES the router —
    // reading the browser's URL for the first time, with the answer already in
    // hand (T-64).
    setState(() => _phase = phase);
    // Mirror of the web's logout path: leaving the authenticated phase for
    // ANY reason (sign-out, inactivity, dead session) drops admin mode — and
    // the S-10 elevation window with it.
    if (phase != _AuthPhase.authed) {
      _adminMode.deactivate();
      _sudo.reset();
      // T-18: the age the strip names, and the device's copy of the plan,
      // belong to what THIS person saw.
      appConnectivity.forgetData();
      unawaited(_offlineCache.clear());
      _profileGatesDeferred = false;
      _activity.reset();
    }
    if (phase == _AuthPhase.authed) {
      _lastInteraction = DateTime.now();
      _inactivityTimer ??= Timer.periodic(
          InactivityPolicy.pollInterval, (_) => _checkInactivity());
      // The bell badge lives with the authenticated phase (count + its
      // workflow Realtime trigger).
      _badge.start();
      // F-09: reads the REAL permission and repairs a registration for someone
      // who already said yes. Never prompts — the dialog is spent by a gesture
      // on the Notificações screen, not by opening the app.
      unawaited(_startPush());
      // T-65: asks the BROWSER whether this reader already has the app. Here
      // rather than at boot because the banner lives in the authenticated
      // shell, and because a question nobody will act on is not worth asking.
      unawaited(_resolveAppHandoff());
      // U-51: asks the browser whether this is Safari on an iPhone still in
      // a tab. Same place, same reason: the strip lives in the authenticated
      // shell, and a stranger evaluating the app is not asked to install it.
      _resolveInstallHint();
      // T-78: the day this member used the app, on this channel.
      _touchActivity();
    } else {
      _badge.stop();
      unawaited(_push.stop());
      _inactivityTimer?.cancel();
      _inactivityTimer = null;
    }
    if (phase != _AuthPhase.gate) _ensureRouterListeners();
    _refresh.ping();
  }

  /// T-37: a pageview per navigation, the app's answer to the web's
  /// `OnLocationChanged`. The URL is sanitized by the pure mirror, so no invite
  /// token or profile id can travel with it.
  ///
  /// Attached here rather than in `initState` because touching [_router] is
  /// what builds it, and building it before the gate has answered is the whole
  /// defect this item removed.
  void _ensureRouterListeners() {
    if (_routerLive) return;
    _routerLive = true;
    _router.routeInformationProvider.addListener(_trackPageView);
    _router.routeInformationProvider.addListener(_refreshDocumentTitle);
  }

  /// U-48: the browser's tab and history name the SCREEN, not just the
  /// product. `MaterialApp.title` is read at build, so a navigation rebuilds
  /// the root; go_router keeps the pages it built (T-65), so the cost is the
  /// `Title` widget alone.
  void _refreshDocumentTitle() {
    if (mounted) setState(() {});
  }

  /// "Calendário · Entrelares" for the location on screen, the brand alone
  /// while the gate decides — reading [_router] before that would BUILD it,
  /// which is the T-64 defect, so the guard is [_routerLive], never the phase.
  String get _documentTitle {
    final prefix = environmentTitlePrefix(isProduction: Env.current.isProduction);
    if (!_routerLive) return '$prefix${DocumentTitle.brand}';
    return DocumentTitle.compose(
      _router.routeInformationProvider.value.uri.toString(),
      _l,
      environmentPrefix: prefix,
    );
  }

  /// T-65 — whether to offer the crossing into the installed app.
  ///
  /// Asked once per authenticated session and never again after a dismissal:
  /// the offer is a convenience, and a convenience that keeps coming back is
  /// an interruption. The dismissal is per BROWSER (`prefs` is `localStorage`
  /// on this channel), which is the right grain — it is that browser that has
  /// the app beside it.
  ///
  /// Every failure inside [isStoreAppInstalled] answers "no", so the whole
  /// path is silent by construction: nothing here may cost the reader a
  /// screen.
  ///
  /// The answer lands in a notifier the shell listens to, not in a `setState`:
  /// the shell is built by a go_router route builder, which does not run again
  /// for a rebuild of this widget (see [_deletionBanner]).
  Future<void> _resolveAppHandoff() async {
    if (!kIsWeb || _appHandoff.value != null) return;
    if (widget.prefs.getBool(_handoffDismissedKey) ?? false) return;
    if (!await isStoreAppInstalled(Env.current.androidPackage)) return;
    if (!mounted || _phase != _AuthPhase.authed) return;
    _appHandoff.value = AppHandoffBanner(
      onOpen: _openInApp,
      onDismiss: _dismissAppHandoff,
    );
  }

  /// T-65 — hands the reader's CURRENT location to the app.
  ///
  /// `_self` is not decoration: without a window name the web plugin opens a
  /// new tab to fire the intent and leaves a blank one behind — the same
  /// stray-tab artefact the original bug report was misread as.
  void _openInApp() {
    final uri = ChannelHandoffRules.handoffUri(
      androidPackage: Env.current.androidPackage,
      location: _router.routeInformationProvider.value.uri.toString(),
    );
    unawaited(launchUrl(uri, webOnlyWindowName: '_self'));
  }

  void _dismissAppHandoff() {
    _appHandoff.value = null;
    unawaited(widget.prefs.setBool(_handoffDismissedKey, true));
  }

  /// U-51 — whether to invite the reader to put the app on the Home Screen.
  ///
  /// Synchronous, unlike the handoff: the four facts are properties the
  /// browser already holds. It still lands in a notifier and not in a
  /// `setState`, for the go_router reason [_deletionBanner] gives — and so
  /// that the T-65 widget test's order (shell first, answer second) stays the
  /// order this code can be exercised in.
  ///
  /// Once per authenticated session. U-54: a dismissal snoozes it for
  /// [InstallHintRules.snooze], and the third one is final
  /// ([InstallHintDismissals]). The impression is counted so T-75 can read how
  /// many iPhone readers were shown the door before it measures who walked
  /// through it.
  void _resolveInstallHint() {
    if (!kIsWeb || _installHint.value != null) return;
    final facts = _browserFacts;
    if (facts == null) return;
    if (!InstallHintRules.shouldHint(facts,
        dismissals: _installHintDismissals(), now: DateTime.now())) {
      return;
    }
    _installHint.value = InstallHintBanner(
      onOpen: () => unawaited(_analytics.trackEvent('install-hint-open')),
      onDismiss: _dismissInstallHint,
    );
    unawaited(_analytics.trackEvent('install-hint-view'));
  }

  /// The dismissals this browser remembers. U-51 wrote only a bool; it reads
  /// here as one dismissal with no date, which snoozes nothing.
  InstallHintDismissals _installHintDismissals() {
    final prefs = widget.prefs;
    final count = prefs.getInt(_installHintDismissCountKey) ??
        ((prefs.getBool(_installHintDismissedKey) ?? false) ? 1 : 0);
    final lastMs = prefs.getInt(_installHintLastDismissedKey);
    return InstallHintDismissals(
      count: count,
      last: lastMs == null ? null : DateTime.fromMillisecondsSinceEpoch(lastMs),
    );
  }

  void _dismissInstallHint() {
    _installHint.value = null;
    final next = _installHintDismissals().next(DateTime.now());
    unawaited(widget.prefs.setInt(_installHintDismissCountKey, next.count));
    unawaited(widget.prefs.setInt(
        _installHintLastDismissedKey, next.last!.millisecondsSinceEpoch));
    unawaited(_analytics.trackEvent('install-hint-dismiss'));
  }

  /// F-09 — needs the profile id, which the phase transition does not carry.
  /// A failure here is silent by design: push is an extra channel, and the
  /// session must not depend on it.
  Future<void> _startPush() async {
    try {
      final me = await _dataSource.fetchOwnProfile();
      if (me == null || _phase != _AuthPhase.authed) return;
      await _push.start(me.id);
    } catch (_) {/* the notification and its e-mail still arrive */}
  }

  void _checkInactivity() {
    if (_phase != _AuthPhase.authed) return;
    if (!InactivityPolicy.expired(_lastInteraction, DateTime.now())) return;
    _expiredReason = SessionExpiredReason.inactivity;
    _setPhase(_AuthPhase.anon);
    // Local-first is fine: navigation never waits on the network (lesson 1.3).
    unawaited(_gate.signOutSafely());
  }

  Future<void> _openGate() async {
    // Lesson 1.1: a restored session proves nothing — validate with
    // refreshSession() BEFORE routing (Blazor got this for free via
    // forceLoad; Flutter has no equivalent).
    final hadSession = _client.auth.currentSession != null;
    // T-18: a refresh that cannot reach the server keeps the session and opens
    // the app offline; only a refusal lands on login.
    final verdict = await _gate.validateRestoredSession(
        networkLost: appConnectivity.nextLoss());
    if (!mounted) return;
    final alive = verdict != RestoredSession.signedOut;
    _expiredReason = !alive && hadSession
        ? SessionExpiredReason.restored
        : SessionExpiredReason.none;
    if (verdict == RestoredSession.offline) {
      // T-18: the profile read would only spend postgrest's retries (~7 s)
      // under the splash to fail anyway. Open on what the device has; the
      // gates the profile decides settle at the first server response.
      _setPhase(_AuthPhase.authed);
      _deferProfileGates();
    } else if (alive) {
      // The splash stays up while the profile decides the phase — the shell
      // must never flash for a session that turns out to be onboarding.
      await _resolveAuthedPhase();
    } else {
      _setPhase(_AuthPhase.anon);
    }
  }

  Future<void> _signIn(String email, String password) async {
    await _client.auth.signInWithPassword(email: email, password: password);
    _expiredReason = SessionExpiredReason.none;
    await _resolveAuthedPhase();
  }

  /// F-57 — the Google door. On Android the redirect returns through the
  /// per-flavor custom scheme (see [DeepLinkUrls.oauthCallback]); on web the
  /// page itself round-trips to its own origin and `Supabase.initialize`
  /// consumes the code on the way back in. Errors are the button's to show.
  Future<void> _signInWithGoogle({String? inviteToken}) async {
    final token = inviteToken?.trim() ?? '';
    if (token.isNotEmpty) {
      // The stash IS the state: the OAuth round-trip keeps no widget alive,
      // so the onboarding screen re-reads the token from prefs.
      await widget.prefs
          .setString(OauthOnboardingScreen.pendingInviteTokenKey, token);
    }
    await _client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: kIsWeb ? Uri.base.origin : DeepLinkUrls.oauthCallback,
    );
  }

  /// F-57 — a validated session is AUTHED only if it has a profile; a
  /// deferred OAuth sign-up has none yet and lives on the onboarding screen.
  /// A transient read failure is never a verdict: the session stays authed
  /// and every screen shows its own error state, exactly as before.
  bool _resolvingPhase = false;

  Future<void> _resolveAuthedPhase() async {
    if (_resolvingPhase) return;
    _resolvingPhase = true;
    try {
      Member? me;
      var profileKnown = true;
      try {
        me = await _dataSource.fetchOwnProfile();
      } catch (_) {
        profileKnown = false;
      }
      if (!mounted) return;
      if (profileKnown && me == null) {
        _setPhase(_AuthPhase.onboarding);
        return;
      }
      _setPhase(_AuthPhase.authed);
      if (me != null) {
        await _applyProfileGates(me);
      } else {
        _deferProfileGates();
      }
    } finally {
      _resolvingPhase = false;
    }
  }

  /// T-18 — the profile could not be read when the session opened, so the
  /// S-11/S-15 gates, the onboarding verdict and push registration were never
  /// decided. Before T-18 that was a rare transient; now that a restored
  /// session opens OFFLINE on purpose it is the normal path at the school door,
  /// and leaving it undecided would skip the S-15 consent gate for the whole
  /// process. The first server response settles it.
  bool _profileGatesDeferred = false;

  void _deferProfileGates() {
    _profileGatesDeferred = true;
    // The server may already have answered between the failed read and this
    // line — then no transition is coming to wake the listener.
    _onConnectivityChanged();
  }

  /// U-12 — a new theme repaints the whole app, which is exactly what the
  /// choice asks for: `MaterialApp.themeMode` is read in [build].
  void _onAppearanceChanged() {
    if (mounted) setState(() {});
  }

  void _onConnectivityChanged() {
    if (appConnectivity.offline || !_profileGatesDeferred) return;
    if (_phase != _AuthPhase.authed) return;
    _profileGatesDeferred = false;
    unawaited(_settleDeferredProfileGates());
  }

  Future<void> _settleDeferredProfileGates() async {
    final Member? me;
    try {
      me = await _dataSource.fetchOwnProfile();
    } catch (_) {
      // Still not a verdict: wait for the next time the server answers.
      _profileGatesDeferred = true;
      return;
    }
    if (!mounted || _phase != _AuthPhase.authed) return;
    if (me == null) {
      // A deferred OAuth sign-up that opened offline — onboarding after all.
      _setPhase(_AuthPhase.onboarding);
      return;
    }
    unawaited(_startPush());
    await _applyProfileGates(me);
  }

  Future<void> _signOut() async {
    // Set BEFORE the call: the auth event may arrive before or after the
    // await returns, and only this flag makes that order irrelevant.
    _userSignOut = true;
    await _gate.signOutSafely();
    _identity.clear();
    // Lesson 1.3: navigate ALWAYS (the auth listener also fires on success).
    _expiredReason = SessionExpiredReason.none;
    _setPhase(_AuthPhase.anon);
  }

  /// U-13 — the authenticated half of the language rule, in the web's
  /// MainLayout order: adoption first (it "reboots" the tree), detection
  /// recording second and best-effort — a failed write costs one e-mail in
  /// the old language and retries next boot. The profile arrives from
  /// [_resolveAuthedPhase], which already decided this session HAS one —
  /// the old fetch-and-swallow here is what silently let a profile-less
  /// session into the shell before F-57.
  Future<void> _applyProfileGates(Member me) async {
    // S-11/S-15 — the two account gates, decided once per authenticated boot
    // exactly like the web's MainLayout does after its first render.
    _isLeaving = me.leftAt != null;
    _consentState = _isLeaving
        ? ConsentGateState.upToDate
        : PolicyVersions.evaluate(me.consentPolicyVersion, DateTime.now());
    _refresh.ping();
    unawaited(_refreshDeletionBanner(me));

    final stored = widget.prefs.getString(LanguageResolver.storageKey);
    if (!_adoptedThisProcess &&
        Localization.shouldAdopt(me.language, _l.current, stored)) {
      _adoptedThisProcess = true;
      final adopted = AppLanguage.tryParse(me.language)!;
      // First belt: make the NEXT boot resolve to the adopted language —
      // without persisting, a profile saying "en" on a pt-BR device would be
      // adopted, rebuilt, re-detected and adopted again, forever.
      try {
        await widget.prefs
            .setString(LanguageResolver.storageKey, adopted.code);
      } catch (_) {
        // covered by the process guard above
      }
      if (mounted) setState(() => _l = Localization(adopted));
      return;
    }

    if (me.leftAt == null &&
        Localization.shouldRecordDetected(me.languageDetected, _l.current)) {
      try {
        await _dataSource.updateDetectedLanguage(me.id, _l.current.code);
      } catch (_) {
        // best-effort by design
      }
    }
  }

  /// S-11 — the banner that has to reach every tab. Best-effort: a family with
  /// no pending request is the overwhelmingly common case, and a failed read
  /// must never keep the app from opening.
  Future<void> _refreshDeletionBanner(Member me) async {
    try {
      final pending = await _dataSource.fetchPendingFamilyDeletion();
      if (!mounted) return;
      if (pending == null || _isLeaving) {
        _deletionBanner.value = null;
        return;
      }
      final members = await _dataSource.fetchMembers();
      if (!mounted) return;
      _deletionBanner.value = FamilyDeletionBanner(
        scheduledFor: pending.request.scheduledFor,
        allAgreed: FamilyLifecycleRules.allAgreed(
          members: members
              .map((m) => LifecycleMember(
                  id: m.id,
                  isActiveMember: m.isActiveMember,
                  isAdmin: m.isAdmin))
              .toList(),
          requesterProfileId: pending.request.requestedBy,
          votes: pending.responses
              .map((r) =>
                  DeletionVote(profileId: r.profileId, agreed: r.agreed))
              .toList(),
        ),
        iAmRequester: pending.request.requestedBy == me.id,
        onTap: () => _router.go('/family'),
      );
    } catch (_) {
      // No banner is the honest fallback: the Família page still shows the
      // whole panel, and the DB enforces the deadline regardless.
    }
  }

  /// U-13 — the picker's path. Local storage first (it is what the next boot
  /// reads), the profile second and best-effort; then the whole tree rebuilds
  /// in the new language (the `forceLoad` analog).
  Future<void> _setLanguage(AppLanguage language) async {
    if (language == _l.current) return;
    try {
      await widget.prefs
          .setString(LanguageResolver.storageKey, language.code);
    } catch (_) {
      // Storage refused the write: the session still gets the language below;
      // the next boot re-detects from the device locale.
    }
    if (_client.auth.currentSession != null) {
      try {
        final me = await _dataSource.fetchOwnProfile();
        if (me != null) {
          await _dataSource.updateOwnLanguage(me.id, language.code);
        }
      } catch (_) {
        // The client's choice does not depend on the server write — the
        // profile copy exists for the server-side senders.
      }
    }
    if (mounted) setState(() => _l = Localization(language));
  }

  @override
  Widget build(BuildContext context) {
    return AppL10n(
      l: _l,
      setLanguage: _setLanguage,
      child: Listener(
        // S-04: any touch anywhere is activity.
        behavior: HitTestBehavior.translucent,
        // T-78: and a touch is a day of use (throttled to one call a day).
        onPointerDown: (_) {
          _lastInteraction = DateTime.now();
          _touchActivity();
        },
        child: MaterialApp.router(
          // U-48: per route ("Família · Entrelares"), so tabs and history
          // are readable — T-64 fixed the URL and left the title.
          title: _documentTitle,
          // Material's own surfaces (dialogs, tooltips, a11y announcements)
          // follow the session language; the app's text reads the catalog.
          locale: _l.isEnglish ? const Locale('en') : const Locale('pt', 'BR'),
          supportedLocales: const [Locale('pt', 'BR'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          // U-27 — both themes are hand-written from the tokens, and dark
          // ships WITH them: it is nearly free here and was nearly impossible
          // against the 79 colour literals that delivery removed.
          // U-12 — and WHICH of the two is the reader's own answer now, read
          // from `prefs` before the first frame; "Sistema" is one of the three
          // answers, not the absence of one.
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: widget.appearance.themeMode,
          // T-53 stage 4 — the web channel is a phone-shaped app, and a
          // browser window is not a phone. The Blazor PWA always capped its
          // pages (`.page-container { max-width: 500px; margin: 0 auto }`), so
          // an edge-to-edge calendar on a 2000px monitor is a parity BREAK,
          // not inherited behaviour. 600 rather than the web's 500 by owner
          // decision: the calendar has seven columns and breathes better.
          // Applied through `builder`, so it wraps the Navigator and therefore
          // every route, sheet and dialog — one place, no screen to forget.
          //
          // T-64 — and `child` is the ROUTER itself (`WidgetsApp.build` hands
          // the builder its `routing` widget), so not returning it is how the
          // app spends the gate NOT ROUTING. That is the fix: a router that
          // mounts before the session gate has answered has to invent an
          // answer, and every answer it invented moved the URL away from what
          // the reader asked for — park on `/splash`, then hand the
          // destination back too late, then disagree with the address bar. It
          // also costs nothing: no screen builds, so no anon request is fired
          // for a session that is still being decided. When the phase lands,
          // the router mounts with the browser's own URL still intact and the
          // first decision made about it is the right one.
          builder: (context, child) => _phase == _AuthPhase.gate
              ? const AppWidthCap(child: AppSplash())
              : AppWidthCap(child: child),
          routerConfig: _router,
        ),
      ),
    );
  }
}

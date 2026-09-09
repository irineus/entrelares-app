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

import 'deep_link_urls.dart';
import 'env.dart';
import 'package:entrelares_db_contracts/models/member.dart';
import 'screens/calendar_screen.dart';
import 'screens/custom_roles_screen.dart';
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
import 'services/admin_mode.dart';
import 'services/analytics_service.dart';
import 'services/auth_providers.dart';
import 'services/custody_data_source.dart';
import 'services/notification_badge.dart';
import 'services/onboarding_service.dart';
import 'services/push_service.dart';
import 'services/session_gate.dart';
import 'services/store_billing.dart';
import 'services/sudo_service.dart';
import 'services/supabase_custody_data_source.dart';
import 'theme/app_theme.dart';
import 'widgets/app_l10n.dart';
import 'widgets/app_width_cap.dart';
import 'widgets/app_splash.dart';
import 'widgets/onboarding.dart';

/// Whether [usePathUrlStrategy] already ran in this PAGE. See its call site.
bool _urlStrategyApplied = false;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
  await Supabase.initialize(
    url: Env.current.supabaseUrl,
    publishableKey: Env.current.supabaseKey,
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
  runApp(EntrelaresApp(prefs: prefs, initialLanguage: language));
}

class EntrelaresApp extends StatefulWidget {
  final SharedPreferences prefs;
  final AppLanguage initialLanguage;

  const EntrelaresApp(
      {super.key, required this.prefs, required this.initialLanguage});

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
          onBackToFamily: () => _router.go('/family'),
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
            deletionBanner: _deletionBanner,
            tourKeys: _tourKeys),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/',
              builder: (_, _) => CalendarScreen(
                  dataSource: _dataSource,
                  adminMode: _adminMode,
                  analytics: _analytics,
                  onboarding: _onboarding,
                  tourKeys: _tourKeys,
                  onOpenFamily: () => _router.go('/family'),
                  onOpenNotifications: () => _router.go('/notifications')),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/family',
              builder: (_, _) => FamilyScreen(
                dataSource: _dataSource,
                adminMode: _adminMode,
                analytics: _analytics,
                sudo: _sudo,
                storeBilling: _storeBilling,
                onFamilyDeleted: _signOut,
                onOpenCustomRoles: () => _router.go('/family/custom-roles'),
                // F-16: own card opens my profile; another member's opens
                // theirs, and the screen itself re-checks that I may look.
                onOpenProfile: (member, isOwn) => _router.go(
                    isOwn ? '/family/profile' : '/family/profile/${member.id}'),
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
                    onSeePremium: () => _router.go('/family'),
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
                  ),
                  routes: [
                    GoRoute(
                      path: ':id',
                      builder: (_, state) => ProfileScreen(
                        dataSource: _dataSource,
                        sudo: _sudo,
                        profileId:
                            int.tryParse(state.pathParameters['id'] ?? ''),
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
                  push: _push,
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
              builder: (_, _) => ReportsScreen(dataSource: _dataSource),
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
  FamilyDeletionBanner? _deletionBanner;

  /// U-23 — the checklist/tour state and the shared registry of tour targets
  /// (they live in two different subtrees: the tab bar and the calendar).
  late final OnboardingService _onboarding;
  final _tourKeys = TourKeys();

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
      // on Histórico, which always holds the row that was tapped, while a
      // request awaiting this person lands on "Para você". The notification id
      // rides along so a SECOND tap re-applies the tab — the screen's State
      // survives inside the shell branch.
      final landing = PushRouting.landingFor(data['type']);
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
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSub?.cancel();
    if (_routerLive) {
      _router.routeInformationProvider.removeListener(_trackPageView);
    }
    _inactivityTimer?.cancel();
    _adminMode.dispose();
    _storeBilling?.dispose();
    _onboarding.dispose();
    _sudo.dispose();
    _badge.dispose();
    _push.dispose();
    _refresh.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkInactivity();
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
    final alive = await _gate.validateRestoredSession();
    if (!mounted) return;
    _expiredReason = !alive && hadSession
        ? SessionExpiredReason.restored
        : SessionExpiredReason.none;
    if (alive) {
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
      if (me != null) await _applyProfileGates(me);
    } finally {
      _resolvingPhase = false;
    }
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
        if (_deletionBanner != null) {
          setState(() => _deletionBanner = null);
        }
        return;
      }
      final members = await _dataSource.fetchMembers();
      if (!mounted) return;
      setState(() {
        _deletionBanner = FamilyDeletionBanner(
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
      });
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
        onPointerDown: (_) => _lastInteraction = DateTime.now(),
        child: MaterialApp.router(
          title:
              '${environmentTitlePrefix(isProduction: Env.current.isProduction)}'
              'Entrelares',
          // Material's own surfaces (dialogs, tooltips, a11y announcements)
          // follow the session language; the app's text reads the catalog.
          locale: _l.isEnglish ? const Locale('en') : const Locale('pt', 'BR'),
          supportedLocales: const [Locale('pt', 'BR'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          // U-27 — both themes are hand-written from the tokens, and dark
          // ships WITH them: it is nearly free here and was nearly impossible
          // against the 79 colour literals this delivery removed. Following
          // the system is the whole feature for now; a user-facing switch is
          // U-12's, not this item's.
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: ThemeMode.system,
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

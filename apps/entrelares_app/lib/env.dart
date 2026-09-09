import 'package:flutter/services.dart' show appFlavor;

/// PUBLIC client config — the same values the web app ships in its
/// `appsettings.json`. Nothing here is a secret and no secret may ever be
/// added to this file: both keys have zero privilege by construction
/// (100% RLS, T-44); all power comes from the authenticated session and the
/// server-side gates.
///
/// Stage 3 (T-53): environments are BUILD FLAVORS. The Supabase singleton
/// initializes once per process (pilot lesson 8), so [current] is resolved at
/// COMPILE TIME from `--flavor` — per build variant, never a runtime switcher.
class Env {
  const Env._({
    required this.name,
    required this.isProduction,
    required this.supabaseUrl,
    required this.supabaseKey,
    this.umamiWebsiteId = '',
    required this.analyticsHostname,
    required this.webHostname,
    required this.androidPackage,
    this.webPush = WebPushConfig.none,
  });

  final String name;
  final bool isProduction;
  final String supabaseUrl;
  final String supabaseKey;

  /// T-37: the Umami website id is PUBLIC (it identifies a site, not a person)
  /// but environment-specific. **Empty on dev on purpose** — the service turns
  /// into a no-op, so QA traffic never pollutes production statistics, exactly
  /// as the web app's deploy does by leaving the variable unset outside
  /// `master`.
  final String umamiWebsiteId;

  /// Umami Cloud. A self-hosted collector would change this (and the web app's
  /// `UMAMI_HOST` variable) together.
  final String umamiHost = 'https://cloud.umami.is';

  /// What Umami reports as the site. The app declares its own hostname so
  /// store traffic is separable from `web.entrelares.app` in the same
  /// dashboard — a device has no `location.hostname` to read.
  final String analyticsHostname;

  /// The same, for the WEB build of this environment. T-53 stage 4: Flutter
  /// Web took over the hostname the Blazor PWA reported, so the Umami series
  /// did not break in two at the cutover — the `channel` prop is what separates
  /// the clients, never the site.
  ///
  /// It is a DECLARED label, not a host the app resolves: the web build reports
  /// this string rather than `location.hostname`, exactly so the two channels
  /// land on one site. Production names the real host because they coincide;
  /// **dev is synthetic on purpose** — since the Blazor shutdown (T-56) there is
  /// no dev web deployment at all, so naming any real host here would name one
  /// that is either dead or somebody else's. It used to say `qa.entrelares.app`,
  /// which stopped resolving the day that Pages project was deleted.
  final String webHostname;

  /// T-48: the Android `applicationId` of THIS variant. Only the Play
  /// "manage subscription" deep link reads it, and pointing it at the wrong
  /// package sends the subscriber to a page about an app they do not have —
  /// hence a per-flavor value rather than a constant (dev deliberately keeps
  /// its own package so the QA build coexists with the store one).
  final String androidPackage;

  /// T-62: what the WEB build needs to push. Empty means "this environment is
  /// not armed", and the web transport then reports `unsupported` in words —
  /// the same fail-closed shape as `FCM_SERVICE_ACCOUNT` server-side and
  /// `billing.store_enabled` client-side. See [WebPushConfig].
  final WebPushConfig webPush;

  /// Dev/QA — the spike's original target. Still runs the legacy anon JWT
  /// until S-17 (app repo) retires it.
  static const dev = Env._(
    name: 'Dev/QA',
    isProduction: false,
    supabaseUrl: 'https://buroanotfjcgvbfmacuh.supabase.co',
    supabaseKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJ1cm9hbm90ZmpjZ3ZiZm1hY3VoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODEwMTIwNDcsImV4cCI6MjA5NjU4ODA0N30.hRU5jhn1pJQeUVpvnAp4IGBJ5Is_pCwlIfR5hdK9Mi0',
    // No website id: analytics is OFF on dev, by decision.
    analyticsHostname: 'dev.app.entrelares.app',
    // Synthetic, like its sibling above — see the field's doc.
    webHostname: 'dev.web.entrelares.app',
    androidPackage: 'com.entrelares.flutter',
    // T-62 armed 08/09/2026. There is no dev WEB deployment — since the Blazor
    // shutdown the only build that resolves to this environment on the web is a
    // local `flutter run -d chrome`. These values exist so that QA round is
    // repeatable by anyone, at any time, without a second visit to the console.
    // They are the DEV project's own: a QA run must never be able to register a
    // token against the production project, which is the whole reason the two
    // Firebase projects exist (runbook §11.1).
    webPush: WebPushConfig(
      apiKey: 'AIzaSyCveCQiYVaozqLQskx5_UZH8k5mJfUVWJI',
      appId: '1:51960618124:web:3855d5ada40801021dafa9',
      messagingSenderId: '51960618124',
      projectId: 'entrelares-dev',
      vapidKey:
          'BKVzlLeJytzADoULGBBLyQWAGd1SHTo-xyojfl10nbqchHrk-Jm_TPM5peu9fIT489ue_xgMJsK1D7Qc4BHHw2g',
    ),
  );

  /// Production — the exact public values `web.entrelares.app` serves every
  /// browser in `appsettings.json` (S-16 publishable key).
  static const prod = Env._(
    name: 'Produção',
    isProduction: true,
    supabaseUrl: 'https://jptqbwfziyzlhlmoekzu.supabase.co',
    supabaseKey: 'sb_publishable_uKr0ES-10F3gpcd0j0osYw_HxqP_RMZ',
    // T-37: the PRODUCT's Umami site — the same one the web app reports to, so
    // the two clients share a dashboard and the `channel` prop separates them.
    umamiWebsiteId: '6fdd6c5a-4bce-449f-8188-3b7399a859d8',
    analyticsHostname: 'app.entrelares.app',
    webHostname: 'web.entrelares.app',
    androidPackage: 'com.entrelares.app',
    // T-62 armed 08/09/2026 — the web channel's push is LIVE from this line.
    // Half the go-live is here; the other half is the identical object in
    // `web/firebase-messaging-sw.js`, which the service worker needs because it
    // starts with no page to ask. `web_channel_test` compares the two string by
    // string, so they cannot be armed one at a time — and while these were
    // blank the control read `unsupported` in words rather than offering a
    // button that could not work.
    webPush: WebPushConfig(
      apiKey: 'AIzaSyCqZbahPltUMUuH_IjWJCPhrH45ob6H6tM',
      appId: '1:575356979434:web:b193af65d8185c02e72f93',
      messagingSenderId: '575356979434',
      projectId: 'entrelares-prod',
      vapidKey:
          'BKxwYBh6_lCawyFhugKyh1yoRvm0-O2kAeH88KJxanKdsCEMUHS4ASehFoO6y_VXFHtQ0hrFWdabnvK5f49isNM',
    ),
  );

  /// How the WEB build says "production". `flutter build web` accepts no
  /// `--flavor` — on web [appFlavor] is always null — so the flavor alone
  /// would resolve the web channel to dev, and the production hostname would
  /// talk to the QA project. The deploy passes
  /// `--dart-define=APP_ENV=prod`, and `web_channel_test` fails the build if
  /// that define ever drops out of the workflow.
  static const _appEnv = String.fromEnvironment('APP_ENV');

  /// Anything that does not explicitly say `prod` falls back to dev:
  /// `flutter test` and flavor-less targets must never touch production.
  /// Mirror of `isProductionTarget` (core) — inlined because [current] has to
  /// be a compile-time constant, and covered there by its own suite.
  static const current =
      appFlavor == 'prod' || _appEnv == 'prod' ? prod : dev;

  /// Mirrors `pubspec.yaml`'s `version:` — the web's `AppVersion.Display`.
  /// Only the F-17 export reads it, and a stale value there would misdate an
  /// LGPD record, so `env_version_test.dart` fails the build if the two drift.
  static const String appVersion = '2.6.6+70';
}

/// T-62 — the PUBLIC Firebase Web config of one environment, plus its VAPID
/// public key.
///
/// **Why the web needs five values where Android needs a file.** On Android the
/// transport reads `google-services.json`, which the Gradle plugin bakes into
/// the flavor. There is no such file on the web: `Firebase.initializeApp` takes
/// explicit options, so the same public identifiers have to be written here,
/// per environment. Nothing in this class is a secret — every one of these
/// values is served to every browser that loads a Firebase web app, and the
/// VAPID key is the PUBLIC half of the pair (the private half never leaves the
/// Firebase console). Rule 1 of `CLAUDE.md` holds unchanged.
///
/// **Empty is a state, not an omission.** The item ships with the code, the
/// worker and the runbook complete and the values blank, because filling them
/// is Firebase-console work (`supabase/README.md` §11-bis). While they are
/// blank [isConfigured] is false, `PushMessaging.supported` is false, and the
/// Notificações control resolves to `unsupported` and SAYS so — never a switch
/// that does nothing when pressed.
class WebPushConfig {
  const WebPushConfig({
    this.apiKey = '',
    this.appId = '',
    this.messagingSenderId = '',
    this.projectId = '',
    this.vapidKey = '',
  });

  /// Firebase Console → Project settings → General → Your apps → Web app.
  final String apiKey;
  final String appId;
  final String messagingSenderId;
  final String projectId;

  /// Firebase Console → Project settings → Cloud Messaging → Web Push
  /// certificates → the "Key pair" column. Public by construction.
  final String vapidKey;

  /// Every value, or none. A HALF-filled config is the worst of the three
  /// states — it passes a "not empty" check and then fails at `getToken` with
  /// a message about an unrelated field — so the check is all five.
  bool get isConfigured =>
      apiKey.isNotEmpty &&
      appId.isNotEmpty &&
      messagingSenderId.isNotEmpty &&
      projectId.isNotEmpty &&
      vapidKey.isNotEmpty;

  /// The unarmed environment. Also what every non-web build carries: the
  /// native transport reads `google-services.json` and never looks here.
  static const none = WebPushConfig();
}

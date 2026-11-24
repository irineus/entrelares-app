import 'dart:js_interop';
// `globalContext['…']` and `.has(…)`: reading a property off an object whose
// shape is the BROWSER's, not ours. Feature detection has no typed binding by
// construction — the whole question is whether the property is there.
import 'dart:js_interop_unsafe';

import 'package:entrelares_core/entrelares_core.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

import '../env.dart';
import 'push_messaging.dart';

/// T-62 — the WEB transport. F-09 left this file a stub that answered "no" to
/// everything, because the web had a constraint the native channels do not;
/// this is that constraint worked out rather than flipped.
///
/// **The three workers on this origin, and why they do not collide.**
///   * `web/service-worker.js` is the TOMBSTONE of the Blazor PWA's worker. It
///     holds scope `/`, and its `activate` clears every cache, unregisters
///     ITSELF and reloads the open windows. It never touches another
///     registration, and nothing here registers it — only the browser's update
///     check on a device that still carries the old install reaches it at all.
///   * `flutter_service_worker.js` is the app shell, registered at scope `/` by
///     Flutter's own bootstrap.
///   * `firebase-messaging-sw.js` is registered by the Firebase JS SDK at its
///     own scope, `/firebase-cloud-messaging-push-scope`, which is exactly why
///     [target] does NOT pass `serviceWorkerScriptPath`: the FlutterFire layer
///     would then call `register(path)` with no `{scope}`, taking scope `/` and
///     REPLACING the app shell's registration. Letting the SDK register its own
///     worker is the whole answer to "which worker at which scope".
///
/// **Nothing is loaded until push is actually used.** `firebase_core_web` does
/// not bundle the Firebase JS SDK — it injects it from `www.gstatic.com`, which
/// this app's CSP forbids for executable code. So [_ensureFirebase] loads the
/// VENDORED copy (`tool/vendor_firebase_js.py`) from this origin and hands it
/// to the plugin through the two globals the plugin checks before injecting
/// anything. Being lazy is not only about weight: it means a person who never
/// enables push never fetches a byte of Firebase.
PushMessaging create() => WebPushMessaging();

class WebPushMessaging implements PushMessaging {
  /// The vendored SDK, at the version `web_channel_test` pins to the plugin's
  /// own `supportedFirebaseJsSdkVersion`.
  static const _sdkBase = '/firebasejs/13.3.0';

  FirebaseApp? _app;
  Future<bool>? _loading;

  @override
  String get platformName => 'web';

  /// Const-foldable from a compile-time constant: an environment with no
  /// Firebase Web config has no transport, and the control says `unsupported`
  /// rather than offering a button that cannot work.
  @override
  bool get supported => Env.current.webPush.isConfigured;

  /// Deliberately cheap, and deliberately NOT the SDK's `isSupported()` —
  /// answering that would mean downloading the SDK to ask whether we may use
  /// it. These three globals are what the SDK itself tests for, and their
  /// absence is a real browser: Firefox in a private window has no
  /// `serviceWorker`, and an iPhone that never added this site to the Home
  /// Screen has no `PushManager`.
  @override
  Future<bool> initialize() async =>
      supported &&
      globalContext.has('Notification') &&
      globalContext.has('PushManager') &&
      (globalContext['navigator'] as JSObject?)?.has('serviceWorker') == true;

  @override
  Future<PushPermission> permission() async => _current;

  @override
  Future<PushPermission> requestPermission() async {
    try {
      final status = (await web.Notification.requestPermission().toDart).toDart;
      return _map(status);
    } catch (error) {
      // A browser that refuses the call at all (an insecure origin, an iframe
      // without the permission). "Not asked" keeps the control offering, which
      // is the honest state: nothing was answered.
      debugPrint('[push] requestPermission failed: $error');
      return PushPermission.notAsked;
    }
  }

  /// This browser's Firebase Installation ID (T-109), or null.
  ///
  /// **The permission is read BEFORE the SDK is asked, and that guard is the
  /// point of this method.** The Firebase JS SDK's `register()` — like the
  /// `getToken` it replaces — opens the browser's permission prompt on its own
  /// when the permission is still `default`, and `PushService.start` calls this
  /// on EVERY authenticated session, whose documented contract is that it never
  /// prompts. Without this line the web channel would ask every returning
  /// visitor for notification permission at boot, with no gesture and no
  /// context, and would spend on page load the one prompt the product means to
  /// spend on a press. The prompt lives in [requestPermission], reachable only
  /// from the control.
  ///
  /// **The listener is armed before `register()`.** The JS SDK REFUSES a
  /// `register()` with no `onRegistered` handler in place, and the FID arrives
  /// only on that stream (every `register()` re-emits it). Reading the getter
  /// installs the handler; `.first` subscribes on the spot.
  @override
  Future<String?> target() async {
    if (_current != PushPermission.granted) return null;
    if (!await _ensureFirebase()) return null;
    final messaging = FirebaseMessaging.instance;
    final registered = messaging.onRegistered.first.timeout(_registerTimeout);
    try {
      await messaging.register(
        vapidKey: Env.current.webPush.vapidKey,
        // NOT passed on purpose — see the class doc. Null leaves the JS SDK to
        // register its own worker at its own scope, instead of the FlutterFire
        // layer registering it at `/` over the app shell.
        // ignore: avoid_redundant_argument_values
        serviceWorkerScriptPath: null,
      );
    } catch (_) {
      // The listener is already armed; left alone, its timeout fires 30 s
      // later as an UNHANDLED error — measured on Android (T-109).
      registered.ignore();
      rethrow;
    }
    return await registered;
  }

  static const _registerTimeout = Duration(seconds: 30);

  @override
  PushTargetKind get targetKind => PushTargetKind.fid;

  @override
  Future<void> unregister() async {
    // Only reachable after [target] brought the SDK up; asking otherwise would
    // download the whole SDK in order to drop a registration that cannot exist.
    if (_app == null) return;
    await FirebaseMessaging.instance.unregister();
  }

  /// The JS SDK feeds `onRegistered` on every `register()` and on the
  /// browser's `pushsubscriptionchange` — the rotation the old `onTokenRefresh`
  /// never reported on the web (its stream was never fed). Empty until the SDK
  /// is up, so a person who never enabled push never downloads it for this.
  @override
  Stream<String> get targetChanges => _app == null
      ? const Stream.empty()
      : FirebaseMessaging.instance.onRegistered;

  // T-109 MIGRATION ONLY — the token API firebase_messaging 17 deprecated.
  // Read once per browser, before the first `register()`, so the row an older
  // build wrote can be deleted; removed with the token path (cleanup card).
  // The same guard as [target]: `getToken` prompts on `default` too.
  @override
  Future<String?> legacyToken() async {
    if (_current != PushPermission.granted) return null;
    if (!await _ensureFirebase()) return null;
    // ignore: deprecated_member_use
    return FirebaseMessaging.instance.getToken(
      vapidKey: Env.current.webPush.vapidKey,
      // ignore: avoid_redundant_argument_values
      serviceWorkerScriptPath: null,
    );
  }

  @override
  Future<void> dropLegacyToken() async {
    if (_app == null) return;
    // ignore: deprecated_member_use
    await FirebaseMessaging.instance.deleteToken();
  }

  /// Empty because on this channel the tap never reaches Dart: a notification
  /// shown by a service worker is clicked against the WORKER, and
  /// `onMessageOpenedApp` has no web implementation at all. The landing rule
  /// lives in `web/firebase-messaging-sw.js`, which opens
  /// `/notifications?tab=…&n=…` — the same URL `main.dart` builds for Android,
  /// which is why the destination is identical on both channels.
  @override
  Stream<Map<String, String>> get opened => const Stream.empty();

  /// Always null on the web, in FlutterFire and therefore here. The cold-start
  /// case it exists for does not arise: the worker OPENS the URL, so the app
  /// boots already pointed at the right screen.
  @override
  Future<Map<String, String>?> initialMessage() async => null;

  PushPermission get _current {
    try {
      return _map(web.Notification.permission);
    } catch (error) {
      // `Notification` missing entirely — [initialize] already answered false,
      // so nothing downstream acts on this.
      return PushPermission.notAsked;
    }
  }

  PushPermission _map(String status) => switch (status) {
        'granted' => PushPermission.granted,
        // The browser's refusal is as permanent as Android's: the prompt does
        // not reappear, and only site settings undo it. `blocked`, not `off`.
        'denied' => PushPermission.denied,
        // 'default', and anything a future browser adds.
        _ => PushPermission.notAsked,
      };

  /// Loads the vendored SDK and brings Firebase up, once per page.
  ///
  /// The two globals are the plugin's own escape hatch: `firebase_core_web`
  /// injects the gstatic scripts only when `window.firebase_core` is unset, and
  /// `firebase_messaging_web` reads the module off `window.firebase_messaging`.
  /// Setting both before `initializeApp` means the plugin injects nothing and
  /// every byte of the SDK comes from this origin — which is what keeps
  /// `script-src 'self'` intact (`web_channel_test`).
  Future<bool> _ensureFirebase() => _loading ??= () async {
        try {
          if (globalContext['firebase_core'] == null) {
            globalContext['firebase_core'] =
                await importModule('$_sdkBase/firebase-app.js'.toJS).toDart;
            globalContext['firebase_messaging'] =
                await importModule('$_sdkBase/firebase-messaging.js'.toJS)
                    .toDart;
          }
          final config = Env.current.webPush;
          _app = await Firebase.initializeApp(
            options: FirebaseOptions(
              apiKey: config.apiKey,
              appId: config.appId,
              messagingSenderId: config.messagingSenderId,
              projectId: config.projectId,
            ),
          );
          return true;
        } catch (error) {
          // A blocked script, an offline load, a browser that refuses the
          // worker. Push is off; the session is not.
          debugPrint('[push] the web SDK did not come up: $error');
          _loading = null;
          return false;
        }
      }();
}

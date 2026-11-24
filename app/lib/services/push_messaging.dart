/// F-09 — the transport, chosen at COMPILE time.
///
/// **Why this seam exists, and it is two reasons.**
///
/// The first is the web channel. It has no push transport at all — Flutter Web
/// push needs its own service worker, and `web/service-worker.js` is the PWA's
/// tombstone, which exists to unregister itself and must never gain a handler.
/// Without this split the web build would still LINK `firebase_core` and
/// `firebase_messaging` to reach code that can never run, and the first-load
/// weight of the web channel is a product concern with an owner's acceptance
/// behind it. The conditional export below means those packages never reach
/// the web compile at all.
///
/// The second is that it makes [PushService] testable. `firebase_messaging` is
/// a platform channel and there is no Android under `flutter test`, so before
/// this seam the entire service was unreachable from a suite — including the
/// four-state control the person actually presses.
///
/// Same idiom, and the same reasoning, as `file_delivery.dart`.
library;

import 'package:entrelares_core/entrelares_core.dart';

import 'push_messaging_io.dart'
    if (dart.library.js_interop) 'push_messaging_web.dart' as impl;

/// The transport this build was compiled with.
PushMessaging createPushMessaging() => impl.create();

/// What the app needs from a push transport — nothing more, so a fake is cheap.
abstract class PushMessaging {
  /// False where there is no transport. Const-foldable per platform.
  bool get supported;

  /// Brings the transport up. Returns false when it cannot start (no config
  /// for this flavor, no Play Services, an offline first launch) — never
  /// throws, because a missing push must not take the boot with it.
  Future<bool> initialize();

  /// The OS permission as it stands right now. Read, never assumed: below
  /// Android 13 the grant is implicit, and a permission granted last week can
  /// be revoked in Settings without anything telling the app.
  Future<PushPermission> permission();

  /// Raises the OS dialog. On Android 13+ this is a ONE-SHOT resource — it
  /// appears once per install and a refusal is only undone in Settings — so
  /// only a gesture may call it.
  Future<PushPermission> requestPermission();

  /// This device's push TARGET — the value the server addresses it by — or
  /// null when there is none to give. Since T-109 a Firebase Installation ID
  /// from `register()`/`onRegistered`, never the deprecated registration token
  /// (see [targetKind]). Never prompts: a transport whose registration would
  /// raise the permission dialog answers null while the permission is unasked.
  Future<String?> target();

  /// What [target] returns, as stored in `push_subscriptions.kind` — the
  /// server picks the FCM v1 field (`fid` / `token`) by it.
  PushTargetKind get targetKind;

  /// Unregisters this installation at the transport, so the next [target]
  /// registers anew.
  Future<void> unregister();

  /// Fires when the transport re-registers this installation on its own (an
  /// ID change, a routine sync, a browser `pushsubscriptionchange`). Missing
  /// this is the classic silent break: every layer keeps reporting success
  /// while the server holds an address nobody answers.
  Stream<String> get targetChanges;

  /// T-109 MIGRATION ONLY: the registration token an older build of this app
  /// stored on the server for this device, or null when there is none to give.
  /// Read ONCE per install by [PushService] — Firebase warns against using the
  /// token API and the installation API together — so the old row can be
  /// deleted and the device does not receive every push twice. Always null on
  /// Android, where the installation-ID opt-in disables the token API and FCM
  /// retires the old token by itself (measured; see push_messaging_io.dart).
  /// Goes away with the token path (the T-109 cleanup card).
  Future<String?> legacyToken();

  /// T-109 MIGRATION ONLY: invalidates that token at the transport.
  Future<void> dropLegacyToken();

  /// Fires when a notification is TAPPED, carrying its data payload.
  Stream<Map<String, String>> get opened;

  /// The message that launched the app from a cold start, delivered exactly
  /// once — it waits here rather than on [opened].
  Future<Map<String, String>?> initialMessage();

  /// Which platform string a registration should be stored under.
  String get platformName;
}

/// The OS permission, in the three shapes the app has to tell apart.
enum PushPermission {
  /// Notifications may be shown.
  granted,

  /// The dialog has never been answered — the prompt is still available.
  notAsked,

  /// Refused. On Android the dialog will not appear again, so the app must
  /// send the person to Settings rather than offer a button that does nothing.
  denied,
}

import 'package:entrelares_core/entrelares_core.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'push_messaging.dart';

/// F-09 — the native transport: FCM, which carries Android today and APNs on
/// iOS the moment T-40 produces an `ios/` at all (the plugin covers both, so
/// nothing here is Android-specific).
///
/// This file is the ONLY place `firebase_core` and `firebase_messaging` are
/// imported. It is never compiled for the web — see `push_messaging.dart`.
PushMessaging create() => FcmMessaging();

class FcmMessaging implements PushMessaging {
  @override
  bool get supported => true;

  @override
  String get platformName =>
      defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';

  @override
  Future<bool> initialize() async {
    try {
      await Firebase.initializeApp();
      return true;
    } catch (error) {
      // A flavor with no `google-services.json`, or a device without the
      // services the transport needs. The product's whole job works without
      // push, so this degrades to "no push" and never to a dead first frame.
      debugPrint('[push] Firebase.initializeApp failed: $error');
      return false;
    }
  }

  @override
  Future<PushPermission> permission() async =>
      _map(await FirebaseMessaging.instance.getNotificationSettings());

  @override
  Future<PushPermission> requestPermission() async =>
      _map(await FirebaseMessaging.instance.requestPermission());

  PushPermission _map(NotificationSettings settings) =>
      switch (settings.authorizationStatus) {
        // `provisional` is iOS's quiet delivery — notifications DO arrive, so
        // for every decision the app makes it is a grant.
        AuthorizationStatus.authorized ||
        AuthorizationStatus.provisional =>
          PushPermission.granted,
        AuthorizationStatus.denied => PushPermission.denied,
        // notDetermined, and anything a future SDK adds: the prompt has not
        // been spent, so the control keeps offering it.
        _ => PushPermission.notAsked,
      };

  /// T-109: the Firebase Installation ID, from `register()`/`onRegistered`.
  ///
  /// The listener is armed BEFORE `register()` — `.first` subscribes on the
  /// spot — because the FID arrives only on the stream: every `register()`
  /// re-emits it, even for an installation already registered. A transport that
  /// never answers (no Play Services, an offline first run) times out into an
  /// error, which [PushService] already reads as "no target right now".
  @override
  Future<String?> target() async {
    final messaging = FirebaseMessaging.instance;
    final registered = messaging.onRegistered.first.timeout(_registerTimeout);
    await messaging.register();
    return await registered;
  }

  static const _registerTimeout = Duration(seconds: 30);

  @override
  PushTargetKind get targetKind => PushTargetKind.fid;

  @override
  Future<void> unregister() => FirebaseMessaging.instance.unregister();

  /// Emits on every app start with auto-init on (a routine sync), on every
  /// `register()`, and when the FID changes. [PushService] upserts each one, so
  /// a repeat is a `last_seen_at` touch and a change re-points the row.
  @override
  Stream<String> get targetChanges => FirebaseMessaging.instance.onRegistered;

  // T-109 MIGRATION ONLY — the token API firebase_messaging 17 deprecated.
  // Read once per install, before the first `register()`, to delete the row
  // an older build wrote; removed with the token path (T-109 cleanup card).
  @override
  // ignore: deprecated_member_use
  Future<String?> legacyToken() => FirebaseMessaging.instance.getToken();

  @override
  // ignore: deprecated_member_use
  Future<void> dropLegacyToken() => FirebaseMessaging.instance.deleteToken();

  @override
  Stream<Map<String, String>> get opened =>
      FirebaseMessaging.onMessageOpenedApp.map(_data);

  @override
  Future<Map<String, String>?> initialMessage() async {
    final message = await FirebaseMessaging.instance.getInitialMessage();
    return message == null ? null : _data(message);
  }

  Map<String, String> _data(RemoteMessage message) => {
        for (final entry in message.data.entries)
          entry.key: entry.value?.toString() ?? '',
      };
}

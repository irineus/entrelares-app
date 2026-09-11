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

  @override
  Future<String?> token() => FirebaseMessaging.instance.getToken();

  @override
  Future<void> deleteToken() => FirebaseMessaging.instance.deleteToken();

  @override
  Stream<String> get tokenRefreshes => FirebaseMessaging.instance.onTokenRefresh;

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

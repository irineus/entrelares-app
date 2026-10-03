import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// F-80 PR 2 — the family referral code an Android install carried.
///
/// The landing sends an Android reader of a family's link to the Play listing
/// with `referrer=ReferralRules.installReferrer(code)`; Play keeps that string
/// for the install (around 90 days) and hands it back through Google's
/// Install Referrer API. The API is read by a small platform channel in the
/// app's OWN Android code (`MainActivity`, library
/// `com.android.installreferrer:installreferrer`) — no pub.dev plugin, because
/// the old ones apply `kotlin-android` and break on the pinned AGP 9.
///
/// Read only where a founder is being made, and only after the caller saw
/// `feature.referral` on — dark, this class is never asked:
///   * the register screen, BEFORE the e-mail sign-up, so the code rides in
///     the sign-up metadata (an e-mail founder has no session until the
///     address is confirmed, often after `attribute_referral`'s 24 h);
///   * `main.dart`, after a Google founder's onboarding, for the RPC.
///
/// No "already read" marker on disk, on purpose: both moments happen once per
/// family by construction (a family is founded once), and the server is
/// idempotent anyway (first touch wins, and only a family born in the last
/// 24 h is accepted). A marker would be one more thing Android Auto Backup
/// could copy to another device (T-18) for no behaviour it changes. In memory
/// the answer is read once per process ([code] memoises).
class InstallReferrer {
  InstallReferrer({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  /// The channel `MainActivity` answers on. Spelled once on each side.
  static const String channelName = 'app.entrelares/install_referrer';

  /// The one method: answers the raw referrer string, or null.
  static const String readMethod = 'read';

  /// How long a founder's sign-up may wait on Play's service — a referral
  /// never delays a sign-up by more than this.
  static const Duration timeout = Duration(seconds: 3);

  final MethodChannel _channel;
  Future<String?>? _code;

  /// The reader for this build, or null where the API does not exist (the
  /// web, and any platform that is not Android).
  static InstallReferrer? forThisPlatform() =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android
      ? InstallReferrer()
      : null;

  /// The code the install carried, already shaped by
  /// [ReferralRules.codeFromInstallReferrer], or null — for an organic
  /// install, a sideload, a missing Play Store, a slow service or any error.
  /// Never throws.
  Future<String?> code() => _code ??= _read();

  Future<String?> _read() async {
    try {
      final raw = await _channel
          .invokeMethod<String>(readMethod)
          .timeout(timeout);
      return ReferralRules.codeFromInstallReferrer(raw);
    } catch (_) {
      return null;
    }
  }
}

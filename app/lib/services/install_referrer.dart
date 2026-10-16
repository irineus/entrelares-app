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
/// T-101 (04/10/2026): the same string also says where the install came from
/// ([acquisition]) — read at every founder sign-up on Android, flag or not,
/// for the family's acquisition source.
///
/// For the referral code, read only where a founder is being made, and only
/// after the caller saw `feature.referral` on:
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
  Future<String?>? _raw;

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
  Future<String?> code() async =>
      ReferralRules.codeFromInstallReferrer(await _rawOnce());

  /// T-101 — where this install came from (`AcquisitionRules`): a referral
  /// code, a Google Ads click (`gclid`/`gbraid`), one of our ads' `utm_source`
  /// words, or organic. Read only where a family is being founded; only the
  /// verdict and the campaign token leave the device — the string itself is
  /// never sent nor stored. Never throws: a sideload, a missing Play Store or
  /// a slow service is `organic`.
  Future<Acquisition> acquisition() async =>
      AcquisitionRules.fromInstallReferrer(await _rawOnce());

  /// The raw string, asked once per process (both readers share it).
  Future<String?> _rawOnce() => _raw ??= _read();

  Future<String?> _read() async {
    try {
      return await _channel.invokeMethod<String>(readMethod).timeout(timeout);
    } catch (_) {
      return null;
    }
  }
}

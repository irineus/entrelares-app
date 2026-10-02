/// F-72 — whether the web channel invites an Android reader to install the
/// Play app.
///
/// T-65 (13/09/2026) handed a reader over to the INSTALLED app and left the
/// opposite case out on purpose: while the listing was a closed test, an
/// install link led a stranger to a page they could not open. T-59 made the
/// listing public on 25/09/2026, and the Play listing is the largest zero-cost
/// channel the product has (L-13).
///
/// The whole difficulty is the one T-65 already named: the browser answers
/// `getInstalledRelatedApps()` with an EMPTY LIST both for "not installed" and
/// for any of the four sources it depends on being broken. An invitation to
/// install shown to someone who HAS the app is the defect to design against,
/// so the rule trusts an empty list only when:
///
///   * the browser implements the API at all ([StoreAppPresence.unknown] —
///     no API, a rejected promise — invites nobody, the T-38 shape);
///   * the device is Android (desktop Chrome implements the API too, for
///     Windows apps, and answers an empty list there);
///   * THIS browser never confirmed the app before (owner, 27/09/2026): once a
///     handoff was possible here, a later empty list is far likelier to be a
///     broken source than an uninstall, and the invitation stays away for good.
///
/// The four sources themselves are pinned by `web_channel_test`, so the
/// residual case is narrow — and its cost is small: the Play listing of an
/// installed app shows *Abrir*, not a dead end.
///
/// Two more silences, both owner's calls (27/09/2026): a web app already
/// installed to the Home Screen chose the web as its app, and is not asked
/// again; and a dismissal snoozes for [InstallHintRules.snooze], three times
/// at most — the U-54 shape, shared on purpose so the two install offers of
/// the product keep one rhythm.
///
/// Production builds only: a dev web build names the dev `applicationId`,
/// which has no store listing, and must never send a tester to production.
library;

import 'install_hint_rules.dart';

/// What the browser answered about the store app on this device — T-65's
/// question with its third answer spelled out, which the handoff alone never
/// needed ("not confirmed" and "not installed" both meant "no crossing").
enum StoreAppPresence {
  /// The browser could not answer: no `getInstalledRelatedApps`, a rejected
  /// promise, a native build. Invites nobody and offers no crossing.
  unknown,

  /// The browser confirmed the store package on this device.
  installed,

  /// The browser implements the API and did NOT list the package.
  notInstalled,
}

abstract final class PlayInstallRules {
  /// `Android` is in the user agent of every browser on Android — Chrome
  /// included, and Chrome's "desktop site" mode aside, which the API answer
  /// then covers only when the reader asked for it. No iOS or desktop agent
  /// carries the token.
  static bool isAndroid(String userAgent) => userAgent.contains('Android');

  /// The whole decision.
  static bool shouldInvite({
    required bool isProduction,
    required BrowserInstallFacts facts,
    required StoreAppPresence presence,
    required bool appConfirmedBefore,
    InstallHintDismissals dismissals = InstallHintDismissals.none,
    required DateTime now,
  }) {
    if (!isProduction) return false;
    if (presence != StoreAppPresence.notInstalled) return false;
    if (appConfirmedBefore) return false;
    if (!isAndroid(facts.userAgent)) return false;
    if (InstallHintRules.isStandalone(facts)) return false;
    return !InstallHintRules.isQuiet(dismissals, now);
  }

  /// The public listing the invitation opens.
  ///
  /// `referrer` is Google Play's own install-referrer parameter, not a
  /// pageview query: the Play Console reads its `utm_*` into the acquisition
  /// report, which is the only place an install can be attributed at all —
  /// our Umami ends at the tap (`play-invite-open`), and `utm_*` on OUR
  /// addresses measures nothing (L-27).
  ///
  /// [referrer] defaults to the shell banner's campaign; F-80 passes
  /// `ReferralRules.installReferrer(code)` so the installed app can read the
  /// family's code back through the Install Referrer API.
  static Uri listingUri(String androidPackage,
          {String referrer = PlayInstallRules.referrer}) =>
      Uri.https(
        'play.google.com',
        '/store/apps/details',
        {'id': androidPackage, 'referrer': referrer},
      );

  /// The campaign the Play Console groups these installs under. Spelled once;
  /// renaming it ends the series in the Console, like an Umami event name.
  static const String referrer =
      'utm_source=web.entrelares.app&utm_medium=shell-banner'
      '&utm_campaign=play-invite';
}

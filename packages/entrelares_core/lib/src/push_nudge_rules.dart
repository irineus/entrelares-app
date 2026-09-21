/// U-54 — the one next step toward push for a reader whose device does not
/// receive it yet, chosen by what THAT device can do.
///
/// Origin: family 19's father reads the app in Safari on an iPhone, with no
/// device registered, and the F-52 avisos meant for the day reached him days
/// later as unread rows. On production (21/09/2026) only 4 of 35 active members
/// had any device with push. The Notificações screen told a Safari tab only
/// that notifications "work in the installed app" — no action, and no way back
/// to the U-51 install sheet once its strip was dismissed.
///
/// A pure function of two things the app already holds: the [PushState] the
/// `PushService` settled on, and the [BrowserInstallFacts] the U-51 seam reads
/// (null in the native app, where there is no browser to ask). It is shown
/// ONLY to the member whose device it is — the product never tells one member
/// about another member's device (owner, 21/09/2026).
///
/// Fail-closed like [InstallHintRules]: a browser this rule does not recognise
/// gets the plain "this browser does not receive notifications" line, never a
/// set of steps that may not match the screen in the reader's hand.
library;

import 'install_hint_rules.dart';
import 'push_enrollment.dart';

/// What the Notificações screen offers.
enum PushNudgeStep {
  /// Push is on for this device: nothing to nudge.
  none,

  /// Supported and not enrolled: the U-43 card with *Ativar notificações*.
  enable,

  /// Safari on an iPhone/iPad, still in a tab: on iOS a web app receives
  /// notifications only from the Home Screen, so the step is the U-51 sheet.
  install,

  /// Another browser, or an in-app web view, on an iPhone/iPad: the install
  /// steps are Safari's, so the step is "open this address in Safari".
  needsSafari,

  /// Refused in the Android app: Settings → Notifications → App notifications.
  reallowApp,

  /// Refused in the installed iPhone app: Ajustes → Notificações → Entrelares.
  reallowIos,

  /// Refused in a browser: the site's permission, next to the address bar.
  reallowBrowser,

  /// The device itself has no transport (an app with no Play services, an
  /// installed iPhone app on an iOS without web push): nothing to do.
  unsupportedHere,

  /// A browser with no push at all (Firefox in a private window, say): the
  /// installed app is where notifications live.
  unsupportedBrowser;

  /// A step with a button. It sits ABOVE the list, like the U-43 card; every
  /// other step is the quiet line after it, with no button that cannot work.
  bool get isActionable => this == enable || this == install;

  /// The closed value analytics carries (T-37: no identifiers, ever).
  String get analyticsValue => switch (this) {
        none => 'none',
        enable => 'enable',
        install => 'install',
        needsSafari => 'needs-safari',
        reallowApp || reallowIos || reallowBrowser => 'reallow',
        unsupportedHere || unsupportedBrowser => 'unsupported',
      };
}

/// Where the reader is, as analytics names it. A closed set.
enum PushNudgePlatform {
  androidApp('android-app'),
  iosSafari('ios-safari'),
  iosStandalone('ios-standalone'),
  iosOther('ios-other'),
  web('web');

  final String analyticsValue;
  const PushNudgePlatform(this.analyticsValue);
}

abstract final class PushNudgeRules {
  static bool _isApple(BrowserInstallFacts facts) =>
      InstallHintRules.isAppleTouchDevice(
          userAgent: facts.userAgent, maxTouchPoints: facts.maxTouchPoints);

  static PushNudgePlatform platform(BrowserInstallFacts? facts) {
    if (facts == null) return PushNudgePlatform.androidApp;
    if (!_isApple(facts)) return PushNudgePlatform.web;
    if (InstallHintRules.isStandalone(facts)) {
      return PushNudgePlatform.iosStandalone;
    }
    return InstallHintRules.isSafari(facts.userAgent)
        ? PushNudgePlatform.iosSafari
        : PushNudgePlatform.iosOther;
  }

  /// The whole decision.
  static PushNudgeStep step({
    required PushState state,
    required BrowserInstallFacts? facts,
  }) {
    switch (state) {
      case PushState.on:
        return PushNudgeStep.none;
      case PushState.off:
        return PushNudgeStep.enable;
      case PushState.blocked:
        if (facts == null) return PushNudgeStep.reallowApp;
        return _isApple(facts) && InstallHintRules.isStandalone(facts)
            ? PushNudgeStep.reallowIos
            : PushNudgeStep.reallowBrowser;
      case PushState.unsupported:
        if (facts == null) return PushNudgeStep.unsupportedHere;
        if (!_isApple(facts)) return PushNudgeStep.unsupportedBrowser;
        if (InstallHintRules.isStandalone(facts)) {
          return PushNudgeStep.unsupportedHere;
        }
        return InstallHintRules.canInstall(facts)
            ? PushNudgeStep.install
            : PushNudgeStep.needsSafari;
    }
  }

  /// What a tap on *Ativar notificações* ended in, for `push-enable-result`.
  /// Read off the RESULTING state: a dialog the reader closed leaves it `off`.
  static String enableOutcome(PushState result) => switch (result) {
        PushState.on => 'granted',
        PushState.blocked => 'denied',
        PushState.off => 'dismissed',
        PushState.unsupported => 'unsupported',
      };
}

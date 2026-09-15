/// U-51 — whether to tell a reader how to put the app on the iPhone's Home
/// Screen.
///
/// Since 15/09/2026 the native iOS build (T-40) waits for revenue, so for an
/// iPhone `web.entrelares.app` installed to the Home Screen is the ONLY
/// channel — and only the landing (L-19) taught the gesture. A reader who
/// arrives straight at the app, through an invitation link or a notification
/// e-mail, keeps it as a Safari tab and never learns there is an icon to have.
///
/// The decision is a pure function of four facts the browser exposes, read on
/// the web side (`install_hint_web.dart`) and handed here:
///
///   * the user agent — is this an iPhone, an iPod or an iPad, and is the
///     browser Safari proper (the Share sheet with *Adicionar à Tela de Início*
///     is Safari's; Chrome, Firefox and Edge on iOS are WebKit under another
///     chrome and do not follow the steps the sheet gives);
///   * `navigator.maxTouchPoints` — since iPadOS 13 an iPad's Safari presents
///     itself as a Macintosh, and the touch count is what tells it apart from
///     a Mac, where the gesture does not exist;
///   * whether the page already runs standalone — Safari's own
///     `navigator.standalone`, or the standard `display-mode: standalone`
///     media query. Installed, the hint has nothing left to say;
///   * whether this browser dismissed the hint before.
///
/// Fail-closed, in the T-38 shape: a fact the browser could not answer arrives
/// as "no", and every "no" means no hint. The accepted price is silence on a
/// browser this rule does not recognise; the alternative is a set of steps
/// that do not match the screen in the reader's hand.
library;

/// What the browser said about itself, as the web side read it. Every field
/// has a fail-closed default so a property the browser lacks never becomes a
/// hint.
class BrowserInstallFacts {
  final String userAgent;
  final int maxTouchPoints;

  /// Safari's `navigator.standalone`: true inside an app added to the Home
  /// Screen. Undefined everywhere else, which the reader maps to false.
  final bool navigatorStandalone;

  /// `matchMedia('(display-mode: standalone)').matches` — the standard
  /// spelling of the same fact.
  final bool displayModeStandalone;

  const BrowserInstallFacts({
    required this.userAgent,
    this.maxTouchPoints = 0,
    this.navigatorStandalone = false,
    this.displayModeStandalone = false,
  });
}

abstract final class InstallHintRules {
  /// User-agent tokens of browsers that run on iOS but are NOT Safari. Each
  /// one wraps WebKit in its own chrome, so the Share button the steps name
  /// is somewhere else or absent. Spelled as the vendors spell them.
  static const List<String> _notSafariTokens = [
    'CriOS/', // Chrome
    'FxiOS/', // Firefox
    'EdgiOS/', // Edge
    'OPiOS/', 'OPT/', // Opera, Opera Touch
    'DuckDuckGo/',
    'YaBrowser/',
    'GSA/', // the Google app's in-app browser
  ];

  /// An iPhone, iPod touch, or an iPad — including an iPad whose Safari
  /// presents itself as a Macintosh (the default since iPadOS 13), which only
  /// the touch count distinguishes from a Mac.
  static bool isAppleTouchDevice({
    required String userAgent,
    required int maxTouchPoints,
  }) {
    if (userAgent.contains('iPhone') ||
        userAgent.contains('iPad') ||
        userAgent.contains('iPod')) {
      return true;
    }
    return userAgent.contains('Macintosh') && maxTouchPoints > 1;
  }

  /// Safari proper, as opposed to WebKit inside another browser or inside an
  /// app's web view.
  ///
  /// Safari carries BOTH a `Version/` and a `Safari/` token; an in-app web
  /// view (a link opened inside a mail or chat app) carries neither a
  /// `Version/` nor, usually, a `Safari/` — and has no Share sheet with the
  /// install row, so the steps would be wrong there.
  static bool isSafari(String userAgent) {
    if (!userAgent.contains('Safari/') || !userAgent.contains('Version/')) {
      return false;
    }
    return !_notSafariTokens.any(userAgent.contains);
  }

  /// Already on the Home Screen, by either spelling of the fact.
  static bool isStandalone(BrowserInstallFacts facts) =>
      facts.navigatorStandalone || facts.displayModeStandalone;

  /// The whole decision.
  static bool shouldHint(BrowserInstallFacts facts, {required bool dismissed}) {
    if (dismissed) return false;
    if (isStandalone(facts)) return false;
    if (!isAppleTouchDevice(
        userAgent: facts.userAgent, maxTouchPoints: facts.maxTouchPoints)) {
      return false;
    }
    return isSafari(facts.userAgent);
  }
}

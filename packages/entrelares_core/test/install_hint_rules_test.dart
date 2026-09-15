import 'package:entrelares_core/entrelares_core.dart';
import 'package:test/test.dart';

// User agents as the browsers actually send them (iOS 26 / current releases,
// read from the vendors' own strings on 15/09/2026). A rule tested against
// strings we typed to fit it would pass while production never matched — the
// save_errors.dart lesson.
const iphoneSafari =
    'Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) '
    'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 '
    'Safari/604.1';
const ipadSafariDesktopMode =
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 '
    '(KHTML, like Gecko) Version/26.0 Safari/605.1.15';
const ipadSafariMobileMode =
    'Mozilla/5.0 (iPad; CPU OS 26_0 like Mac OS X) AppleWebKit/605.1.15 '
    '(KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1';
const macSafari = ipadSafariDesktopMode; // the same string; touch tells them apart
const chromeIos =
    'Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) '
    'AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/140.0.0.0 Mobile/15E148 '
    'Safari/604.1';
const firefoxIos =
    'Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) '
    'AppleWebKit/605.1.15 (KHTML, like Gecko) FxiOS/140.0 Mobile/15E148 '
    'Safari/605.1.15';
const edgeIos =
    'Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) '
    'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 EdgiOS/140.0.0.0 '
    'Mobile/15E148 Safari/604.1';
const iosWebView =
    'Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) '
    'AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148';
const androidChrome =
    'Mozilla/5.0 (Linux; Android 15; SM-S911B) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/140.0.0.0 Mobile Safari/537.36';
const windowsChrome =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';

BrowserInstallFacts facts(
  String userAgent, {
  int touch = 5,
  bool navigatorStandalone = false,
  bool displayModeStandalone = false,
}) =>
    BrowserInstallFacts(
      userAgent: userAgent,
      maxTouchPoints: touch,
      navigatorStandalone: navigatorStandalone,
      displayModeStandalone: displayModeStandalone,
    );

bool hint(BrowserInstallFacts f, {bool dismissed = false}) =>
    InstallHintRules.shouldHint(f, dismissed: dismissed);

void main() {
  group('who gets the hint', () {
    test('an iPhone in Safari, not yet installed', () {
      expect(hint(facts(iphoneSafari)), isTrue);
    });

    test('an iPad in Safari, in both of its disguises', () {
      // Since iPadOS 13 Safari presents an iPad as a Macintosh; only the
      // touch count says it is not a Mac.
      expect(hint(facts(ipadSafariDesktopMode, touch: 5)), isTrue);
      expect(hint(facts(ipadSafariMobileMode, touch: 5)), isTrue);
    });

    test('an iPhone that asked for the desktop site still counts', () {
      // "Solicitar site para computador" swaps the UA for the Mac one; the
      // device and the gesture are unchanged.
      expect(hint(facts(macSafari, touch: 5)), isTrue);
    });
  });

  group('who never does', () {
    test('an app already on the Home Screen, by either spelling', () {
      // Installed, the hint has nothing left to say. Safari exposes
      // `navigator.standalone`; the standard media query says the same.
      expect(hint(facts(iphoneSafari, navigatorStandalone: true)), isFalse);
      expect(hint(facts(iphoneSafari, displayModeStandalone: true)), isFalse);
    });

    test('a browser that dismissed it', () {
      expect(hint(facts(iphoneSafari), dismissed: true), isFalse);
    });

    test('a Mac in Safari — same UA as an iPad, no touch', () {
      expect(hint(facts(macSafari, touch: 0)), isFalse);
      expect(hint(facts(macSafari, touch: 1)), isFalse);
    });

    test('Android, whose UA also says "Safari"', () {
      // Chrome on Android carries a `Safari/` token; the T-65 handoff is that
      // channel's banner, and T-59 owns its install invitation.
      expect(hint(facts(androidChrome)), isFalse);
    });

    test('a desktop browser', () {
      expect(hint(facts(windowsChrome, touch: 0)), isFalse);
      // A touch laptop is still not an Apple device.
      expect(hint(facts(windowsChrome, touch: 10)), isFalse);
    });

    test('the other browsers on iOS — the steps are Safari\'s', () {
      // WebKit under another chrome: the Share button the steps name is
      // elsewhere or absent. Silence beats steps that do not match the screen.
      expect(hint(facts(chromeIos)), isFalse);
      expect(hint(facts(firefoxIos)), isFalse);
      expect(hint(facts(edgeIos)), isFalse);
    });

    test('an in-app web view — no Share sheet, no install row', () {
      // A link opened inside a mail or chat app: no `Version/` token, and no
      // way to add to the Home Screen from there.
      expect(hint(facts(iosWebView)), isFalse);
    });

    test('a browser that answered nothing', () {
      // Every fact defaults to its fail-closed value: an empty UA and no touch
      // count is "do not hint", never an error.
      expect(hint(const BrowserInstallFacts(userAgent: '')), isFalse);
    });
  });

  group('the parts', () {
    test('isSafari needs both the Version/ and the Safari/ token', () {
      expect(InstallHintRules.isSafari(iphoneSafari), isTrue);
      expect(InstallHintRules.isSafari(chromeIos), isFalse);
      expect(InstallHintRules.isSafari(iosWebView), isFalse);
      expect(InstallHintRules.isSafari('Version/26.0'), isFalse);
      expect(InstallHintRules.isSafari('Safari/604.1'), isFalse);
    });

    test('isAppleTouchDevice reads the device, not the browser', () {
      expect(
          InstallHintRules.isAppleTouchDevice(
              userAgent: chromeIos, maxTouchPoints: 5),
          isTrue);
      expect(
          InstallHintRules.isAppleTouchDevice(
              userAgent: androidChrome, maxTouchPoints: 5),
          isFalse);
    });
  });
}

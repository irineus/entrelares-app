import 'package:entrelares_core/entrelares_core.dart';
import 'package:test/test.dart';

// The same real user agents the U-51 rule is tested with — a rule tested
// against strings typed to fit it passes while production never matches.
import 'install_hint_rules_test.dart'
    show
        androidChrome,
        chromeIos,
        facts,
        firefoxIos,
        iosWebView,
        ipadSafariDesktopMode,
        iphoneSafari,
        macSafari,
        windowsChrome;

PushNudgeStep step(PushState state, BrowserInstallFacts? f) =>
    PushNudgeRules.step(state: state, facts: f);

void main() {
  group('an iPhone reader in Safari, not installed — family 19\'s father', () {
    // No PushManager in a Safari tab, so the service settles on `unsupported`.
    test('is walked to the install sheet', () {
      expect(step(PushState.unsupported, facts(iphoneSafari)),
          PushNudgeStep.install);
      expect(step(PushState.unsupported, facts(ipadSafariDesktopMode)),
          PushNudgeStep.install);
    });

    test('the install step has a button; it sits above the list', () {
      expect(PushNudgeStep.install.isActionable, isTrue);
      expect(PushNudgeStep.enable.isActionable, isTrue);
    });
  });

  group('the other iOS browsers are told to use Safari, never given steps', () {
    test('Chrome, Firefox, an in-app web view', () {
      for (final ua in [chromeIos, firefoxIos, iosWebView]) {
        expect(step(PushState.unsupported, facts(ua)),
            PushNudgeStep.needsSafari,
            reason: ua);
      }
      expect(PushNudgeStep.needsSafari.isActionable, isFalse);
    });
  });

  group('installed on an iPhone', () {
    final installed = facts(iphoneSafari, navigatorStandalone: true);

    test('permission not asked: the U-43 card, unchanged', () {
      expect(step(PushState.off, installed), PushNudgeStep.enable);
    });

    test('refused: the Ajustes path, no button', () {
      expect(step(PushState.blocked, installed), PushNudgeStep.reallowIos);
    });

    test('an iOS without web push: nothing to do, said plainly', () {
      // Standalone and still no PushManager — the transport is not there.
      expect(step(PushState.unsupported, installed),
          PushNudgeStep.unsupportedHere);
    });

    test('push on: nothing to nudge', () {
      expect(step(PushState.on, installed), PushNudgeStep.none);
    });
  });

  group('Android and desktop — U-43 behaviour kept', () {
    test('the app: enable, then Settings when refused', () {
      expect(step(PushState.off, null), PushNudgeStep.enable);
      expect(step(PushState.blocked, null), PushNudgeStep.reallowApp);
      expect(step(PushState.unsupported, null), PushNudgeStep.unsupportedHere);
      expect(step(PushState.on, null), PushNudgeStep.none);
    });

    test('a browser: enable, then the site permission when refused', () {
      for (final ua in [androidChrome, windowsChrome]) {
        expect(step(PushState.off, facts(ua, touch: 0)), PushNudgeStep.enable);
        expect(step(PushState.blocked, facts(ua, touch: 0)),
            PushNudgeStep.reallowBrowser);
      }
    });

    test('a browser with no push at all keeps the old line', () {
      expect(step(PushState.unsupported, facts(windowsChrome, touch: 0)),
          PushNudgeStep.unsupportedBrowser);
      // A Mac is not an iPhone: no install steps there.
      expect(step(PushState.unsupported, facts(macSafari, touch: 0)),
          PushNudgeStep.unsupportedBrowser);
    });
  });

  group('analytics dimensions are a closed set', () {
    test('platform', () {
      expect(PushNudgeRules.platform(null), PushNudgePlatform.androidApp);
      expect(PushNudgeRules.platform(facts(iphoneSafari)),
          PushNudgePlatform.iosSafari);
      expect(
          PushNudgeRules.platform(
              facts(iphoneSafari, displayModeStandalone: true)),
          PushNudgePlatform.iosStandalone);
      expect(PushNudgeRules.platform(facts(chromeIos)),
          PushNudgePlatform.iosOther);
      expect(PushNudgeRules.platform(facts(androidChrome)),
          PushNudgePlatform.web);
    });

    test('the props carry only the enum values', () {
      final props = analyticsFunnelProps(
          channel: 'web',
          platform: PushNudgePlatform.iosSafari,
          step: PushNudgeStep.install);
      expect(props, {
        'channel': 'web',
        'platform': 'ios-safari',
        'step': 'install',
      });
      expect(
          PushNudgePlatform.values.map((p) => p.analyticsValue).toSet(),
          {'android-app', 'ios-safari', 'ios-standalone', 'ios-other', 'web'});
      expect(
          PushNudgeStep.values.map((s) => s.analyticsValue).toSet(),
          {'none', 'enable', 'install', 'needs-safari', 'reallow',
              'unsupported'});
    });

    test('the enable outcome reads the RESULTING state', () {
      expect(PushNudgeRules.enableOutcome(PushState.on), 'granted');
      expect(PushNudgeRules.enableOutcome(PushState.blocked), 'denied');
      expect(PushNudgeRules.enableOutcome(PushState.off), 'dismissed');
      expect(PushNudgeRules.enableOutcome(PushState.unsupported),
          'unsupported');
    });
  });
}

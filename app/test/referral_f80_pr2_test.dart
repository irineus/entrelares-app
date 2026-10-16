// F-80 PR 2 — the Android door (Install Referrer) and the Família card
// "Indique uma família", both built dark.
//
// What this file pins:
//   · the Install Referrer reader answers the code `ReferralRules` reads from
//     the platform channel's string, memoises it, and turns every failure
//     into "no code";
//   · the Android e-mail founder: dark, the channel is NEVER asked and
//     nothing is sent; on, the code rides in the sign-up with
//     `referral_channel: 'android'`; a `?ref=` link still wins;
//   · the card: hidden (and `my_referral_code` never asked) while dark,
//     hidden for a viewer, shown for a full member with the landing link,
//     and the share sheet gets the sentence + link while the event carries
//     the channel and never the code.
import 'dart:convert';
import 'dart:io';

import 'package:entrelares_app/screens/family_screen.dart';
import 'package:entrelares_app/services/admin_mode.dart';
import 'package:entrelares_app/services/analytics_service.dart';
import 'package:entrelares_app/services/custody_data_source.dart';
import 'package:entrelares_app/services/install_referrer.dart';
import 'package:entrelares_app/services/sudo_service.dart';
import 'package:entrelares_app/widgets/app_l10n.dart';
import 'package:entrelares_core/entrelares_core.dart';
import 'package:entrelares_db_contracts/models/member.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'calendar_slice_test.dart' show FakeCustodyDataSource;
import 'family_page_test.dart' as fam;
import 'register_test.dart'
    show
        acceptTerms,
        goToFamilyStep,
        pumpRegister,
        source,
        submitButton,
        tapVisible;

const _code = 'ABCDEFGH23';
const _referrer =
    'utm_source=entrelares.app&utm_medium=referral'
    '&utm_campaign=family-referral&ref=$_code';
const _channel = MethodChannel(InstallReferrer.channelName);

/// Fakes the app's own Android channel; returns the call counter.
List<MethodCall> _fakeChannel(Future<Object?> Function(MethodCall) answer) {
  final calls = <MethodCall>[];
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, (call) {
        calls.add(call);
        return answer(call);
      });
  addTearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null),
  );
  return calls;
}

({AnalyticsService service, List<Map<String, dynamic>> payloads})
_recordingAnalytics() {
  final payloads = <Map<String, dynamic>>[];
  final service = AnalyticsService(
    websiteId: 'site-1',
    host: 'https://cloud.umami.is',
    hostname: 'web.entrelares.app',
    client: MockClient((request) async {
      payloads.add(
        (jsonDecode(request.body) as Map<String, dynamic>)['payload']
            as Map<String, dynamic>,
      );
      return http.Response('', 200);
    }),
  );
  return (service: service, payloads: payloads);
}

void main() {
  final l = Localization(AppLanguage.ptBr);

  group('InstallReferrer', () {
    testWidgets('reads the code from the string the channel answers, once', (
      tester,
    ) async {
      final calls = _fakeChannel((_) async => _referrer);
      final reader = InstallReferrer();

      expect(await reader.code(), _code);
      expect(await reader.code(), _code);
      expect(calls, hasLength(1));
      expect(calls.single.method, InstallReferrer.readMethod);
    });

    testWidgets('an organic install is no code', (tester) async {
      _fakeChannel((_) async => 'utm_source=google-play&utm_medium=organic');
      expect(await InstallReferrer().code(), isNull);
    });

    testWidgets('a platform error or a null answer is no code — never throws', (
      tester,
    ) async {
      _fakeChannel((_) async => throw PlatformException(code: 'x'));
      expect(await InstallReferrer().code(), isNull);
      _fakeChannel((_) async => null);
      expect(await InstallReferrer().code(), isNull);
    });

    testWidgets('no handler at all (web, a desktop host) is no code', (
      tester,
    ) async {
      // The engine's "no handler" answer travels the real event loop.
      expect(await tester.runAsync(() => InstallReferrer().code()), isNull);
    });

    test('a reader exists on Android only', () {
      try {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        expect(InstallReferrer.forThisPlatform(), isNotNull);
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        expect(InstallReferrer.forThisPlatform(), isNull);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  test('mirror — the Android side answers on the same channel and method, '
      'registered and built with the Google client', () {
    const kotlin = 'android/app/src/main/kotlin/com/entrelares/entrelares_app';
    final channel = File(
      '$kotlin/InstallReferrerChannel.kt',
    ).readAsStringSync();
    expect(
      channel,
      contains('const val CHANNEL = "${InstallReferrer.channelName}"'),
    );
    expect(
      channel,
      contains('const val READ = "${InstallReferrer.readMethod}"'),
    );
    expect(
      File('$kotlin/MainActivity.kt').readAsStringSync(),
      contains('InstallReferrerChannel(this).register('),
    );
    expect(
      File('android/app/build.gradle.kts').readAsStringSync(),
      contains('implementation("com.android.installreferrer:installreferrer:'),
    );
  });

  group('Android e-mail founder', () {
    Future<void> signUpFounder(WidgetTester tester) async {
      await goToFamilyStep(tester);
      await tester.enterText(
        find.widgetWithText(TextField, l[K.registerFamilyName]),
        'Souza',
      );
      await tapVisible(tester, find.widgetWithText(ChoiceChip, 'Mãe'));
      await acceptTerms(tester);
      await tapVisible(tester, submitButton(l));
      await tester.pumpAndSettle();
    }

    testWidgets('dark: no code is sent — the referrer is read once, for the '
        'source only (T-101)', (
      tester,
    ) async {
      final calls = _fakeChannel((_) async => _referrer);
      final ds = source(); // referralEnabled = false, as in production
      final a = _recordingAnalytics();
      await pumpRegister(
        tester,
        dataSource: ds,
        installReferrer: InstallReferrer(),
        analytics: a.service,
      );
      await signUpFounder(tester);

      expect(ds.referralEnabledFetches, 1);
      // T-101: every Android founder's install says where it came from; the
      // referral CODE still stays home while the module is dark.
      expect(calls, hasLength(1));
      expect(ds.signUps.single['acquisition'], Acquisition.referral);
      expect(ds.signUps.single['referralCode'], isNull);
      expect(ds.signUps.single['referralChannel'], isNull);
      expect(a.payloads.where((p) => p['name'] == 'referral-signup'), isEmpty);
    });

    testWidgets('on: the install code rides with the sign-up as android', (
      tester,
    ) async {
      final calls = _fakeChannel((_) async => _referrer);
      final ds = source()..referralEnabled = true;
      final a = _recordingAnalytics();
      await pumpRegister(
        tester,
        dataSource: ds,
        installReferrer: InstallReferrer(),
        analytics: a.service,
      );
      await signUpFounder(tester);

      expect(calls, hasLength(1));
      expect(ds.signUps.single['referralCode'], _code);
      expect(ds.signUps.single['referralChannel'], 'android');
      final events = a.payloads
          .where((p) => p['name'] == 'referral-signup')
          .toList();
      expect(events.single['data'], {'channel': 'android'});
      expect(jsonEncode(a.payloads), isNot(contains(_code)));
    });

    testWidgets('on, but an organic install: nothing is sent', (tester) async {
      _fakeChannel((_) async => 'utm_source=google-play&utm_medium=organic');
      final ds = source()..referralEnabled = true;
      await pumpRegister(
        tester,
        dataSource: ds,
        installReferrer: InstallReferrer(),
      );
      await signUpFounder(tester);

      expect(ds.signUps.single['referralCode'], isNull);
      expect(ds.signUps.single['referralChannel'], isNull);
    });

    testWidgets('T-101: an ad install says where it came from, dark or on', (
      tester,
    ) async {
      final calls = _fakeChannel(
        (_) async => 'utm_source=meta&utm_campaign=Primeira-Turma',
      );
      final ds = source(); // referral dark
      await pumpRegister(
        tester,
        dataSource: ds,
        installReferrer: InstallReferrer(),
      );
      await signUpFounder(tester);

      expect(calls, hasLength(1));
      expect(
        ds.signUps.single['acquisition'],
        const Acquisition(AcquisitionRules.meta, 'primeira-turma'),
      );
      expect(ds.signUps.single['referralCode'], isNull);
    });

    testWidgets('a ?ref= link wins and the referrer is not read', (
      tester,
    ) async {
      final calls = _fakeChannel((_) async => 'ref=ZZZZZZZZZZ');
      final ds = source()..referralEnabled = true;
      await pumpRegister(
        tester,
        dataSource: ds,
        referralCode: _code,
        installReferrer: InstallReferrer(),
      );
      await signUpFounder(tester);

      expect(calls, isEmpty);
      expect(ds.signUps.single['referralCode'], _code);
      // T-101: the link's code is the source too — Play is not asked.
      expect(ds.signUps.single['acquisition'], Acquisition.referral);
    });
  });

  group('the Família card', () {
    const viewer = Member(
      id: 9,
      fullName: 'Vó Lurdes',
      colorSlot: 1,
      userId: 'u9',
      roleId: 1,
      membershipType: 'viewer',
    );

    Future<({List<String> shared, List<Map<String, dynamic>> payloads})> pump(
      WidgetTester tester,
      FakeCustodyDataSource ds,
    ) async {
      final shared = <String>[];
      final a = _recordingAnalytics();
      await tester.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        AppL10n(
          l: l,
          setLanguage: (_) async {},
          child: MaterialApp(
            home: FamilyScreen(
              dataSource: ds,
              adminMode: AdminMode(),
              sudo: SudoService(ds),
              analytics: a.service,
              onShareReferral: (message) async => shared.add(message),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return (shared: shared, payloads: a.payloads);
    }

    final card = find.byKey(const ValueKey('family-referral-card'));
    // U-61: the card waits for a family that is complete AND active — the
    // fixture's two caregivers plus a plan.
    const planned = OnboardingFacts(hasAnyPlannedDay: true);

    testWidgets('dark: no card, and the code is never asked', (tester) async {
      final ds = fam.source();
      await pump(tester, ds);

      expect(card, findsNothing);
      expect(find.text(l[KApp.famReferralTitle]), findsNothing);
      expect(ds.referralCodeFetches, 0);
    });

    testWidgets('on: the link, the rule and Compartilhar', (tester) async {
      final ds = fam.source(settings: const {'feature.referral': 'true'})
        ..onboardingFacts = planned;
      await pump(tester, ds);

      expect(card, findsOne);
      expect(find.text(l[KApp.famReferralTitle]), findsOne);
      expect(find.text(l[KApp.famReferralRule]), findsOne);
      expect(find.text('https://entrelares.app/i/$_code'), findsOne);
      expect(
        find.descendant(of: card, matching: find.text(l[KApp.commonShare])),
        findsOne,
      );
      expect(ds.referralCodeFetches, 1);
    });

    // U-67: desktop web has no Web Share — the link alone to the clipboard.
    testWidgets('Copiar link puts the link alone on the clipboard',
        (tester) async {
      final ds = fam.source(settings: const {'feature.referral': 'true'})
        ..onboardingFacts = planned;
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));
      await pump(tester, ds);
      await tester.ensureVisible(
          find.byKey(const ValueKey('family-referral-copy')));
      await tester.tap(find.byKey(const ValueKey('family-referral-copy')));
      await tester.pumpAndSettle();
      expect(copied, 'https://entrelares.app/i/$_code');
      expect(find.text(l[K.famLinkCopied]), findsOne);
    });

    testWidgets('a plain member (not the admin) sees it too', (tester) async {
      final ds = fam.source(
        members: const [fam.plain, fam.admin],
        settings: const {'feature.referral': 'true'},
      )..onboardingFacts = planned;
      await pump(tester, ds);
      expect(card, findsOne);
    });

    testWidgets('U-61: a founder alone, or a family with no plan, is not '
        'asked to bring in another family — and the code is never fetched',
        (tester) async {
      // The audit saw "Indique uma família" on a one-member family that had
      // not even invited the co-parent.
      final alone = fam.source(
        members: const [fam.admin],
        settings: const {'feature.referral': 'true'},
      )..onboardingFacts = planned;
      await pump(tester, alone);
      expect(card, findsNothing);
      expect(alone.referralCodeFetches, 0);

      final unplanned = fam.source(settings: const {'feature.referral': 'true'});
      await pump(tester, unplanned);
      expect(card, findsNothing);
      expect(unplanned.referralCodeFetches, 0);
    });

    testWidgets('share: the sentence and the link go to the sheet; the event '
        'carries the channel and never the code', (tester) async {
      final ds = fam.source(settings: const {'feature.referral': 'true'})
        ..onboardingFacts = planned;
      final r = await pump(tester, ds);

      await tester.ensureVisible(card);
      await tester.tap(
        find.descendant(of: card, matching: find.text(l[KApp.commonShare])),
      );
      await tester.pumpAndSettle();

      expect(r.shared, [
        '${l[KApp.famReferralShareText]}\nhttps://entrelares.app/i/$_code',
      ]);
      final events = r.payloads
          .where((p) => p['name'] == 'referral-share')
          .toList();
      expect(events, hasLength(1));
      // The test host is not the web.
      expect(events.single['data'], {'channel': 'android'});
      expect(jsonEncode(r.payloads), isNot(contains(_code)));
    });

    testWidgets('a viewer never sees it, and never asks', (tester) async {
      final ds = fam.source(
        members: const [viewer, fam.admin],
        settings: const {'feature.referral': 'true'},
      );
      await pump(tester, ds);

      expect(card, findsNothing);
      expect(ds.referralCodeFetches, 0);
    });

    testWidgets('the server refusing is no card', (tester) async {
      final ds = fam.source(settings: const {'feature.referral': 'true'})
        ..onboardingFacts = planned
        ..myReferralCode = null;
      await pump(tester, ds);
      expect(card, findsNothing);
    });
  });

  test('the rule sentence types no operator number (U-57)', () {
    for (final language in AppLanguage.values) {
      final text = Localization(language)[KApp.famReferralRule];
      expect(RegExp(r'\d').hasMatch(text), isFalse, reason: text);
      for (final word in ['trinta', 'thirty', 'doze', 'twelve']) {
        expect(text.toLowerCase(), isNot(contains(word)), reason: text);
      }
    }
  });
}

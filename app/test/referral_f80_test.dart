// F-80 PR 1 — the referral code on the client, built dark.
//
// What this file pins:
//   · the founder's e-mail sign-up carries the `?ref=` code ONLY when the
//     server said `feature.referral` is on — dark, nothing leaves;
//   · the invitee never asks and never sends (they found no family);
//   · `referral-signup` carries the channel and never the code;
//   · the Google founder tells `main.dart` the family was founded, and the
//     claim branch never does.
import 'dart:convert';

import 'package:entrelares_app/services/analytics_service.dart';
import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'calendar_slice_test.dart' show FakeCustodyDataSource;
import 'oauth_onboarding_test.dart' show pumpOnboarding, prefsWith, pt;
import 'register_test.dart'
    show
        acceptTerms,
        goToFamilyStep,
        invite,
        pumpRegister,
        source,
        submitButton,
        tapVisible,
        validToken;

const _code = 'ABCDEFGH23';

void main() {
  final l = Localization(AppLanguage.ptBr);

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

  ({AnalyticsService service, List<Map<String, dynamic>> payloads})
  recordingAnalytics() {
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

  group('founder e-mail sign-up', () {
    testWidgets('dark: the code is never sent and no event fires', (
      tester,
    ) async {
      final ds = source(); // referralEnabled = false, as in production
      final a = recordingAnalytics();
      await pumpRegister(
        tester,
        dataSource: ds,
        referralCode: _code,
        analytics: a.service,
      );
      await signUpFounder(tester);

      expect(ds.referralEnabledFetches, 1);
      expect(ds.signUps.single['referralCode'], isNull);
      expect(a.payloads.where((p) => p['name'] == 'referral-signup'), isEmpty);
      expect(jsonEncode(a.payloads), isNot(contains(_code)));
    });

    testWidgets('on: the code rides with the sign-up, the event carries the '
        'channel and never the code', (tester) async {
      final ds = source()..referralEnabled = true;
      final a = recordingAnalytics();
      await pumpRegister(
        tester,
        dataSource: ds,
        referralCode: _code,
        analytics: a.service,
      );
      await signUpFounder(tester);

      expect(ds.signUps.single['referralCode'], _code);
      final events = a.payloads
          .where((p) => p['name'] == 'referral-signup')
          .toList();
      expect(events, hasLength(1));
      // The test host is not the web: the channel is the server's word for it.
      expect(events.single['data'], {'channel': 'android'});
      expect(jsonEncode(a.payloads), isNot(contains(_code)));
      expect(find.text(l[K.registerConfirmEmailTitle]), findsOne);
    });

    testWidgets('no code: nothing is asked', (tester) async {
      final ds = source()..referralEnabled = true;
      await pumpRegister(tester, dataSource: ds);
      await signUpFounder(tester);

      expect(ds.referralEnabledFetches, 0);
      expect(ds.signUps.single['referralCode'], isNull);
    });
  });

  testWidgets('the invitee never asks — an invitation founds no family', (
    tester,
  ) async {
    final ds = source()
      ..inviteInfo = invite
      ..referralEnabled = true;
    await pumpRegister(
      tester,
      dataSource: ds,
      inviteToken: validToken,
      referralCode: _code,
    );

    expect(ds.referralEnabledFetches, 0);
  });

  group('Google onboarding', () {
    Future<void> completeFounder(WidgetTester tester) async {
      await tester.enterText(
        find.widgetWithText(TextField, pt[K.registerFamilyName]),
        'Família Teste',
      );
      await tester.tap(find.text('Mãe'));
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(FilledButton, pt[KApp.onbFounderCta]),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('the founder branch reports the family as founded, before '
        'completing', (tester) async {
      final order = <String>[];
      final ds = FakeCustodyDataSource(members: const [], days: const [])
        ..displayName = 'Ana do Google';
      await pumpOnboarding(
        tester,
        ds,
        await prefsWith({}),
        onFamilyFounded: () => order.add('founded'),
        onCompleted: () async => order.add('completed'),
      );
      await completeFounder(tester);

      expect(order, ['founded', 'completed']);
    });

    testWidgets('a refused onboarding founds nothing', (tester) async {
      var founded = false;
      final ds = FakeCustodyDataSource(members: const [], days: const [])
        ..displayName = 'Ana do Google'
        ..onboardingRefusalMessage = 'Recusado.';
      await pumpOnboarding(
        tester,
        ds,
        await prefsWith({}),
        onFamilyFounded: () => founded = true,
      );
      await completeFounder(tester);

      expect(founded, isFalse);
    });
  });
}

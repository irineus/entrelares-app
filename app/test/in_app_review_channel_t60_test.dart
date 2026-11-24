// T-60 — In-App Review left the `in_app_review` plugin (it applied the Kotlin
// Gradle Plugin, which future Flutter versions refuse) for the app's own
// Android channel, `InAppReviewChannel.kt`. This suite holds the Dart half of
// that contract: the channel name and method names `MainActivity` answers on,
// "available" only on a clear yes, and a refused flow surfacing as an error
// that ReviewPromptService (review_prompt_f73_test) already swallows.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:entrelares_app/services/review_prompt_service.dart';

const _channel = MethodChannel(PlayInAppReviewer.channelName);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <String>[];

  void answer(Object? Function(MethodCall call) reply) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      calls.add(call.method);
      return reply(call);
    });
  }

  setUp(calls.clear);
  tearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, null));

  test('the names the Kotlin side answers on', () {
    expect(PlayInAppReviewer.channelName, 'app.entrelares/in_app_review');
    expect(PlayInAppReviewer.isAvailableMethod, 'isAvailable');
    expect(PlayInAppReviewer.requestReviewMethod, 'requestReview');
  });

  test('available only when Play says yes', () async {
    answer((_) => true);
    expect(await PlayInAppReviewer().isAvailable(), isTrue);
    answer((_) => false);
    expect(await PlayInAppReviewer().isAvailable(), isFalse);
    answer((_) => null);
    expect(await PlayInAppReviewer().isAvailable(), isFalse);
    expect(calls, everyElement('isAvailable'));
  });

  test('no channel, or an error, reads as not available — never a throw',
      () async {
    // No handler at all: what a platform without the channel answers.
    expect(await PlayInAppReviewer().isAvailable(), isFalse);
    answer((_) => throw PlatformException(code: 'boom'));
    expect(await PlayInAppReviewer().isAvailable(), isFalse);
  });

  test('requestReview asks for the flow and completes on Play\'s null',
      () async {
    answer((_) => null);
    await PlayInAppReviewer().requestReview();
    expect(calls, ['requestReview']);
  });

  test('a flow Play refused surfaces as an error for the service to swallow',
      () async {
    answer((_) => throw PlatformException(code: 'unavailable'));
    await expectLater(
        PlayInAppReviewer().requestReview(), throwsA(isA<PlatformException>()));
  });
}

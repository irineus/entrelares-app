// The web channel's frame. U-28's lesson applies here more than anywhere: the
// requirement is about ARRANGEMENT, so the test measures geometry — a cap that
// silently stopped binding would look identical to a suite that only asserts
// what is present.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:entrelares_app/theme/tokens.dart';
import 'package:entrelares_app/widgets/app_width_cap.dart';

void main() {
  Future<Rect> pumpAt(WidgetTester tester, Size window) async {
    await tester.binding.setSurfaceSize(window);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(
      home: AppWidthCap(child: SizedBox.expand(key: Key('content'))),
    ));
    await tester.pumpAndSettle();
    return tester.getRect(find.byKey(const Key('content')));
  }

  testWidgets('a wide window gets a centred column, not an edge-to-edge app',
      (tester) async {
    final content = await pumpAt(tester, const Size(1400, 900));

    expect(content.width, maxAppWidth,
        reason: 'the Blazor PWA never drew a page edge to edge');
    expect(content.center.dx, 700, reason: 'and it was centred');
  });

  testWidgets('a phone never notices the cap', (tester) async {
    // Which is why this changes nothing on the store channel.
    final content = await pumpAt(tester, const Size(390, 844));

    expect(content.width, 390);
  });

  testWidgets('exactly at the cap nothing shifts', (tester) async {
    final content = await pumpAt(tester, const Size(maxAppWidth, 800));

    expect(content.width, maxAppWidth);
    expect(content.left, 0);
  });
}

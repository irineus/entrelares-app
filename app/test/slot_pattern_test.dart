// U-27 — the slot texture and the swapped day's dashed border.
//
// The `hitTest` cases are not theory: the first version of these painters left
// `CustomPainter.hitTest` at its default, and `RenderCustomPaint.hitTestSelf`
// reads `painter.hitTest(position) ?? true` — so the decoration ABSORBED every
// press on the day it decorated. On a swapped day, whose border is drawn on
// top of the whole cell, that made the day untappable.
import 'package:entrelares_app/theme/slot_pattern.dart';
import 'package:entrelares_app/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('neither painter takes a tap', () {
    expect(
        const SlotPatternPainter(
                SlotPattern.diagonalHatch, Color(0xFF000000))
            .hitTest(Offset.zero),
        isFalse);
    expect(
        const DashedBorderPainter(color: Color(0xFF000000), radius: 8)
            .hitTest(Offset.zero),
        isFalse);
  });

  testWidgets('a cell wearing both painters still receives the tap',
      (tester) async {
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 48,
            height: 48,
            child: InkWell(
              onTap: () => taps++,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CustomPaint(
                    painter: const SlotPatternPainter(
                        SlotPattern.dots, Color(0xFF888888)),
                    child: const SizedBox.expand(),
                  ),
                  CustomPaint(
                    painter: const DashedBorderPainter(
                        color: Color(0xFF888888), radius: 8),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.byType(InkWell));
    expect(taps, 1);
  });

  testWidgets('the swatch renders every pattern without overflowing',
      (tester) async {
    for (final slot in AppTokens.light.slots) {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: Center(child: SlotSwatch(slot: slot))),
      ));
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SlotSwatch(slot: AppTokens.light.swapped, dashedBorder: true),
        ),
      ),
    ));
    expect(tester.takeException(), isNull);
  });

  test('shouldRepaint reacts to the values that change the picture', () {
    const a = SlotPatternPainter(SlotPattern.dots, Color(0xFF111111));
    expect(
        a.shouldRepaint(
            const SlotPatternPainter(SlotPattern.dots, Color(0xFF222222))),
        isTrue);
    expect(a.shouldRepaint(a), isFalse);
  });
}

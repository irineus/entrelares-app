// U-28 QA — the calendar has to FIT on a phone.
//
// The owner found the grid scrolling twice: first because the chrome around it
// had grown, then again with the admin strip on. The cell height is a RANGE
// now — the grid spends whatever the screen gives it, divided by the weeks the
// month really has — so the question this file answers is the one that still
// matters: in the WORST month, is there room left for the cell to reach its
// floor without the grid scrolling?
//
// Scrolling a calendar is not a small annoyance. The whole point of the screen
// is seeing the month at once; a month you have to scroll is a list.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'calendar_slice_test.dart' as cal;

/// Mirrors `_dayCellMinHeight` and `_daySpacing` in `calendar_screen.dart`.
/// Duplicated on purpose: the test asserts against the numbers a reader can
/// see, so changing either shows up here as a failure to think about.
const double _cellFloor = 50;
const double _spacing = 3;

/// The worst month the calendar ever has to draw: 31 days starting on a
/// Saturday, which is six rows.
const int _worstRows = 6;

Future<void> _pump(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(cal.app(cal.FakeCustodyDataSource(
    members: [cal.ana, cal.bruno],
    days: const [],
  )));
  await tester.pumpAndSettle();
}

/// The grid's OWN viewport — `find.byType(Viewport).first` picks the legend's,
/// and `.byType(GridView).first` is needed because the PageView keeps
/// neighbouring months alive.
Size _gridViewport(WidgetTester tester) => tester.getSize(find
    .ancestor(of: find.byType(GridView).first, matching: find.byType(Viewport))
    .first);

void main() {
  // 360x740 is the small end of what the product actually meets; the owner's
  // own device reports ~339x755 logical pixels.
  for (final size in [const Size(360, 740), const Size(340, 700)]) {
    testWidgets('a six-week month fits at ${size.width}x${size.height}',
        (tester) async {
      await _pump(tester, size);
      final viewport = _gridViewport(tester);

      // What six weeks need at the floor, plus the weekday initials, the list
      // padding, the admin strip the owner had ON when he found this
      // scrolling, and a second legend row for a four-carer family.
      const chrome = 30.0 + 40.0 + 26.0;
      final needed =
          _worstRows * _cellFloor + (_worstRows - 1) * _spacing + chrome;

      expect(needed, lessThanOrEqualTo(viewport.height),
          reason: 'a six-week month needs $needed and the viewport gives '
              '${viewport.height} — the cell would be pushed under its floor, '
              'or the calendar would scroll');
    });
  }

  testWidgets('the grid never overflows its own viewport', (tester) async {
    await _pump(tester, const Size(360, 740));
    expect(tester.getSize(find.byType(GridView).first).height,
        lessThanOrEqualTo(_gridViewport(tester).height));
  });

  testWidgets('a taller screen gives the days more room, not dead space',
      (tester) async {
    // The point of making the height a range: with a fixed cell a five-week
    // month left a band of nothing under the grid on anything but the smallest
    // phone, which is what the owner read as "this is the minimum".
    // 640 keeps the cell below its ceiling; by 740 a six-week month has
    // already reached it, so comparing 740 with anything taller compares two
    // clamped values and proves nothing.
    await _pump(tester, const Size(360, 640));
    final short = tester.getSize(find.byType(GridView).first).height;

    await _pump(tester, const Size(360, 740));
    final tall = tester.getSize(find.byType(GridView).first).height;

    expect(tall, greaterThan(short),
        reason: 'the grid is sized to the screen now — the same month on a '
            'taller phone must spend the extra height on the days');
  });
}

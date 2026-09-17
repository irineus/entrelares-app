// U-39 — the day cell's two typographic steps, as numbers.
//
// The widget half lives in `calendar_fits_u28_test`; this file pins the
// arithmetic the grid decides with: what each step needs, where the
// comfortable step starts at a given text scale, when the time line alone
// steps down for a cell too narrow for it, and how far the compact step
// follows the reader's scale at the floor before it would overflow.
import 'package:entrelares_app/theme/tokens.dart';
import 'package:flutter_test/flutter_test.dart';

/// A time that is never the binding constraint — the height tests.
double _narrow(double fontSize) => 0;

/// A time whose width is a fixed multiple of its font size, like a real
/// glyph run: "18:00" in Inter is ~2.7 em, "12:00 PM" ~4.1 em.
double Function(double) _em(double em) => (fontSize) => fontSize * em;

DayCellType _resolve(double height, double scale,
        {double width = 1000, double Function(double) time = _narrow}) =>
    DayCellType.resolve(
        width: width, height: height, scale: scale, timeWidth: time);

void main() {
  group('needs', () {
    test('the compact step is exactly the U-28 floor at 1.0×', () {
      // 12 + 2 + 18 + 2 + max(9, 11) inside the 2.5 dp today ring.
      expect(DayCellType.compact.needs(1.0), 50);
    });

    test('the comfortable step is 60 dp at 1.0×, not the card\'s 58', () {
      // 14 + 2 + 24 + 2 + max(11, 13) + 5 — the card counted the 11 px time
      // as the last line; the 13 dp mark that replaces it is taller and does
      // not scale.
      expect(DayCellType.comfortable.needs(1.0), 60);
    });

    test('the mark, not the time, is the binding line until the text outgrows it',
        () {
      // Compact: 9 px × 1.2 = 10.8 < 11 → the icon still sets the last line.
      expect(DayCellType.compact.needs(1.2), 12 * 1.2 + 4 + 18 + 11 + 5);
      // Compact: 9 px × 1.3 = 11.7 > 11 → the time does.
      expect(DayCellType.compact.needs(1.3),
          closeTo(12 * 1.3 + 4 + 18 + 9 * 1.3 + 5, 1e-9));
    });

    test('the comfortable step fits the ceiling with large text', () {
      expect(DayCellType.comfortable.needs(1.3), lessThanOrEqualTo(76));
    });
  });

  group('forHeight', () {
    test('comfortable from the height it needs, compact below it', () {
      expect(DayCellType.forHeight(60, 1.0), DayCellType.comfortable);
      expect(DayCellType.forHeight(59.9, 1.0), DayCellType.compact);
      expect(DayCellType.forHeight(76, 1.0), DayCellType.comfortable);
      expect(DayCellType.forHeight(50, 1.0), DayCellType.compact);
    });

    test('the threshold moves with the reader\'s scale', () {
      // 60 dp holds the comfortable step at 1.0× and not at 1.3×.
      expect(DayCellType.forHeight(60, 1.3), DayCellType.compact);
      expect(DayCellType.forHeight(76, 1.3), DayCellType.comfortable);
    });
  });

  group('resolve', () {
    test('a generous cell is the preset itself, at the reader\'s scale', () {
      final r = _resolve(76, 1.3);
      expect(r.isComfortable, isTrue);
      expect(r.time, DayCellType.comfortable.time);
      expect(r.textScaleCap, 1.3);
      final c = _resolve(55, 1.0);
      expect(c.isComfortable, isFalse);
      expect(c.textScaleCap, 1.0);
    });

    test('a time too wide for the cell steps down ALONE', () {
      // 46 dp wide → 41 inside the ring. "12:00 PM" at 11 px ≈ 45 px: the
      // time keeps 9 px (≈ 37, fits); number and avatar stay comfortable.
      final en = _resolve(76, 1.0, width: 46, time: _em(4.1));
      expect(en.isComfortable, isTrue);
      expect(en.number, DayCellType.comfortable.number);
      expect(en.avatarRadius, DayCellType.comfortable.avatarRadius);
      expect(en.time, DayCellType.compact.time);
      expect(en.textScaleCap, 1.0);
      // "18:00" at 11 px ≈ 30 px: the whole comfortable step.
      final pt = _resolve(76, 1.0, width: 46, time: _em(2.7));
      expect(pt, DayCellType.comfortable._copyWithCap(1.0));
      // The same "18:00" at 1.3× ≈ 39 px: still inside 41.
      expect(_resolve(76, 1.3, width: 46, time: _em(2.7)).time, 11);
      // But on a 340 dp phone (43 dp cell, 38 inside) it is not: the time
      // steps down, and at 9 px × 1.3 ≈ 31.6 it fits — the reader's scale
      // reaches the text.
      final narrow = _resolve(76, 1.3, width: 43, time: _em(2.7));
      expect(narrow.isComfortable, isTrue);
      expect(narrow.time, 9);
      expect(narrow.textScaleCap, 1.3);
    });

    test('the cap is the smaller of the height and the width bounds', () {
      // 43 dp cell, 38 inside; "18:00" at 9 px = 24.3 → the width allows
      // 38 / 24.3 = 1.56×; the height at 50 dp allows 1.0 — the floor wins.
      final floor = _resolve(50, 1.3, width: 43, time: _em(2.7));
      expect(floor.textScaleCap, 1.0);
      // 76 dp, a cell so narrow (30 dp, 25 inside) that even the compact
      // time is the bound: 25 / 24.3 = 1.03×.
      final thin = _resolve(76, 1.3, width: 30, time: _em(2.7));
      expect(thin.time, 9);
      expect(thin.textScaleCap, closeTo(25 / 24.3, 1e-9));
    });
  });

  group('heightCap', () {
    test('is the reader\'s scale wherever the step fits', () {
      expect(DayCellType.comfortable.heightCap(76, 1.3), 1.3);
      expect(DayCellType.compact.heightCap(60, 1.3), 1.3);
      expect(DayCellType.compact.heightCap(50, 1.0), 1.0);
    });

    test('at the floor the compact step has no room to grow', () {
      // 50 dp is exactly what the compact step needs at 1.0× — the mark line
      // does not shrink, so the number cannot grow at all.
      expect(DayCellType.compact.heightCap(50, 1.3), 1.0);
    });

    test('between the floor and the fit, the cap is what the cell holds', () {
      // 52 dp: 2 dp to spend on the number alone (9 × 1.167 = 10.5 < 11, the
      // mark still binds): s = 14 / 12.
      final cap = DayCellType.compact.heightCap(52, 1.3);
      expect(cap, closeTo(14 / 12, 1e-9));
      expect(DayCellType.compact.needs(cap), lessThanOrEqualTo(52 + 1e-9));
      // 54 dp: the number alone would allow 1.333, but 9 × 1.333 = 12 > 11,
      // so both lines share the room: s = 27 / 21.
      final cap54 = DayCellType.compact.heightCap(54, 1.3);
      expect(cap54, closeTo(27 / 21, 1e-9));
      expect(DayCellType.compact.needs(cap54), closeTo(54, 1e-9));
    });

    test('once the time outgrows the mark, both lines share the room', () {
      // Comfortable at 68 dp, reader at 1.5×: needs 14×1.5 + 28 + 16.5 + 5
      // = 70.5 > 68. Fixed part 33; markBound = (68 − 33 − 13) / 14 = 1.571,
      // but 11 × 1.571 = 17.3 > 13, so both lines grow: s = 35 / 25 = 1.4.
      final cap = DayCellType.comfortable.heightCap(68, 1.5);
      expect(cap, closeTo(1.4, 1e-9));
      expect(DayCellType.comfortable.needs(cap), closeTo(68, 1e-9));
    });

    test('never below the design size, never above the reader', () {
      expect(DayCellType.compact.heightCap(40, 1.3), 1.0);
      expect(DayCellType.compact.heightCap(50, 0.9), 0.9);
    });
  });

  group('widthCap', () {
    test('the width binds when the time would outgrow the cell', () {
      // 43 dp cell, 38 inside; "18:00" at 11 px = 29.7 → fits up to
      // 38 / 29.7 = 1.28×, under the reader's 1.3.
      final c = DayCellType.comfortable.widthCap(43, 1.3, _em(2.7));
      expect(c, closeTo(38 / 29.7, 1e-9));
      expect(_em(2.7)(11 * c), lessThanOrEqualTo(38 + 1e-9));
    });

    test('never below the design size, even where the width is short', () {
      // A cell narrower than the time at 9 px: the floor holds (the text
      // clips rather than shrinks — U-28 measured the floor to fit).
      expect(DayCellType.compact.widthCap(20, 1.3, _em(2.7)), 1.0);
    });
  });
}

extension on DayCellType {
  /// The preset as [DayCellType.resolve] returns it for a cell it fits.
  DayCellType _copyWithCap(double cap) => DayCellType.resolve(
      width: 1000, height: 1000, scale: cap, timeWidth: _narrow);
}

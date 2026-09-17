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
import 'package:entrelares_app/screens/calendar_screen.dart';
import 'package:entrelares_app/services/admin_mode.dart';
import 'package:entrelares_app/theme/app_theme.dart';
import 'package:entrelares_app/theme/tokens.dart';
import 'package:entrelares_app/widgets/app_l10n.dart';
import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'calendar_slice_test.dart' as cal;
import 'frozen_day_test.dart' as frz;

/// Mirrors `_dayCellMinHeight`, `_dayCellMaxHeight` and `_daySpacing` in
/// `calendar_screen.dart`. Duplicated on purpose: the test asserts against
/// the numbers a reader can see, so changing any shows up here as a failure
/// to think about.
const double _cellFloor = 50;
const double _cellCeiling = 76;
const double _spacing = 3;

/// The worst month the calendar ever has to draw: 31 days starting on a
/// Saturday, which is six rows.
const int _worstRows = 6;

/// U-39 — a month with the two things a cell can carry under the avatar: a
/// handoff time on today's cell (the one that also wears the widest ring) and
/// a frozen mark on the 1st. Off by default so the U-28 tests keep pumping
/// the empty month they were written against.
Future<void> _pump(WidgetTester tester, Size size,
    {double scale = 1.0,
    bool withMarks = false,
    AppLanguage language = AppLanguage.ptBr}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final ds = cal.FakeCustodyDataSource(
    members: [cal.ana, cal.bruno],
    days: withMarks
        ? [cal.row(1, cal.dayOfMonth(cal.today.day), 1, handoffTime: '18:00')]
        : const [],
  );
  if (withMarks) ds.frozenRequests = [frz.swapReq(10, cal.dayOfMonth(1))];
  // The product's own theme, so the cell's text names Inter — the family the
  // U-39 group loads — rather than the host's fallback font. `cal.app` runs
  // on the bare MaterialApp for the slice tests, which measure no text.
  await tester.pumpWidget(MediaQuery(
    data: MediaQueryData(size: size, textScaler: TextScaler.linear(scale)),
    child: AppL10n(
      l: Localization(language),
      setLanguage: (_) async {},
      child: MaterialApp(
        theme: AppTheme.light,
        home: CalendarScreen(dataSource: ds, adminMode: AdminMode()),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

/// The grid's own cells, marks and texts — the today card above the grid
/// prints the same time, and the legend draws its own avatars.
Finder _inGrid(Finder matching) =>
    find.descendant(of: find.byType(GridView).first, matching: matching);

double _cellHeight(WidgetTester tester) =>
    tester.getSize(_inGrid(find.byType(InkWell)).first).height;

/// The step the grid painted, read from the handoff time's font size — the
/// number under test, not a proxy for it.
double _timeFontSize(WidgetTester tester, [String time = '18:00']) =>
    tester.widget<Text>(_inGrid(find.text(time))).style!.fontSize!;

/// The day number's font size — today's, the cell every month has.
double _numberFontSize(WidgetTester tester) =>
    tester
        .widget<Text>(_inGrid(find.text('${cal.today.day}')))
        .style!
        .fontSize!;

/// What the text under the cell's clamp is actually scaled by.
double _paintedScaleOf(WidgetTester tester, Finder text) =>
    MediaQuery.textScalerOf(tester.element(_inGrid(text).first)).scale(1);

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

  // U-39 — the type inside the cell follows the height the range produced.
  // The floor above is what the COMPACT step was measured into; this group
  // holds the ceiling: a 76 dp cell paints the comfortable step, at large
  // text too, without overflowing, and a cell at the floor stays as U-28
  // drew it.
  group('U-39 typography steps', () {
    // The step is chosen by MEASURING the time's width in the reader's
    // language, and the test host's fallback font draws every glyph as a
    // square — "18:00" at 9 px comes out 45 px wide, wider than the cell, so
    // under it no step ever fits and the compact one wraps. The grid is
    // measured with the font the product ships, the U-41 technique.
    setUpAll(() async {
      final inter = FontLoader('Inter')
        ..addFont(rootBundle.load('assets/fonts/Inter-Regular.ttf'))
        ..addFont(rootBundle.load('assets/fonts/Inter-Medium.ttf'));
      await inter.load();
    });

    test('the compact step is what the floor was measured for', () {
      // The U-28 arithmetic, now readable from the step itself: number,
      // avatar, the mark and both gaps inside the today ring.
      expect(DayCellType.compact.needs(1.0), lessThanOrEqualTo(_cellFloor));
      // And the ceiling holds the comfortable step at 1.3× — the promise the
      // widget tests below measure on a real grid.
      expect(DayCellType.comfortable.needs(1.3),
          lessThanOrEqualTo(_cellCeiling));
    });

    testWidgets('a 76 dp cell paints the comfortable step', (tester) async {
      await _pump(tester, const Size(360, 740), withMarks: true);
      expect(_cellHeight(tester), _cellCeiling,
          reason: 'this month at 360x740 no longer reaches the ceiling — '
              'pick a size that does, the step under test is the ceiling\'s');

      expect(_timeFontSize(tester), DayCellType.comfortable.time);
      expect(_timeFontSize(tester), greaterThanOrEqualTo(11),
          reason: 'the card\'s acceptance: on a 76 dp cell the handoff time '
              'is at least 11 px');
      expect(
          tester
              .widget<DayCellAvatar>(_inGrid(find.byType(DayCellAvatar)).first)
              .radius,
          DayCellType.comfortable.avatarRadius);
      expect(
          tester
              .widget<Icon>(_inGrid(find.byIcon(Icons.notifications_active)))
              .size,
          DayCellType.comfortable.mark);
      expect(tester.takeException(), isNull);
    });

    testWidgets('at 1.3× the 76 dp cell keeps the comfortable step, unclamped',
        (tester) async {
      await _pump(tester, const Size(360, 740), scale: 1.3, withMarks: true);
      expect(_cellHeight(tester), _cellCeiling);
      expect(_timeFontSize(tester), DayCellType.comfortable.time);
      // The clamp is a no-op here: the reader's scale reaches the text.
      expect(_paintedScaleOf(tester, find.text('18:00')), closeTo(1.3, 1e-9));
      expect(tester.takeException(), isNull,
          reason: 'the comfortable step overflowed a 76 dp cell at 1.3×');
    });

    testWidgets(
        'in English on a phone the time alone keeps the compact size — '
        '"12:00 PM" at 11 px does not fit the cell', (tester) async {
      await _pump(tester, const Size(360, 740),
          withMarks: true, language: AppLanguage.en);
      expect(_cellHeight(tester), _cellCeiling);

      // The height affords the comfortable step: number and avatar take it.
      expect(_numberFontSize(tester), DayCellType.comfortable.number);
      expect(
          tester
              .widget<DayCellAvatar>(_inGrid(find.byType(DayCellAvatar)).first)
              .radius,
          DayCellType.comfortable.avatarRadius);
      // The width does not afford its time: the widest English time is
      // measured, not counted, and the line steps down alone (owner,
      // 16/09/2026).
      expect(_timeFontSize(tester, '6:00 PM'), DayCellType.compact.time);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a cell near the floor paints the compact step, unchanged',
        (tester) async {
      // 540 dp tall: a five-week month lands around 55 dp, a six-week one
      // on the floor — compact either way.
      await _pump(tester, const Size(360, 540), withMarks: true);
      expect(_cellHeight(tester), lessThan(DayCellType.comfortable.needs(1)));

      expect(_timeFontSize(tester), DayCellType.compact.time);
      expect(
          tester
              .widget<DayCellAvatar>(_inGrid(find.byType(DayCellAvatar)).first)
              .radius,
          DayCellType.compact.avatarRadius);
      expect(
          tester
              .widget<Icon>(_inGrid(find.byIcon(Icons.notifications_active)))
              .size,
          DayCellType.compact.mark);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'at the floor with 1.3× text the cell honours what it can hold, '
        'and nothing overflows', (tester) async {
      // Short enough that the range clamps at its floor even at 1.3×.
      await _pump(tester, const Size(360, 480), scale: 1.3, withMarks: true);
      expect(_cellHeight(tester), _cellFloor,
          reason: 'the case under test is the floor; pick a shorter surface');

      expect(_timeFontSize(tester), DayCellType.compact.time);
      // 50 dp is exactly the compact step at 1.0× (the mark does not shrink),
      // so the cell's texts render at the design size — never smaller.
      final painted = _paintedScaleOf(tester, find.text('18:00'));
      expect(painted, closeTo(1.0, 1e-9));
      expect(painted, DayCellType.compact.heightCap(_cellFloor, 1.3));
      expect(tester.takeException(), isNull,
          reason: 'the compact step overflowed the floor at 1.3× — the clamp '
              'is not reaching the cell\'s texts');
    });
  });
}

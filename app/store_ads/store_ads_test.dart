// T-102 — the ad kit of the first real-cohort campaign (L-31), rendered from
// the app's REAL widgets with T-97's fictional demo family, in PT-BR.
//
// ON DEMAND, NEVER IN CI: like `store_screenshots/`, this directory sits
// outside `test/`, which is the only one the CI's bare `flutter test`
// discovers. Regenerate every image with
//
//     cd app && fvm flutter test store_ads/
//
// and they land in `store/ads/img/<angle>-<network>-<W>x<H>.png` (three
// angles × the six placement sizes) plus the two closing cards the video
// script uses, `store/ads/video/frames/fim-<W>x<H>.png`. Then
// `bash store/ads/render_video.sh` cuts the two videos. store/ads/README.md
// says which file goes where.
//
// Every word is a claim about the product (S-15): the three angles show FREE
// screens (two caregivers, the calendar, a swap — no Premium module), the
// tone is neutral (never "ex", never a side), no price, no competitor, no
// number an operator can change (U-57), no emoji (U-31).
import 'dart:io';

import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test/calendar_slice_test.dart' show FakeCustodyDataSource;
import '../store_screenshots/demo_family.dart';
import '../store_screenshots/store_frame.dart' show capture, loadBundleFonts;
import 'ad_frame.dart';

/// One angle of the campaign: its words and how to reach its screen.
class Angle {
  final String name;
  final AdWords words;
  final FakeCustodyDataSource Function(DemoTexts t) source;
  final Future<void> Function(WidgetTester tester, Localization l)? interact;

  const Angle(this.name, this.words, {required this.source, this.interact});
}

/// The festas: Ana has the 24th and the 1st, Bruno the 25th and the 31st —
/// the alternation many families write down, painted by the plan's own
/// transitions (`plan(carerOf:)`).
int? festasCarer(DateTime d) {
  if (d.month == 12 && (d.day == 24)) return ana.id;
  if (d.month == 12 && (d.day == 25 || d.day == 31)) return bruno.id;
  if (d.month == 1 && d.day == 1) return ana.id;
  return null;
}

/// Steps the calendar forward to [month] (of this year or the next), the way
/// a finger does.
Future<void> _goToMonth(WidgetTester tester, Localization l, int month) async {
  var steps = (month - today.month) % 12;
  while (steps-- > 0) {
    await tester.tap(find.byTooltip(l[K.calNextMonth]));
    await tester.pumpAndSettle();
  }
}

Future<void> _openDay(WidgetTester tester, DateTime date) async {
  final cell = find
      .descendant(of: find.byType(PageView), matching: find.text('${date.day}'))
      .last;
  await tester.ensureVisible(cell);
  await tester.pumpAndSettle();
  await tester.tap(cell);
  await tester.pumpAndSettle();
}

final angles = <Angle>[
  // 1 — who is with the child today. FREE: the calendar, two caregivers.
  Angle(
    'hoje',
    const AdWords(
      'Quem está com as crianças hoje?',
      'O calendário da guarda compartilhada mostra com quem elas estão em cada dia.',
    ),
    source: (t) =>
        familySource(premium: false)..frozenRequests = [pendingRequest(t)],
  ),

  // 2 — a swap is asked and answered in the app, and recorded. FREE: swaps
  // have no Premium gate. NOT "only when both agree": a request nobody
  // answers is approved by the deadline rule (F-24/F-60), and the admin mode
  // writes directly (F-81) — so the words say what always holds.
  Angle(
    'troca',
    const AdWords(
      'Troca de dia pedida e respondida no app',
      'Um responsável pede, o outro aprova ou recusa, e a mudança fica registrada.',
    ),
    source: (t) => familySource(premium: false)
      ..frozenRequests = [pendingRequest(t)]
      ..pendingForMe = [pendingRequest(t)],
    interact: (tester, l) async {
      if (requestedSaturday.month != today.month) {
        await _goToMonth(tester, l, requestedSaturday.month);
      }
      await _openDay(tester, requestedSaturday);
    },
  ),

  // 3 — the festas in two houses, in one calendar (November–December). FREE:
  // the calendar of December, within the plan's months.
  Angle(
    'festas',
    const AdWords(
      'Natal e Ano-Novo em duas casas',
      'As festas de fim de ano num calendário só, que os responsáveis veem juntos.',
    ),
    source: (t) => familySource(premium: false, carerOf: festasCarer),
    interact: (tester, l) => _goToMonth(tester, l, 12),
  ),
];

/// The closing card of both videos.
const closing = AdWords(
  'O calendário da guarda compartilhada',
  'No Android, pelo Google Play, e em qualquer navegador.',
);

const _out = '../store/ads';

/// Sets the test view to [format]'s canvas.
Future<void> _useFormat(WidgetTester tester, AdFormat format) async {
  tester.view.physicalSize = Size(
    format.width.toDouble(),
    format.height.toDouble(),
  );
  tester.view.devicePixelRatio = AdFormat.pixelRatio;
  addTearDown(tester.view.reset);
}

void _expectWordsWhole(WidgetTester tester) {
  for (final p in tester.renderObjectList<RenderParagraph>(
    find.descendant(
      of: find.byKey(AdFrame.wordsKey),
      matching: find.byType(RichText),
    ),
  )) {
    expect(
      p.didExceedMaxLines,
      isFalse,
      reason: 'ad words cut: "${p.text.toPlainText()}"',
    );
  }
}

void main() {
  final l = Localization(AppLanguage.ptBr);
  const texts = DemoTexts(false);

  setUpAll(() async {
    await loadBundleFonts();
    // The folders hold exactly what this run wrote.
    for (final folder in ['img', 'video/frames']) {
      final dir = Directory('$_out/$folder');
      if (!dir.existsSync()) continue;
      for (final f in dir.listSync().whereType<File>()) {
        if (f.path.endsWith('.png')) f.deleteSync();
      }
    }
  });

  for (final angle in angles) {
    for (final format in adFormats) {
      testWidgets('${angle.name} ${format.network} ${format.name}', (
        tester,
      ) async {
        await _useFormat(tester, format);
        final boundary = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: AdFrame(
              format: format,
              words: angle.words,
              app: shellApp(
                angle.source(texts),
                language: AppLanguage.ptBr,
                tab: ShellTab.calendar,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await angle.interact?.call(tester, l);
        await tester.pumpAndSettle();
        _expectWordsWhole(tester);
        await capture(
          tester,
          boundary,
          '$_out/img/${angle.name}-${format.network}-${format.name}.png',
        );
      });
    }
  }

  for (final format in adFormats.where(
    (f) => f.network == 'meta' && (f.height == 1920 || f.height == 1080),
  )) {
    testWidgets('closing card ${format.name}', (tester) async {
      await _useFormat(tester, format);
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: AdFrame(format: format, words: closing),
        ),
      );
      await tester.pumpAndSettle();
      _expectWordsWhole(tester);
      await capture(tester, boundary, '$_out/video/frames/fim-${format.name}.png');
    });
  }
}

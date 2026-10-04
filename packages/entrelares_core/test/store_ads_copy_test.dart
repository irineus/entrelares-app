import 'package:test/test.dart';

import 'mirrors/repo_files.dart';

/// T-102 — the ad copy of the first real-cohort campaign (L-31), in
/// `store/ads/copy/`, one item per line. The owner pastes these lines into
/// Google Ads and Meta; a line over a field's limit is refused by the
/// console at the worst moment (mid-setup), so every limit is pinned here,
/// together with the campaign's rules: neutral tone (never "ex"), no price and
/// no operator number (U-57: no digit at all), no emoji (U-31), no competitor,
/// and nothing that sells a Premium module as if it were free — the kit's
/// three angles show only free screens, so the copy names none of the Premium
/// modules.
void main() {
  List<String> lines(String file) => repoFile('store/ads/copy/$file')
      .split('\n')
      .map((l) => l.trimRight())
      .where((l) => l.isNotEmpty)
      .toList();

  /// `key|text` lines (Meta) → the text.
  String textOf(String line) =>
      line.contains('|') ? line.substring(line.indexOf('|') + 1) : line;

  void limits(String file, {required int count, required int max}) {
    final items = lines(file);
    expect(items, hasLength(count), reason: file);
    for (final item in items) {
      expect(textOf(item).length, lessThanOrEqualTo(max), reason: item);
      expect(textOf(item), isNotEmpty);
    }
    expect(items.toSet(), hasLength(items.length), reason: '$file repeats');
  }

  group('the limits of each field', () {
    test('Google app campaign: 5 headlines <= 30, 5 descriptions <= 90', () {
      limits('google-app-headlines.txt', count: 5, max: 30);
      limits('google-app-descriptions.txt', count: 5, max: 90);
    });

    test('Search responsive ad: 15 headlines <= 30, 4 descriptions <= 90', () {
      limits('search-headlines.txt', count: 15, max: 30);
      limits('search-descriptions.txt', count: 4, max: 90);
    });

    test('Meta: 3 angles x 2 variants of primary text, 3 headlines <= 40', () {
      // 125 is where Meta starts cutting the primary text behind "… mais".
      limits('meta-primary.txt', count: 6, max: 125);
      limits('meta-headlines.txt', count: 3, max: 40);
      final angles = {'hoje', 'troca', 'festas'};
      expect(
        lines('meta-primary.txt').map((l) => l.split('|').first).toSet(),
        {for (final a in angles) ...{'$a-1', '$a-2'}},
      );
      expect(
        lines('meta-headlines.txt').map((l) => l.split('|').first).toSet(),
        angles,
      );
    });
  });

  group('keywords', () {
    test('the five product-intent terms, each in phrase AND exact match', () {
      const terms = [
        'app guarda compartilhada',
        'aplicativo guarda compartilhada',
        'calendário guarda compartilhada',
        'app para pais separados',
        'app coparentalidade',
      ];
      expect(lines('search-keywords.txt').toSet(), {
        for (final t in terms) ...{'"$t"', '[$t]'},
      });
    });

    test('the negatives keep out legal and definition searches', () {
      expect(lines('search-negatives.txt').toSet(), {
        'advogado',
        'lei',
        'pensão',
        'petição',
        '"o que é"',
      });
    });
  });

  test('the campaign rules hold in every line a reader sees', () {
    final emoji = RegExp(
      '[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}\u{1F000}-\u{1F2FF}\u{FE0F}]',
      unicode: true,
    );
    const competitors = [
      'ourfamilywizard',
      'wizard',
      '2houses',
      'cozi',
      'appclose',
      'talkingparents',
      'amicus',
    ];
    // The Premium modules (store/README.md §1.1's plan column).
    const premium = [
      'pdf',
      'relatório',
      'agenda',
      'despesa',
      'conversa',
      'chat',
      'visualizador',
      'babá',
      'avó',
    ];
    for (final file in [
      'google-app-headlines.txt',
      'google-app-descriptions.txt',
      'search-headlines.txt',
      'search-descriptions.txt',
      'meta-primary.txt',
      'meta-headlines.txt',
    ]) {
      for (final line in lines(file)) {
        final text = textOf(line);
        final lower = text.toLowerCase();
        final where = '$file: $text';
        expect(RegExp(r'\bex\b|\bex-').hasMatch(lower), isFalse, reason: where);
        expect(RegExp(r'[0-9]').hasMatch(text), isFalse,
            reason: 'no price, no operator number (U-57): $where');
        expect(text.contains(r'R$'), isFalse, reason: where);
        expect(emoji.hasMatch(text), isFalse, reason: 'U-31: $where');
        for (final c in competitors) {
          expect(lower.contains(c), isFalse, reason: where);
        }
        for (final p in premium) {
          expect(RegExp('\\b$p').hasMatch(lower), isFalse,
              reason: 'a Premium module in the free kit: $where');
        }
      }
    }
  });
}

import 'package:entrelares_core/entrelares_core.dart';
import 'package:test/test.dart';

/// F-55 — the child name rule, mirrored from `child_normalize_name`. The DB
/// gate proves the server; this proves the client says the same sentences.
void main() {
  group('ChildRules.normalize', () {
    test('trims and collapses inner whitespace, like the server', () {
      expect(ChildRules.normalize('  Maria   Clara '), 'Maria Clara');
      expect(ChildRules.normalize(null), '');
    });
  });

  group('ChildRules.validateName', () {
    test('an empty name answers the RPC sentence', () {
      expect(ChildRules.validateName('   '),
          'Informe o primeiro nome da criança.');
    });

    test('40 code points pass, 41 answer the RPC sentence', () {
      expect(ChildRules.validateName('a' * 40), isNull);
      expect(ChildRules.validateName('a' * 41),
          'O nome da criança pode ter no máximo 40 caracteres.');
    });

    test('whitespace does not count against the limit once collapsed', () {
      expect(ChildRules.validateName('  ${'a' * 20}     ${'b' * 19}  '), isNull);
    });
  });

  group('ChildRules.joinNames', () {
    test('one, two and three names read as a sentence', () {
      expect(ChildRules.joinNames(['Lia'], and: 'e'), 'Lia');
      expect(ChildRules.joinNames(['Lia', 'Theo'], and: 'e'), 'Lia e Theo');
      expect(ChildRules.joinNames(['Lia', 'Theo', 'Nina'], and: 'and'),
          'Lia, Theo and Nina');
    });

    test('nothing to say is null, not an empty string', () {
      expect(ChildRules.joinNames(const [], and: 'e'), isNull);
      expect(ChildRules.joinNames(const ['  '], and: 'e'), isNull);
    });
  });

  // F-07: what the Crianças page offers, mirroring add_child.
  group('ChildRules.addBlock', () {
    ChildAddBlock block(int taken, {bool premium = false}) =>
        ChildRules.addBlock(
          childrenTaken: taken,
          isPremium: premium,
          freeMax: 1,
          maxPerFamily: 6,
        );

    test('free: the first child is included, the second is Premium', () {
      expect(block(0), ChildAddBlock.none);
      expect(block(1), ChildAddBlock.freeCap);
    });

    test('Premium: up to the ceiling, then the ceiling says so', () {
      expect(block(5, premium: true), ChildAddBlock.none);
      expect(block(6, premium: true), ChildAddBlock.maxCap);
    });

    test('a downgraded family above the free cap keeps its children and '
        'only meets the gate on the next one', () {
      expect(block(3), ChildAddBlock.freeCap);
    });

    test('the ceiling wins over the free cap when both are hit', () {
      expect(
          ChildRules.addBlock(
              childrenTaken: 2, isPremium: false, freeMax: 2, maxPerFamily: 2),
          ChildAddBlock.maxCap);
    });

    test('the seeds are the migration seeds: 1 free, 6 in all', () {
      expect(PublicSettings.unloaded.childrenFreeMax, 1);
      expect(PublicSettings.unloaded.childrenMaxPerFamily, 6);
      expect(
          const PublicSettings(
                  {'children.free_max': '2', 'children.max_per_family': '8'})
              .childrenMaxPerFamily,
          8);
    });
  });

  test('the flag reads false until the server says true', () {
    expect(PublicSettings.unloaded.childAgendaEnabled, isFalse);
    expect(const PublicSettings({'feature.child_agenda': 'true'})
        .childAgendaEnabled, isTrue);
  });
}

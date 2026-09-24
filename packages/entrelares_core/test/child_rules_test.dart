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

  test('the flag reads false until the server says true', () {
    expect(PublicSettings.unloaded.childAgendaEnabled, isFalse);
    expect(const PublicSettings({'feature.child_agenda': 'true'})
        .childAgendaEnabled, isTrue);
  });
}

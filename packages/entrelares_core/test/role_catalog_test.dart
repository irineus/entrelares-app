/// Mirror of `entrelares-app` `Entrelares.Tests/RoleCatalogTests.cs` and the
/// role half of `ProfileServiceHelpersTests.cs` — same cases, same verdicts.
///
/// The catalog is presentation, not validation: the DB seeds the 21 built-ins
/// and refuses anything else at invite time. What these pin is that every
/// spelling a stored row can carry still resolves, and that a family's own
/// custom role is never translated.
library;

import 'package:entrelares_core/entrelares_core.dart';
import 'package:test/test.dart';

void main() {
  group('catalog shape', () {
    test('carries the 21 built-in roles', () {
      expect(RoleCatalog.all, hasLength(21));
    });

    test('canonical names are distinct', () {
      final names = RoleCatalog.all.map((d) => d.canonicalName).toSet();
      expect(names, hasLength(RoleCatalog.all.length));
    });

    test('aliases are globally distinct — resolution cannot depend on order',
        () {
      final seen = <String>{};
      for (final definition in RoleCatalog.all) {
        for (final alias in definition.aliases) {
          expect(seen.add(alias), isTrue,
              reason: 'alias "$alias" is claimed by more than one role');
        }
      }
    });

    test('every canonical name is one of its own aliases', () {
      for (final definition in RoleCatalog.all) {
        expect(definition.aliases, contains(definition.canonicalName));
      }
    });

    test('aliases are lowercase — find() lowercases before matching', () {
      for (final definition in RoleCatalog.all) {
        for (final alias in definition.aliases) {
          expect(alias, alias.toLowerCase());
        }
      }
    });

    test('every role has both labels', () {
      for (final definition in RoleCatalog.all) {
        expect(definition.label.trim(), isNotEmpty);
        expect(definition.labelEn.trim(), isNotEmpty);
      }
    });

    test('built-in labels are unique in both languages', () {
      final pt = RoleCatalog.all.map((d) => d.label).toSet();
      final en = RoleCatalog.all.map((d) => d.labelEn).toSet();
      expect(pt, hasLength(RoleCatalog.all.length));
      expect(en, hasLength(RoleCatalog.all.length));
    });

    test('the three gendered pairs stay distinct in English', () {
      String en(String key) => RoleCatalog.translate(key, AppLanguage.en);
      expect(en('cousin_m'), isNot(en('cousin_f')));
      expect(en('friend_m'), isNot(en('friend_f')));
      expect(en('guardian_m'), isNot(en('guardian_f')));
    });
  });

  group('translate (PT-BR)', () {
    const cases = {
      'father': 'Pai',
      'mother': 'Mãe',
      'grandfather': 'Avô',
      'grandmother': 'Avó',
      'great_grandfather': 'Bisavô',
      'great_grandmother': 'Bisavó',
      'stepfather': 'Padrasto',
      'stepmother': 'Madrasta',
      'uncle': 'Tio',
      'aunt': 'Tia',
      'godfather': 'Padrinho',
      'godmother': 'Madrinha',
      'brother': 'Irmão',
      'sister': 'Irmã',
      'cousin_m': 'Primo',
      'cousin_f': 'Prima',
      'friend_m': 'Amigo',
      'friend_f': 'Amiga',
      'guardian_m': 'Tutor',
      'guardian_f': 'Tutora',
      'nanny': 'Babá',
    };

    cases.forEach((stored, expected) {
      test('$stored → $expected', () {
        expect(RoleCatalog.translate(stored), expected);
      });
    });

    test('resolves the PT spellings historical rows carry', () {
      expect(RoleCatalog.translate('pai'), 'Pai');
      expect(RoleCatalog.translate('mae'), 'Mãe');
      expect(RoleCatalog.translate('mãe'), 'Mãe');
      expect(RoleCatalog.translate('avo'), 'Avô');
      expect(RoleCatalog.translate('avó'), 'Avó');
      expect(RoleCatalog.translate('bisavo'), 'Bisavô');
      expect(RoleCatalog.translate('irmao'), 'Irmão');
      expect(RoleCatalog.translate('irma'), 'Irmã');
      expect(RoleCatalog.translate('baba'), 'Babá');
    });

    test('is case-insensitive and tolerates surrounding blanks', () {
      expect(RoleCatalog.translate('  FATHER  '), 'Pai');
      expect(RoleCatalog.translate('Mãe'), 'Mãe');
    });
  });

  group('translate (English)', () {
    test('resolves every stored shape', () {
      expect(RoleCatalog.translate('father', AppLanguage.en), 'Father');
      expect(RoleCatalog.translate('mae', AppLanguage.en), 'Mother');
      expect(RoleCatalog.translate('avo', AppLanguage.en), 'Grandfather');
      expect(RoleCatalog.translate('avó', AppLanguage.en), 'Grandmother');
      expect(RoleCatalog.translate('nanny', AppLanguage.en), 'Nanny');
    });

    test('the gendered suffixes exist because the label prints alone', () {
      expect(RoleCatalog.translate('cousin_m', AppLanguage.en), 'Cousin (m)');
      expect(RoleCatalog.translate('guardian_f', AppLanguage.en), 'Guardian (f)');
    });
  });

  group('custom roles (F-41) pass through untranslated', () {
    for (final custom in const [
      'Vovó Coruja',
      'Sogra',
      'Tia-avó do interior',
      'Babá da tarde',
    ]) {
      test('"$custom" survives both languages unchanged', () {
        expect(RoleCatalog.translate(custom), custom);
        expect(RoleCatalog.translate(custom, AppLanguage.en), custom);
      });
    }

    test('find() reports null so callers can tell built-in from custom', () {
      expect(RoleCatalog.find('Vovó Coruja'), isNull);
      expect(RoleCatalog.find('nanny'), isNotNull);
    });

    test('an empty stored value is not a role', () {
      expect(RoleCatalog.find(''), isNull);
      expect(RoleCatalog.translate(''), '');
    });
  });

  group('sign-up shortlist (U-44)', () {
    test("six built-ins, in the owner's order", () {
      expect(RoleCatalog.shortlist.map((d) => d.label),
          ['Pai', 'Mãe', 'Avô', 'Avó', 'Padrasto', 'Madrasta']);
    });

    test('shortlist and "Outro…" together are the whole catalog, once each',
        () {
      final names = [
        ...RoleCatalog.shortlist.map((d) => d.canonicalName),
        ...RoleCatalog.others.map((d) => d.canonicalName),
      ];
      expect(names, hasLength(RoleCatalog.all.length));
      expect(names.toSet(),
          RoleCatalog.all.map((d) => d.canonicalName).toSet());
    });

    test('the others keep catalog order', () {
      final order = RoleCatalog.all.map((d) => d.canonicalName).toList();
      final indexes = [
        for (final d in RoleCatalog.others) order.indexOf(d.canonicalName)
      ];
      expect(indexes, [...indexes]..sort());
    });
  });
}

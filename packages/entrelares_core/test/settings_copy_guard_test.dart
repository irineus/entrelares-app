// U-57 — a number an operator can change is never typed into a sentence.
//
// The freemium keys are enforced from `app_settings` (T-41) and, since T-80,
// edited from the operator console. Three catalog sentences still carried the
// seed as a literal ("2 responsáveis", "dois", "6 meses"), so a console edit
// made the server refuse at the new number while the screen promised the old
// one — both well-formed, nothing red. This suite reads the catalogs as data:
// every sentence that STATES a key's value names it through a placeholder,
// and no sentence anywhere counts months or caregivers with a digit.
import 'package:entrelares_core/entrelares_core.dart';
import 'package:test/test.dart';

void main() {
  final seeds = PublicSettings.unloaded;

  /// Which catalog sentences state which `app_settings` key, and the words
  /// that would be the seed spelled out. A new sentence that states one of
  /// these numbers joins this list in the same delivery.
  final stated = <String, ({int seed, List<String> keys, List<String> words})>{
    'free_caregivers': (
      seed: seeds.freeCaregivers,
      keys: [K.famFreeCapNotice, K.premFeatureCaregivers],
      words: ['dois', 'two'],
    ),
    'calendar_months_free': (
      seed: seeds.calendarMonthsFree,
      keys: [K.premFeatureHorizon, K.horizonFree],
      words: ['seis', 'six'],
    ),
    'calendar_months_premium': (
      seed: seeds.calendarMonthsPremium,
      keys: [K.horizonPremium, K.horizonFree],
      words: const [],
    ),
    // F-55: the free family's notes per day (the sheet's free-plan line).
    'agenda.free_notes_per_day': (
      seed: seeds.agendaFreeNotesPerDay,
      keys: [KApp.agendaFreeNotesOne, KApp.agendaFreeNotesMany],
      words: ['uma', 'one'],
    ),
    // T-82: server-only key, stated through the notification's `params.percent`
    // (seed 80 — the app has no PublicSettings getter for it on purpose).
    'email_quota.warn_percent': (
      seed: 80,
      keys: [K.notifRenderTitleEmailCap80, K.notifRenderEmailCap80],
      words: const [],
    ),
  };

  final catalogs = <String, Map<String, String>>{
    'pt-BR': {...StringsPtBr.values, ...StringsAppPtBr.values},
    'en': {...StringsEn.values, ...StringsAppEn.values},
  };

  for (final MapEntry(key: language, value: catalog) in catalogs.entries) {
    group(language, () {
      for (final MapEntry(key: setting, value: rule) in stated.entries) {
        test('every sentence stating $setting takes it as a placeholder', () {
          for (final key in rule.keys) {
            final text = catalog[key];
            expect(text, isNotNull, reason: '$key is missing');
            expect(text, contains('{0}'), reason: '$key: "$text"');
            expect(RegExp('\\b${rule.seed}\\b').hasMatch(text!), isFalse,
                reason: '$key types the seed ${rule.seed}: "$text"');
            for (final word in rule.words) {
              expect(
                  RegExp('\\b$word\\b', caseSensitive: false).hasMatch(text),
                  isFalse,
                  reason: '$key spells the seed as "$word": "$text"');
            }
          }
        });
      }

      test('no sentence counts months or caregivers with a typed digit', () {
        // An allowlist would be named here by catalog key, with the reason —
        // today there is nothing to allow.
        const allowed = <String>{};
        final counted = RegExp(
            r'\b\d+º? ?(meses|mês|months?|responsáveis|cuidador(es)?|caregivers?)\b',
            caseSensitive: false);
        for (final MapEntry(:key, :value) in catalog.entries) {
          if (allowed.contains(key)) continue;
          expect(counted.hasMatch(value), isFalse, reason: '$key: "$value"');
        }
      });
    });
  }

  group('Localization.ordinal', () {
    test('Portuguese uses the masculine ordinal mark', () {
      final l = Localization(AppLanguage.ptBr);
      expect(l.ordinal(3), '3º');
      expect(l.ordinal(4), '4º');
    });

    test('English picks the suffix, teens included', () {
      final l = Localization(AppLanguage.en);
      expect([1, 2, 3, 4, 11, 12, 13, 21, 22, 23, 101].map(l.ordinal), [
        '1st', '2nd', '3rd', '4th', '11th', '12th', '13th', '21st', '22nd',
        '23rd', '101st', //
      ]);
    });
  });
}

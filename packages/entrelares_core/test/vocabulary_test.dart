// U-34 — one word per place, one place per word.
//
// The defect was never a wrong string: every label was well-formed on its own
// screen. It was two screens agreeing on a word for two different things
// ("Histórico": the notices a person received AND the audit trail, two taps
// apart), and one screen disagreeing with itself (the tab said "Avisos", its
// own title said "Notificações"). Neither shows up reading one catalog entry,
// so the catalog is read as a SET here, in both languages.
import 'package:entrelares_core/entrelares_core.dart';
import 'package:test/test.dart';

void main() {
  final catalogs = {
    'pt-BR': Localization(AppLanguage.ptBr),
    'en': Localization(AppLanguage.en),
  };

  /// The label on the shell's tab beside the title its screen shows.
  const shellDestinations = <String, (String tab, String title)>{
    'notifications': (K.navNotificationsShort, K.notifPageTitle),
  };

  /// Every label of an in-page tab strip reachable from the shell.
  const stripLabels = <String>[
    K.notifTabIncoming,
    K.notifTabSent,
    K.notifTabHistory,
    K.repTabSummary,
    K.repTabHistory,
    K.repTabPdf,
  ];

  for (final MapEntry(key: language, value: l) in catalogs.entries) {
    group(language, () {
      test('a shell tab and the title of its screen are the same word', () {
        for (final MapEntry(key: place, value: keys)
            in shellDestinations.entries) {
          expect(l[keys.$1], l[keys.$2], reason: place);
        }
        // The long form the tooltip and the document title are built from.
        expect(l[K.navNotificationsShort], l[K.navNotifications]);
      });

      test('no two in-page tabs share a label', () {
        final seen = <String, String>{};
        for (final key in stripLabels) {
          final label = l[key].toLowerCase();
          expect(seen.containsKey(label), isFalse,
              reason: '"${l[key]}" names both ${seen[label]} and $key');
          seen[label] = key;
        }
      });

      test('no in-page tab borrows the name of a shell destination', () {
        final shell = {
          for (final key in [
            K.navCalendar,
            K.navFamily,
            K.navNotifications,
            K.navReports,
          ])
            l[key].toLowerCase(),
        };
        for (final key in stripLabels) {
          expect(shell.contains(l[key].toLowerCase()), isFalse, reason: key);
        }
      });
    });
  }

  test('"Histórico" is the audit trail, and only the audit trail', () {
    final pt = catalogs['pt-BR']!;
    expect(pt[K.repTabHistory], 'Histórico');
    expect(pt[K.notifTabHistory], isNot(contains('istórico')));
  });

  // The glossary reserves "Aviso" for F-52 (a notice one carer SENDS, the
  // third term beside Observação and Mensagem). A reservation is only true
  // while nothing else in the product answers to the word: until this item
  // the push card called what the SYSTEM sends "avisos", in twelve strings.
  // What the system sends is a "notificação" — in the app, on the phone and
  // by e-mail. The one survivor is the tooltip that closes a banner.
  test('"aviso" names nothing the product writes, so F-52 can have it', () {
    const survivors = {K.loginDismissNotice};
    final pt = catalogs['pt-BR']!;
    final word = RegExp(r'\bavis(o|os|a|ar|am)\b', caseSensitive: false);
    for (final key in [...K.allKeys, ...KApp.allKeys]) {
      if (survivors.contains(key)) continue;
      expect(word.hasMatch(pt[key]), isFalse,
          reason: '$key says "${pt[key]}"');
    }
  });

  // `scheduled_parent` is "planejado" / "planned" — the word the day sheet, the
  // onboarding, the wizard and the PDF already used. Three stragglers said
  // "agendado"; what is left of that word is a DATE something is set for
  // (a family deletion, a reactivation), never a carer.
  test('the planned carer is "planejado", never "agendado"', () {
    const dated = {K.layoutFamilyDeletionRequester, K.premScheduledStatus};
    final pt = catalogs['pt-BR']!;
    final word = RegExp(r'agendad[oa]s?', caseSensitive: false);
    for (final key in [...K.allKeys, ...KApp.allKeys]) {
      if (dated.contains(key)) continue;
      expect(word.hasMatch(pt[key]), isFalse,
          reason: '$key says "${pt[key]}"');
    }
    expect(pt[K.editorScheduledParent], 'Responsável planejado');
    expect(pt[K.sumPlanned], 'Planejado');
  });

  test('EN: what the system sends is a "notification", never an "alert"', () {
    // "System alert" is the heading of an operator banner, not a push.
    const survivors = {K.homeSystemAlert};
    final en = catalogs['en']!;
    final word = RegExp(r'\balerts?\b', caseSensitive: false);
    for (final key in [...K.allKeys, ...KApp.allKeys]) {
      if (survivors.contains(key)) continue;
      expect(word.hasMatch(en[key]), isFalse,
          reason: '$key says "${en[key]}"');
    }
  });
}

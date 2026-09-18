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

  // U-34 RESERVED "Aviso" for F-52 — the third term beside Observação do dia
  // and Mensagem — and F-52 (18/09/2026) SPENT it. So the assertion inverts:
  // the word is no longer absent, it is an ADDRESS. It names the notice one
  // carer sends about today, and nothing else; what the SYSTEM sends is still
  // a "notificação", in the app, on the phone and by e-mail. The one survivor
  // outside F-52 is the tooltip that closes a banner.
  //
  // The address is the key PREFIX, not a hand-kept list: a new F-52 string is
  // free to use the word, and a string anywhere else is not. That is the only
  // form of this rule that survives the next person adding a key.
  const noticePrefixes = ['app.notice.', 'notifRender.dayNotice.'];
  const noticeTitles = {
    K.notifRenderTitleDayNotice,
    K.notifRenderTitleDayNoticeCancelled,
  };

  test('"aviso" names the F-52 notice, and nothing else', () {
    const survivors = {K.loginDismissNotice};
    final pt = catalogs['pt-BR']!;
    final word =
        RegExp(r'\bavis(o|os|a|ar|am|ou|aram)\b', caseSensitive: false);
    for (final key in [...K.allKeys, ...KApp.allKeys]) {
      if (survivors.contains(key) || noticeTitles.contains(key)) continue;
      if (noticePrefixes.any(key.startsWith)) continue;
      expect(word.hasMatch(pt[key]), isFalse,
          reason: '$key says "${pt[key]}"');
    }
  });

  // The half of a reservation that rots in silence: a word held for a thing
  // that never says it. If the F-52 surface stops calling itself an aviso, the
  // test above goes green over a glossary entry pointing at nothing.
  test('the F-52 surface calls itself an aviso', () {
    final pt = catalogs['pt-BR']!;
    final word = RegExp(r'\bavis', caseSensitive: false);
    for (final key in [
      KApp.noticeAction,
      KApp.noticeTitle,
      KApp.noticeSend,
      K.notifRenderTitleDayNotice,
      K.notifRenderTitleDayNoticeCancelled,
    ]) {
      expect(word.hasMatch(pt[key]), isTrue, reason: '$key says "${pt[key]}"');
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

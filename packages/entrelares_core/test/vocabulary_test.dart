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

  // F-67 (21/09/2026, owner): "Relato do dia" is the fourth term beside
  // Observação do dia, Aviso and Mensagem — what happened on a day that has
  // passed, appended and never edited. Same shape as the aviso: an ADDRESS
  // (the key prefix) and the half that rots in silence (the surface still
  // says it). "Relatório" (the PDF) is a different word and stays free.
  const accountPrefixes = [
    'app.dayAccount.',
    'notifRender.dayAccount.',
    'notifRender.title.dayAccount',
  ];

  test('"relato" names the F-67 relato do dia, and nothing else', () {
    final pt = catalogs['pt-BR']!;
    final word =
        RegExp(r'\brelat(o|os|ar|ou|ado|ada)\b', caseSensitive: false);
    for (final key in [...K.allKeys, ...KApp.allKeys]) {
      if (accountPrefixes.any(key.startsWith)) continue;
      expect(word.hasMatch(pt[key]), isFalse,
          reason: '$key says "${pt[key]}"');
    }
  });

  test('the F-67 surface calls itself a relato', () {
    final pt = catalogs['pt-BR']!;
    final word = RegExp(r'\brelat', caseSensitive: false);
    for (final key in [
      KApp.dayAccountSection,
      KApp.dayAccountAction,
      KApp.dayAccountSave,
      KApp.pdfDayAccountsSection,
      K.notifRenderTitleDayAccount,
    ]) {
      expect(word.hasMatch(pt[key]), isTrue, reason: '$key says "${pt[key]}"');
    }
  });

  // F-55: "Agenda" and "Nota" are the day agenda, and nothing else — the
  // agenda REPLACES the Observação do dia, and a second "nota" anywhere would
  // read as the old field. Same shape as the aviso and the relato: an ADDRESS
  // (`app.agenda.`, plus the child page that introduces it) and the half that
  // rots in silence (the surface still says it).
  const agendaPrefixes = [
    'app.agenda.',
    'app.child.',
    // F-55 PR 4: the notice and the reminder name the agenda too.
    'notifRender.agenda',
    'notifRender.title.agenda',
    // F-50: the viewer is told it reads the agenda.
    'app.viewer.',
  ];

  test('"agenda" and "nota" name the F-55 agenda, and nothing else', () {
    final pt = catalogs['pt-BR']!;
    final word = RegExp(r'\b(agendas?|notas?)\b', caseSensitive: false);
    for (final key in [...K.allKeys, ...KApp.allKeys]) {
      if (agendaPrefixes.any(key.startsWith)) continue;
      expect(word.hasMatch(pt[key]), isFalse,
          reason: '$key says "${pt[key]}"');
    }
  });

  test('the F-55 surface calls itself the agenda, and the note a nota', () {
    final pt = catalogs['pt-BR']!;
    for (final key in [
      KApp.agendaSection,
      KApp.agendaAdd,
      KApp.agendaPdfSection,
    ]) {
      expect(RegExp(r'\bagenda\b', caseSensitive: false).hasMatch(pt[key]),
          isTrue,
          reason: '$key says "${pt[key]}"');
    }
    expect(pt[KApp.agendaKindNote], 'Nota');
    expect(catalogs['en']![KApp.agendaKindNote], 'Note');
  });

  // `scheduled_parent` is "planejado" / "planned" — the word the day sheet, the
  // onboarding, the wizard and the PDF already used. Three stragglers said
  // "agendado"; what is left of that word is a DATE something is set for
  // (a family deletion, a reactivation), never a carer.
  test('the planned carer is "planejado", never "agendado"', () {
    const dated = {K.layoutFamilyDeletionRequester, K.premScheduledStatus};
    final pt = catalogs['pt-BR']!;
    final word = RegExp(r'agendad[oa]s?', caseSensitive: false);
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

  // F-50: "Visualizador" is the read-only member, and nothing else — the
  // address is `app.viewer.`. ("Apenas visualização", the read-only day,
  // is another word and stays free.)
  test('"visualizador" names the F-50 viewer, and nothing else', () {
    final pt = catalogs['pt-BR']!;
    final word = RegExp(r'\bvisualizador(a|es|as)?\b', caseSensitive: false);
    for (final key in [...K.allKeys, ...KApp.allKeys]) {
      if (key.startsWith('app.viewer.')) continue;
      expect(word.hasMatch(pt[key]), isFalse,
          reason: '$key says "${pt[key]}"');
    }
  });

  test('the F-50 surface calls itself the Visualizador', () {
    final pt = catalogs['pt-BR']!;
    expect(pt[KApp.viewerBadge], 'Visualizador');
    expect(catalogs['en']![KApp.viewerBadge], 'Viewer');
    for (final key in [KApp.viewerReadOnly, KApp.viewerInviteLead]) {
      expect(RegExp(r'\bvisualizador\b', caseSensitive: false).hasMatch(pt[key]),
          isTrue, reason: key);
    }
  });

  // F-34: "despesa" names the shared-expenses module, and nothing else. The
  // address: the expense and settle-up notifications and the app's
  // `app.expense.` keys.
  test('"despesa" names the F-34 expenses, and nothing else', () {
    const prefixes = [
      'notifRender.expense',
      'notifRender.title.expense',
      'notifRender.settlement',
      'notifRender.title.settlement',
      'app.expense.',
    ];
    final pt = catalogs['pt-BR']!;
    final word = RegExp(r'despesas?', caseSensitive: false);
    for (final key in [...K.allKeys, ...KApp.allKeys]) {
      if (prefixes.any(key.startsWith)) continue;
      expect(word.hasMatch(pt[key]), isFalse, reason: '$key says "${pt[key]}"');
    }
  });

  // F-35: "conversa" names the family chat, and nothing else. The address:
  // the chat notification and the app's `app.chat.` keys. ("Mensagem" stays
  // the swap's message — the chat never says it.)
  test('"conversa" names the F-35 chat, and nothing else', () {
    const prefixes = [
      'notifRender.chat',
      'notifRender.title.chat',
      'app.chat.',
    ];
    final pt = catalogs['pt-BR']!;
    final word = RegExp(r'conversas?', caseSensitive: false);
    for (final key in [...K.allKeys, ...KApp.allKeys]) {
      if (prefixes.any(key.startsWith)) continue;
      expect(word.hasMatch(pt[key]), isFalse, reason: '$key says "${pt[key]}"');
    }
  });

  test('F-35: the tab that holds the Conversa is Comunicação', () {
    final pt = catalogs['pt-BR']!;
    expect(pt[KApp.chatNav], 'Comunicação');
    expect(pt[KApp.chatTabChat], 'Conversa');
    // Nothing else in the product calls itself "comunicação".
    final word = RegExp(r'comunica(ção|ções)', caseSensitive: false);
    for (final key in [...K.allKeys, ...KApp.allKeys]) {
      if (key == KApp.chatNav) continue;
      expect(word.hasMatch(pt[key]), isFalse, reason: '$key says "${pt[key]}"');
    }
  });

  test('the F-35 notification calls it the Conversa, never a mensagem', () {
    final pt = catalogs['pt-BR']!;
    expect(pt[K.notifRenderTitleChatMessage], 'Conversa da família');
    expect(pt[K.notifRenderTitleChatMessage], isNot(contains('ensagem')));
  });

  test('the F-34 notifications call it a despesa', () {
    final pt = catalogs['pt-BR']!;
    expect(pt[K.notifRenderTitleExpenseAdded], 'Despesa lançada');
    expect(catalogs['en']![K.notifRenderTitleExpenseAdded], 'Expense added');
  });
}

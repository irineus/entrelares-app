// F-52 — the rules that decide what an aviso may ask for, who may send one,
// and what a sentence about it says.
//
// The two that carry the item's whole safety argument are the ones about
// `keep`: it is the only request whose ANSWER moves the calendar, and it is
// reachable only from the carer whose day it is, with no stated estimate. Both
// halves are asserted here and again in the DB gate — the client MIRRORS, the
// database ENFORCES, and a mirror nobody checks is how the two drift.
import 'package:entrelares_core/entrelares_core.dart';
import 'package:test/test.dart';

void main() {
  group('wire values', () {
    test('every enum round-trips through its wire value', () {
      for (final r in NoticeReason.values) {
        expect(NoticeReason.fromWire(r.wire), r);
      }
      for (final r in NoticeRequest.values) {
        expect(NoticeRequest.fromWire(r.wire), r);
      }
      for (final o in NoticeOutcome.values) {
        expect(NoticeOutcome.fromWire(o.wire), o);
      }
    });

    // A future writer's value must read as "unknown", never as one of today's
    // meanings — the NotificationRenderer rule, which is why the renderer can
    // fall back to the stored sentence instead of inventing a reason.
    test('an unknown wire value is null, never a guess', () {
      expect(NoticeReason.fromWire('escola'), isNull);
      expect(NoticeReason.fromWire(null), isNull);
      expect(NoticeRequest.fromWire('chat'), isNull);
      expect(NoticeOutcome.fromWire('maybe'), isNull);
    });
  });

  group('who may send', () {
    test('the three ends of the day, nulls dropped', () {
      expect(
        noticeSenderIds(
            dayParentId: 1, previousParentId: 2, nextHandoffParentId: 3),
        {1, 2, 3},
      );
    });

    // Yesterday only ever ADDS a person on a transition day; on a day inside
    // someone's run it is the same person, and a set says so by itself.
    test('a day inside one carer\'s run has one end, not three', () {
      expect(
        noticeSenderIds(
            dayParentId: 1, previousParentId: 1, nextHandoffParentId: 1),
        {1},
      );
    });

    test('an unplanned day and a family with no future handoff', () {
      expect(
        noticeSenderIds(
            dayParentId: null, previousParentId: null, nextHandoffParentId: 3),
        {3},
      );
      expect(
        noticeSenderIds(
            dayParentId: 1, previousParentId: 2, nextHandoffParentId: null),
        {1, 2},
      );
    });
  });

  group('what may be asked', () {
    test('info and pickup are always available to an eligible sender', () {
      for (final eta in [null, 15, 30, 60]) {
        expect(
          noticeRequestsFor(senderId: 9, dayParentId: 1, etaMinutes: eta),
          containsAll([NoticeRequest.info, NoticeRequest.pickup]),
        );
      }
    });

    // The rule the sheet states out loud, in both directions.
    test('keep needs the day AND no estimate', () {
      expect(
        noticeRequestsFor(senderId: 1, dayParentId: 1, etaMinutes: null),
        contains(NoticeRequest.keep),
      );
      expect(
        noticeRequestsFor(senderId: 1, dayParentId: 1, etaMinutes: 30),
        isNot(contains(NoticeRequest.keep)),
      );
      expect(
        noticeRequestsFor(senderId: 2, dayParentId: 1, etaMinutes: null),
        isNot(contains(NoticeRequest.keep)),
      );
    });

    // An unplanned day belongs to nobody, so nobody can offer it.
    test('nobody can offer a day that has no carer', () {
      expect(
        noticeRequestsFor(senderId: 1, dayParentId: null, etaMinutes: null),
        isNot(contains(NoticeRequest.keep)),
      );
    });

    test('noticeRequestAllowed agrees with the list it is built from', () {
      for (final sender in [1, 2]) {
        for (final eta in [null, 15]) {
          for (final request in NoticeRequest.values) {
            expect(
              noticeRequestAllowed(
                  request: request,
                  senderId: sender,
                  dayParentId: 1,
                  etaMinutes: eta),
              noticeRequestsFor(
                      senderId: sender, dayParentId: 1, etaMinutes: eta)
                  .contains(request),
              reason: 'sender $sender, eta $eta, $request',
            );
          }
        }
      }
    });
  });

  group('who may answer', () {
    test('only the sender cancels', () {
      expect(
        noticeOutcomeAllowed(
            outcome: NoticeOutcome.cancelled,
            request: NoticeRequest.pickup,
            actorId: 1,
            senderId: 1),
        isTrue,
      );
      expect(
        noticeOutcomeAllowed(
            outcome: NoticeOutcome.cancelled,
            request: NoticeRequest.pickup,
            actorId: 2,
            senderId: 1),
        isFalse,
      );
    });

    test('an aviso is never a conversation with oneself', () {
      for (final outcome in [NoticeOutcome.helping, NoticeOutcome.keeping]) {
        expect(
          noticeOutcomeAllowed(
              outcome: outcome,
              request: NoticeRequest.keep,
              actorId: 1,
              senderId: 1),
          isFalse,
          reason: '$outcome',
        );
      }
    });

    // "Só avisando" asks for nothing, so there is nothing to accept.
    test('nothing is offered on an info aviso', () {
      for (final outcome in [NoticeOutcome.helping, NoticeOutcome.keeping]) {
        expect(
          noticeOutcomeAllowed(
              outcome: outcome,
              request: NoticeRequest.info,
              actorId: 2,
              senderId: 1),
          isFalse,
          reason: '$outcome',
        );
      }
    });

    // Taking the day is reachable only from the aviso that OFFERED it — a
    // pickup request asked for help now, not for the day.
    test('the day can only be taken when it was offered', () {
      expect(
        noticeOutcomeAllowed(
            outcome: NoticeOutcome.keeping,
            request: NoticeRequest.pickup,
            actorId: 2,
            senderId: 1),
        isFalse,
      );
      expect(
        noticeOutcomeAllowed(
            outcome: NoticeOutcome.keeping,
            request: NoticeRequest.keep,
            actorId: 2,
            senderId: 1),
        isTrue,
      );
      expect(
        noticeOutcomeAllowed(
            outcome: NoticeOutcome.helping,
            request: NoticeRequest.pickup,
            actorId: 2,
            senderId: 1),
        isTrue,
      );
    });
  });

  group('the sentence', () {
    final pt = Localization(AppLanguage.ptBr);
    final en = Localization(AppLanguage.en);

    test('PT-BR reads as one sentence, estimate included', () {
      expect(
        noticeSentence(
            l: pt,
            senderName: 'Ana',
            reason: NoticeReason.delay,
            etaMinutes: 30,
            request: NoticeRequest.info),
        'Ana avisou que vai atrasar (cerca de 30 min).',
      );
    });

    // The absence of an estimate is SAID, not left out: it is the fact that
    // makes the day offerable, and a reader who sees nothing cannot tell it
    // from a reader who sees "15 min".
    test('no estimate is stated, not omitted', () {
      expect(
        noticeSentence(
            l: pt,
            senderName: 'Ana',
            reason: NoticeReason.traffic,
            etaMinutes: null,
            request: NoticeRequest.keep),
        'Ana avisou que está preso no trânsito (sem previsão) e precisa que '
            'alguém fique com a criança hoje.',
      );
    });

    test('the sender\'s own line is quoted, never labelled', () {
      // "Mensagem" belongs to F-44 and "Observação" to the day note; an aviso
      // borrowing either word is exactly the blurring U-34 exists to stop.
      final sentence = noticeSentence(
          l: pt,
          senderName: 'Ana',
          reason: NoticeReason.medical,
          etaMinutes: null,
          request: NoticeRequest.pickup,
          note: 'estou no pronto-socorro');
      expect(sentence, endsWith('"estou no pronto-socorro"'));
      expect(sentence, isNot(contains('Mensagem')));
      expect(sentence, isNot(contains('Observação')));
    });

    test('a blank line renders no empty quotes', () {
      for (final note in [null, '', '   ']) {
        expect(
          noticeSentence(
              l: pt,
              senderName: 'Ana',
              reason: NoticeReason.other,
              etaMinutes: 15,
              request: NoticeRequest.info,
              note: note),
          isNot(contains('"')),
          reason: 'note: ${note == null ? 'null' : '"$note"'}',
        );
      }
    });

    test('EN says the same facts', () {
      expect(
        noticeSentence(
            l: en,
            senderName: 'Ana',
            reason: NoticeReason.delay,
            etaMinutes: 60,
            request: NoticeRequest.pickup),
        'Ana let you know they are running late (about 60 min) and need '
            'someone to collect the child.',
      );
    });

    // Every combination has to produce a sentence: 4 reasons × 4 estimates ×
    // 3 requests is 48 per language, and a missing catalog entry shows up as
    // the key itself rather than as a failure anywhere else.
    test('every combination renders in both languages', () {
      for (final l in [pt, en]) {
        for (final reason in NoticeReason.values) {
          for (final eta in [null, ...noticeEtaOptions]) {
            for (final request in NoticeRequest.values) {
              final sentence = noticeSentence(
                  l: l,
                  senderName: 'Ana',
                  reason: reason,
                  etaMinutes: eta,
                  request: request);
              expect(sentence, startsWith('Ana '));
              expect(sentence, endsWith('.'));
              expect(sentence, isNot(contains('{')));
              expect(sentence, isNot(contains('notifRender')));
            }
          }
        }
      }
    });
  });

  group('the answer sentence (PR 2)', () {
    final pt = Localization(AppLanguage.ptBr);
    final en = Localization(AppLanguage.en);

    // The sender must not be able to read "alguem vai ajudar" over a day that
    // actually changed hands: the two outcomes say different things, and the
    // keeping one names the move twice on purpose (the person, and the day).
    test('helping tells, keeping says the day moved', () {
      expect(
        noticeAnswerSentence(
            l: pt, answererName: 'Bruno', outcome: NoticeOutcome.helping),
        'Bruno vai ajudar agora.',
      );
      expect(
        noticeAnswerSentence(
            l: pt, answererName: 'Bruno', outcome: NoticeOutcome.keeping),
        'Bruno vai ficar com a criança hoje. O dia de hoje passou para Bruno.',
      );
    });

    test('the answerer own line is quoted, like the sender one', () {
      expect(
        noticeAnswerSentence(
            l: en,
            answererName: 'Bruno',
            outcome: NoticeOutcome.helping,
            note: 'at the bakery'),
        'Bruno is coming to help now. "at the bakery"',
      );
    });

    test('a blank line renders no empty quotes', () {
      for (final note in [null, '', '  ']) {
        expect(
          noticeAnswerSentence(
              l: pt,
              answererName: 'Bruno',
              outcome: NoticeOutcome.keeping,
              note: note),
          isNot(contains('"')),
        );
      }
    });
  });

  group('the numbers the UI says out loud', () {
    test('the cap is two, and the note ceiling is shared with the answer', () {
      expect(noticeMaxPerSenderPerDay, 2);
      expect(noticeNoteMaxLength, 140);
      expect(noticeAnswerNoteMaxLength, noticeNoteMaxLength);
    });

    test('the estimates are the three the sheet offers', () {
      expect(noticeEtaOptions, [15, 30, 60]);
    });
  });
}

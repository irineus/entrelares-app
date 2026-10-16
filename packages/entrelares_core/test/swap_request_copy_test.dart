import 'package:entrelares_core/entrelares_core.dart';
import 'package:test/test.dart';

/// U-60 — the request said in plain words to whoever answers it.
void main() {
  final pt = Localization(AppLanguage.ptBr);
  final en = Localization(AppLanguage.en);
  final thursday = DateTime(2026, 10, 8);
  final saturday = DateTime(2026, 10, 10);

  test('scenario A: the reader is asked to take the day', () {
    expect(
        swapRequestSentence(
            l: pt,
            requesterName: 'Ana',
            date: thursday,
            isRevert: false,
            requesterIsProposed: false),
        'Ana pede que você fique com a criança na qui, 08/10.');
    expect(
        swapRequestSentence(
            l: en,
            requesterName: 'Ana',
            date: thursday,
            isRevert: false,
            requesterIsProposed: false),
        'Ana asks you to keep the child on Thu, 08 Oct.');
  });

  test('U-61: with exactly one child the sentence says the name', () {
    expect(
        swapRequestSentence(
            l: pt,
            requesterName: 'Ana',
            date: thursday,
            isRevert: false,
            requesterIsProposed: false,
            childName: 'Sofia'),
        'Ana pede que você fique com Sofia na qui, 08/10.');
    expect(
        swapRequestSentence(
            l: pt,
            requesterName: 'Ana',
            date: thursday,
            isRevert: false,
            requesterIsProposed: true,
            childName: 'Sofia'),
        'Ana pede para ficar com Sofia na qui, 08/10, que é seu dia.');
    expect(
        swapRequestSentence(
            l: en,
            requesterName: 'Ana',
            date: thursday,
            isRevert: false,
            requesterIsProposed: false,
            childName: 'Sofia'),
        'Ana asks you to keep Sofia on Thu, 08 Oct.');
    // A revert names no child either way.
    expect(
        swapRequestSentence(
            l: pt,
            requesterName: 'Ana',
            date: thursday,
            isRevert: true,
            requesterIsProposed: false,
            childName: 'Sofia'),
        'Ana pede para desfazer a troca da qui, 08/10.');
  });

  test('PT-BR genders the weekday: no sábado, no domingo', () {
    expect(swapOnDay(saturday, pt), 'no sáb, 10/10');
    expect(swapOnDay(DateTime(2026, 10, 11), pt), 'no dom, 11/10');
    expect(swapOfDay(saturday, pt), 'do sáb, 10/10');
    expect(swapOfDay(thursday, pt), 'da qui, 08/10');
  });

  test('scenario B: the requester proposes themselves on my day', () {
    expect(
        swapRequestSentence(
            l: pt,
            requesterName: 'Ana',
            date: saturday,
            isRevert: false,
            requesterIsProposed: true),
        'Ana pede para ficar com a criança no sáb, 10/10, que é seu dia.');
  });

  test('a revert says it undoes a swap', () {
    expect(
        swapRequestSentence(
            l: pt,
            requesterName: 'Ana',
            date: thursday,
            isRevert: true,
            requesterIsProposed: false),
        'Ana pede para desfazer a troca da qui, 08/10.');
    expect(
        swapRequestSentence(
            l: en,
            requesterName: 'Ana',
            date: thursday,
            isRevert: true,
            requesterIsProposed: false),
        'Ana asks to undo the swap of Thu, 08 Oct.');
  });

  // F-94: on the day, while the request waits, both parties read who keeps
  // the day until the answer.
  group('pendingTodaySentence', () {
    String first(int id) => {1: 'Ana', 2: 'Bruno', 3: 'Vera'}[id]!;

    test('the requester reads who stays and who must answer', () {
      expect(
          pendingTodaySentence(
              l: pt, me: 1, carerId: 1, targetId: 2, firstName: first),
          'Você segue responsável até Bruno responder.');
    });

    test('the target reads that the carer stays until they answer', () {
      expect(
          pendingTodaySentence(
              l: pt, me: 2, carerId: 1, targetId: 2, firstName: first),
          'Ana segue responsável até você responder.');
      expect(
          pendingTodaySentence(
              l: en, me: 2, carerId: 1, targetId: 2, firstName: first),
          'Ana stays responsible until you answer.');
    });

    test('scenario B: the target has the day and must answer', () {
      expect(
          pendingTodaySentence(
              l: pt, me: 2, carerId: 2, targetId: 2, firstName: first),
          'Você segue responsável até responder ao pedido.');
    });

    test('a third reader sees both names', () {
      expect(
          pendingTodaySentence(
              l: pt, me: 3, carerId: 1, targetId: 2, firstName: first),
          'Ana segue responsável até Bruno responder.');
    });
  });

  // F-94: the eve reminder rides auto_reminder with kind 'eve'.
  test('the eve reminder renders in the reader language', () {
    const params = '{"kind":"eve","date":"2026-10-08","name":"Ana Souza"}';
    expect(NotificationRenderer.title('auto_reminder', params, 'x', en),
        'Request for tomorrow still unanswered');
    expect(
        NotificationRenderer.message('auto_reminder', params, 'x', en),
        'Ana Souza made a request for tomorrow, 08 Oct 2026, that is still '
        'waiting for your answer.');
    expect(NotificationRenderer.message('auto_reminder', params, 'x', pt),
        'Ana Souza fez um pedido para amanhã, 08/10/2026, que ainda espera a '
        'sua resposta.');
  });

  // F-95: the story of a swapped day, one line under the pills.
  test('swapStorySentence: asked, approved, the note', () {
    expect(
        swapStorySentence(
            l: pt,
            requesterName: 'Ana',
            askedAtLocal: DateTime(2026, 10, 3, 9, 12),
            approverName: 'Bruno',
            approvedAtLocal: DateTime(2026, 10, 4, 18, 12),
            automatic: false,
            note: ' combinado '),
        'Troca pedida por Ana em 03/10 09:12, aprovada por Bruno em 04/10 18:12 · '
        '"combinado"');
    expect(
        swapStorySentence(
            l: pt,
            requesterName: 'Ana',
            askedAtLocal: DateTime(2026, 10, 3, 9, 12),
            approverName: 'Bruno',
            approvedAtLocal: DateTime(2026, 10, 10),
            automatic: true),
        'Troca pedida por Ana em 03/10 09:12, aprovada automaticamente em 10/10 00:00');
  });

  // F-98: the author of an aviso reads herself in the second person.
  test('noticeSentence(mine: true) is "Você avisou que…"', () {
    expect(
        noticeSentence(
            l: pt,
            senderName: 'Ana Souza',
            reason: NoticeReason.delay,
            etaMinutes: 15,
            request: NoticeRequest.info,
            mine: true),
        startsWith('Você avisou que '));
    expect(
        noticeSentence(
            l: pt,
            senderName: 'Ana Souza',
            reason: NoticeReason.delay,
            etaMinutes: null,
            request: NoticeRequest.pickup,
            mine: true),
        isNot(contains('Ana Souza')));
    expect(
        noticeSentence(
            l: en,
            senderName: 'Ana Souza',
            reason: NoticeReason.delay,
            etaMinutes: 15,
            request: NoticeRequest.info,
            mine: true),
        startsWith('You said you '));
  });

  // F-99: the handoff time is the two ends' or an admin's.
  test('mayChangeHandoff: the day, the day before, or an admin', () {
    bool may(int me, {bool admin = false}) => mayChangeHandoff(
        me: me,
        isAdmin: admin,
        scheduledParentId: 1,
        actualParentId: null,
        previousEffectiveParentId: 2);
    expect(may(1), isTrue, reason: 'the carer of the day');
    expect(may(2), isTrue, reason: 'who hands over (D-1)');
    expect(may(3), isFalse, reason: 'a third caregiver');
    expect(may(3, admin: true), isTrue);
  });

  // Owner's QA of 3.1.10: who "Pedir para outra pessoa ficar com este dia"
  // pre-selects when three or more carers could take the day.
  group('suggestSwapCandidate', () {
    // 1 father, 2 mother, 3 grandmother, 4 stepmother, 5 a custom role.
    const roles = {1: 'father', 2: 'mother', 3: 'grandmother', 4: 'stepmother'};
    int? pick(int day, List<int> c,
            {int? prev, int? next, Map<int, int> month = const {}}) =>
        suggestSwapCandidate(
            scheduledParentId: day,
            candidates: c,
            canonicalRoleOf: (id) => roles[id],
            previousCarerId: prev,
            nextCarerId: next,
            daysInMonth: month);

    test('father and mother always swap between themselves', () {
      expect(pick(1, [3, 4, 2], prev: 3, next: 4), 2);
      expect(pick(2, [3, 1], prev: 3), 1);
    });
    test('without the pair: whoever has the child around the day', () {
      expect(pick(3, [1, 2, 5], next: 5), 5);
      expect(pick(4, [1, 2, 3], prev: 3), 3,
          reason: 'a step-parent has no fixed rule');
      expect(pick(1, [3, 5], prev: 5), 5, reason: 'no mother in the family');
    });
    test('a tie or nobody around: more days this month, then roster order',
        () {
      expect(pick(3, [4, 5], prev: 4, next: 5, month: {4: 3, 5: 9}), 5);
      expect(pick(3, [4, 5], month: {5: 2}), 5);
      expect(pick(3, [4, 5]), 4);
      expect(pick(3, const []), isNull);
    });
  });

  test('the HANDOFF_PARTY marker is said in the reader language', () {
    const raw = 'PostgrestException(message: HANDOFF_PARTY: Só quem entrega '
        'ou recebe a criança neste dia pode mudar o horário da entrega., '
        'code: 23514, details: null, hint: null)';
    expect(translateSaveError(raw, 'x', en), en[KApp.errHandoffParty]);
    expect(translateSaveError(raw, 'x', pt), pt[KApp.errHandoffParty]);
  });
}

import 'package:entrelares_core/entrelares_core.dart';
import 'package:entrelares_db_gate/entrelares_db_gate.dart';
import 'package:supabase/supabase.dart';
import 'package:test/test.dart';

import '_helpers.dart';

/// F-52 — the aviso de imprevisto, where it is actually enforced.
///
/// **Why this suite owns its own families.** Every other suite takes a unique
/// FUTURE date from the fixture's allocator, precisely so two tests never
/// collide on `UNIQUE (family_id, schedule_date)`. An aviso cannot do that: it
/// is about TODAY by construction — the RPC reads the clock in
/// `America/Sao_Paulo` and the client has no say — so this suite needs today's
/// row to itself, plus a daily cap counted per sender that a shared family
/// would exhaust for the next test. `createFamily` gives both.
///
/// What is worth proving against a real database, in the order the rules
/// matter:
///
/// * **only the day's three ends may send** — today's carer, yesterday's, and
///   the carer of the next different day. Anyone else is refused;
/// * **only the day's own carer may OFFER the day** (`request = 'keep'`), and
///   only with no estimate. Those two halves are the whole safety argument of
///   the item: the answer to a `keep` aviso opens an already-approved swap
///   (PR 2), so the sender must be the person whose day it is — that is what
///   keeps the swap inside F-28 — and a bounded delay is never a reason to
///   hand the day over;
/// * **the stored PT-BR sentence is byte-identical to the catalog** (U-13).
///   Every reader rebuilds the sentence from `params`; this text is what
///   survives a payload nobody can parse, and a Portuguese reader's history
///   must not appear to change;
/// * **append-only by GRANT** — `authenticated` holds SELECT and nothing else,
///   so no client can write, edit or delete a notice directly;
/// * **one outcome per notice**, by UNIQUE — two carers answering in the same
///   second is the case, not the corner case.
void dayNoticeTests(GateFixture fx) {
  /// Today's row for [carerId], in the throwaway family that owns it.
  Future<void> planToday(int familyId, int carerId) async {
    await fx.service.from('care_schedules').insert({
      'family_id': familyId,
      'schedule_date': isoDate(today()),
      'scheduled_parent_id': carerId,
    });
  }

  Future<void> planTomorrow(int familyId, int carerId) async {
    await fx.service.from('care_schedules').insert({
      'family_id': familyId,
      'schedule_date': isoDate(addDays(today(), 1)),
      'scheduled_parent_id': carerId,
    });
  }

  Future<int> send(
    SupabaseClient who, {
    String reason = 'atraso',
    int? eta,
    String request = 'info',
    String? note,
  }) async =>
      await who.rpc<dynamic>('send_day_notice', params: {
        'p_reason': reason,
        'p_eta_minutes': eta,
        'p_request': request,
        'p_note': note,
      }) as int;

  group('F-52 · who may send', () {
    late ThrowawayFamily fam;

    setUpAll(() async {
      fam = await fx.createFamily('f52send');
      await planToday(fam.familyId, fam.adminProfile.id);
    });

    test('today\'s carer may', () async {
      final id = await send(fam.admin, reason: 'transito', eta: 30);
      final row = (await fx.service
              .from('day_notices')
              .select()
              .eq('id', id)
              .limit(1))
          .single;
      expect(row['sender_profile_id'], fam.adminProfile.id);
      expect(row['schedule_date'], isoDate(today()));
      expect(row['reason'], 'transito');
      expect(row['eta_minutes'], 30);
      expect(row['request'], 'info');
    });

    // The member is nobody's end here: today is the admin's, there is no
    // yesterday row and no future day with a different carer.
    test('a carer with no part in the day may not', () async {
      await expectRejected(() => send(fam.member),
          contains: 'no meio da troca do dia');
    });

    // The end the card's own file list would have missed: the member appears
    // nowhere in today's row, and is still the person COLLECTING next.
    test('the carer of the next handoff may', () async {
      await planTomorrow(fam.familyId, fam.memberProfile.id);
      final id = await send(fam.member, request: 'pickup');
      expect(id, isPositive);
    });
  });

  group('F-52 · who may offer the DAY', () {
    late ThrowawayFamily fam;

    setUpAll(() async {
      fam = await fx.createFamily('f52keep');
      await planToday(fam.familyId, fam.adminProfile.id);
      await planTomorrow(fam.familyId, fam.memberProfile.id);
    });

    // The CHECK constraint's half: a delay with a deadline is not a reason to
    // hand the day over. Whoever is asking, and whatever they say.
    test('a stated estimate refuses it', () async {
      await expectRejected(
          () => send(fam.admin, request: 'keep', eta: 15),
          contains: 'day_notices_keep_needs_open_end');
    });

    // The half only a lookup can answer, and the one that keeps PR 2's swap
    // inside F-28: the answerer proposes THEMSELVES on the sender's own day.
    test('a carer whose day it is not refuses it', () async {
      await expectRejected(
          () => send(fam.member, request: 'keep'),
          contains: 'Só quem está com o dia de hoje');
    });

    test('the day\'s own carer, with no estimate, may', () async {
      final id = await send(fam.admin, request: 'keep', note: '  sem sinal  ');
      final row = (await fx.service
              .from('day_notices')
              .select()
              .eq('id', id)
              .limit(1))
          .single;
      expect(row['request'], 'keep');
      expect(row['eta_minutes'], isNull);
      // The free line is normalized server-side, by the same rule the client
      // mirrors — two trims that can disagree is how the same text renders
      // differently on two screens.
      expect(row['note'], 'sem sinal');
    });
  });

  group('F-52 · the daily cap', () {
    late ThrowawayFamily fam;

    setUpAll(() async {
      fam = await fx.createFamily('f52cap');
      await planToday(fam.familyId, fam.adminProfile.id);
    });

    test('two go through and the third is refused', () async {
      await send(fam.admin);
      await send(fam.admin);
      await expectRejected(() => send(fam.admin),
          contains: 'já enviou 2 avisos hoje');
    });

    // The cap counts avisos SENT, not avisos still open: cancel-and-resend
    // would otherwise be an unbounded channel, which is the F-35 line this
    // number exists to hold.
    test('cancelling does not give the slot back', () async {
      final open = (await fx.service
          .from('day_notices')
          .select('id')
          .eq('sender_profile_id', fam.adminProfile.id)
          .limit(1)).single['id'] as int;
      await fam.admin
          .rpc<dynamic>('cancel_day_notice', params: {'p_notice_id': open});
      await expectRejected(() => send(fam.admin),
          contains: 'já enviou 2 avisos hoje');
    });
  });

  group('F-52 · the sentence and the payload', () {
    late ThrowawayFamily fam;
    late int noticeId;

    setUpAll(() async {
      fam = await fx.createFamily('f52copy');
      await planToday(fam.familyId, fam.adminProfile.id);
      noticeId = await send(fam.admin,
          reason: 'medico', request: 'keep', note: 'no pronto-socorro');
    });

    Future<Map<String, dynamic>> notificationOf(int recipient) async =>
        (await fx.service
                .from('notifications')
                .select()
                .eq('recipient_profile_id', recipient)
                .eq('type', 'day_notice')
                .order('id', ascending: false)
                .limit(1))
            .single;

    // U-13: the stored text is the FALLBACK every reader falls back TO, and it
    // is written in SQL while the catalog is written in Dart. One place says
    // "(sem previsão)" and the other could quietly stop — this is the only
    // assertion that reads both.
    test('the stored PT-BR sentence is byte-identical to the catalog',
        () async {
      final row = await notificationOf(fam.memberProfile.id);
      expect(
        row['message'],
        noticeSentence(
          l: Localization(AppLanguage.ptBr),
          senderName: fam.adminProfile.fullName,
          reason: NoticeReason.medical,
          etaMinutes: null,
          request: NoticeRequest.keep,
          note: 'no pronto-socorro',
        ),
      );
      expect(row['title'], 'Aviso de imprevisto');
    });

    // Without `params` the row renders PT-BR for an English reader forever,
    // and nothing fails. `notification_params_coverage_test` pins that the
    // INSERT carries them; this pins that they carry the right VALUES.
    test('params carry values, never a sentence', () async {
      final params =
          (await notificationOf(fam.memberProfile.id))['params'] as Map;
      expect(params['kind'], 'keep');
      expect(params['reason'], 'medico');
      expect(params['name'], fam.adminProfile.fullName);
      expect(params['date'], isoDate(today()));
      expect(params['note'], 'no pronto-socorro');
      // jsonb_strip_nulls: an absent estimate is ABSENT, not JSON null, so the
      // renderer's own fallback applies rather than a key holding nothing.
      expect(params.containsKey('eta'), isFalse);
    });

    // F-09's rule, which this writer inherits by construction: push only what
    // the recipient did not just do.
    test('the sender gets no receipt', () async {
      final mine = await fx.service
          .from('notifications')
          .select('id')
          .eq('recipient_profile_id', fam.adminProfile.id)
          .eq('type', 'day_notice');
      expect(mine, isEmpty);
    });

    test('cancelling tells whoever received it', () async {
      await fam.admin
          .rpc<dynamic>('cancel_day_notice', params: {'p_notice_id': noticeId});
      final row = await notificationOf(fam.memberProfile.id);
      expect(row['title'], 'Aviso cancelado');
      expect((row['params'] as Map)['kind'], 'cancelled');
    });
  });

  // ── PR 2 ────────────────────────────────────────────────────────────────
  group('F-52 · answering', () {
    late ThrowawayFamily fam;

    Future<int?> answer(SupabaseClient who, int noticeId, String outcome,
            {String? note}) async =>
        await who.rpc<dynamic>('answer_day_notice', params: {
          'p_notice_id': noticeId,
          'p_outcome': outcome,
          'p_note': note,
        }) as int?;

    setUpAll(() async {
      fam = await fx.createFamily('f52ans');
      await planToday(fam.familyId, fam.adminProfile.id);
    });

    test('nobody answers their own aviso', () async {
      final id = await send(fam.admin, request: 'pickup');
      await expectRejected(() => answer(fam.admin, id, 'helping'),
          contains: 'responder ao');
    });

    // "So avisando" asks for nothing, so there is nothing to accept.
    test('an info aviso accepts no answer', () async {
      final id = await send(fam.admin, request: 'info');
      await expectRejected(() => answer(fam.member, id, 'helping'),
          contains: 'pede nada');
    });

    test('helping does not touch the calendar', () async {
      final id = await send(fam.admin, request: 'pickup');
      final swap = await answer(fam.member, id, 'helping', note: 'na padaria');
      expect(swap, isNull);

      final day = (await fx.service
              .from('care_schedules')
              .select()
              .eq('family_id', fam.familyId)
              .eq('schedule_date', isoDate(today()))
              .limit(1))
          .single;
      expect(day['actual_parent_id'], isNull);

      final outcome = (await fx.service
              .from('day_notice_outcomes')
              .select()
              .eq('notice_id', id)
              .limit(1))
          .single;
      expect(outcome['outcome'], 'helping');
      expect(outcome['actor_profile_id'], fam.memberProfile.id);
      expect(outcome['note'], 'na padaria');
      expect(outcome['swap_request_id'], isNull);
    });

    // A pickup asked for help NOW, not for the day. Answering it by taking the
    // day would apply a consent the sender never gave.
    test('the day cannot be taken when it was not offered', () async {
      final id = await send(fam.admin, request: 'pickup');
      await expectRejected(() => answer(fam.member, id, 'keeping'),
          contains: 'pediu ajuda');
    });
  });

  // The assertion the whole PR exists for: the day moves, and it moves THROUGH
  // the two-party workflow — never beside it.
  group('F-52 · taking the day goes through the swap workflow', () {
    late ThrowawayFamily fam;
    late int noticeId;
    late int swapId;

    setUpAll(() async {
      fam = await fx.createFamily('f52take');
      await planToday(fam.familyId, fam.adminProfile.id);
      noticeId = await send(fam.admin, reason: 'medico', request: 'keep');
      swapId = (await fam.member.rpc<dynamic>('answer_day_notice', params: {
        'p_notice_id': noticeId,
        'p_outcome': 'keeping',
        'p_note': null,
      })) as int;
    });

    test('today changed carer', () async {
      final day = (await fx.service
              .from('care_schedules')
              .select()
              .eq('family_id', fam.familyId)
              .eq('schedule_date', isoDate(today()))
              .limit(1))
          .single;
      expect(day['actual_parent_id'], fam.memberProfile.id);
      expect(day['scheduled_parent_id'], fam.adminProfile.id);
    });

    // Scenario A, and it matters: the answerer proposed THEMSELVES on the
    // sender's own day. A third party proposed on somebody else's day is the
    // F-28 case that is forbidden by design, and this is how the aviso stays
    // out of it.
    test('an APPROVED swap records it, requester = the sender', () async {
      final swap = (await fx.service
              .from('swap_requests')
              .select()
              .eq('id', swapId)
              .limit(1))
          .single;
      expect(swap['status'], 'approved');
      expect(swap['requesting_profile_id'], fam.adminProfile.id);
      expect(swap['target_profile_id'], fam.memberProfile.id);
      expect(swap['proposed_actual_parent_id'], fam.memberProfile.id);
      expect(swap['resolved_by'], 'user');
      expect(swap['resolved_at'], isNotNull);
    });

    // Everything downstream is free BECAUSE the change went through the
    // workflow: the record is written by the trigger, with its F-61 stamp, and
    // nothing in this function had to write it.
    test('the audit trail recorded the change by itself', () async {
      final logs = await fx.service
          .from('activity_logs')
          .select()
          .eq('family_id', fam.familyId)
          .eq('affected_date', isoDate(today()))
          .order('id', ascending: false)
          .limit(1);
      expect(logs, isNotEmpty);
      expect(logs.first['action'], 'UPDATE');
      expect((logs.first['new_data'] as Map)['actual_parent_id'],
          fam.memberProfile.id);
    });

    test('the outcome links the notice to the swap it produced', () async {
      final outcome = (await fx.service
              .from('day_notice_outcomes')
              .select()
              .eq('notice_id', noticeId)
              .limit(1))
          .single;
      expect(outcome['outcome'], 'keeping');
      expect(outcome['swap_request_id'], swapId);
    });

    test('the sender is told the day moved', () async {
      final row = (await fx.service
              .from('notifications')
              .select()
              .eq('recipient_profile_id', fam.adminProfile.id)
              .eq('type', 'day_notice')
              .order('id', ascending: false)
              .limit(1))
          .single;
      expect((row['params'] as Map)['kind'], 'keeping');
      expect(
        row['message'],
        noticeAnswerSentence(
          l: Localization(AppLanguage.ptBr),
          answererName: fam.memberProfile.fullName,
          outcome: NoticeOutcome.keeping,
        ),
      );
    });

    // One answer closes it, for good — and a second one cannot re-take a day
    // that already moved.
    test('a second answer is refused', () async {
      await expectRejected(
          () => fam.member.rpc<dynamic>('answer_day_notice', params: {
                'p_notice_id': noticeId,
                'p_outcome': 'helping',
                'p_note': null,
              }),
          contains: 'resolvido');
    });
  });

  group('F-52 · append-only and one outcome', () {
    late ThrowawayFamily fam;
    late int noticeId;

    setUpAll(() async {
      fam = await fx.createFamily('f52lock');
      await planToday(fam.familyId, fam.adminProfile.id);
      noticeId = await send(fam.admin, request: 'pickup');
    });

    // The `account_logs` shape: authenticated holds SELECT and nothing else,
    // so there is no client path that writes a notice the RPC did not.
    test('no client writes a notice directly', () async {
      await expectRejected(() async {
        await fam.admin.from('day_notices').insert({
          'family_id': fam.familyId,
          'schedule_date': isoDate(today()),
          'sender_profile_id': fam.adminProfile.id,
          'reason': 'outro',
          'request': 'info',
        });
      });
    });

    test('a notice is never edited or deleted', () async {
      await expectRejected(() async {
        await fam.admin
            .from('day_notices')
            .update({'reason': 'outro'}).eq('id', noticeId);
      });
      await expectRejected(() async {
        await fam.admin.from('day_notices').delete().eq('id', noticeId);
      });
    });

    test('nobody silences somebody else\'s call for help', () async {
      await expectRejected(
          () => fam.member.rpc<dynamic>('cancel_day_notice',
              params: {'p_notice_id': noticeId}),
          contains: 'Aviso não encontrado');
    });

    // The UNIQUE on notice_id IS the concurrency guard; this is the sequential
    // proof that it is there at all.
    test('one outcome closes it, for good', () async {
      await fam.admin
          .rpc<dynamic>('cancel_day_notice', params: {'p_notice_id': noticeId});
      await expectRejected(
          () => fam.admin.rpc<dynamic>('cancel_day_notice',
              params: {'p_notice_id': noticeId}),
          contains: 'já foi resolvido');
    });

    // Family-scoped like everything else here: another tenant's aviso is not
    // a row this family can read, let alone answer.
    test('another family sees nothing of it', () async {
      final rows = await fx.founderB
          .from('day_notices')
          .select('id')
          .eq('id', noticeId);
      expect(rows, isEmpty);
    });
  });
}

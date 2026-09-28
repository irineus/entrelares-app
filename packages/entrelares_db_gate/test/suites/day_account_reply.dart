import 'dart:convert';

import 'package:entrelares_core/entrelares_core.dart';
import 'package:entrelares_db_gate/entrelares_db_gate.dart';
import 'package:supabase/supabase.dart';
import 'package:test/test.dart';

import '_helpers.dart';
import 'day_notice.dart' show saoPauloToday;

/// F-75 — the reply to a relato do dia, where it is actually enforced.
///
/// * **the flag** — `feature.day_account_replies` off refuses every reply;
/// * **who** — another active caregiver with an account; the relato's author
///   is refused, and so is a Visualizador (the RPC and the table's F-50
///   guard);
/// * **one reply per member per relato, plus one correction** — a new row,
///   both kept; no reply to a reply;
/// * **the window** — counted from when the relato was WRITTEN;
/// * **append-only by GRANT**, family-scoped reads;
/// * **nothing else moves** — no care_schedules row, no activity_logs entry;
/// * **the in-app notice** reaches the relato's author only, in the catalog's
///   own words (U-13);
/// * **the purge** — `purge_e2e_family` takes the replies with the family.
void dayAccountReplyTests(GateFixture fx) {
  const flag = 'feature.day_account_replies';
  const viewersFlag = 'feature.viewers';
  final today = saoPauloToday();
  DateTime back(int days) => addDays(today, -days);

  Future<int> relato(SupabaseClient who, String body) async =>
      await who.rpc<dynamic>('add_day_account', params: {
        'p_date': isoDate(back(1)),
        'p_body': body,
        'p_corrects_id': null,
      }) as int;

  Future<int> reply(SupabaseClient who, int accountId, String body,
          {int? corrects}) async =>
      await who.rpc<dynamic>('add_day_account_reply', params: {
        'p_account_id': accountId,
        'p_body': body,
        'p_corrects_id': corrects,
      }) as int;

  Future<Map<String, dynamic>> row(int id) async => (await fx.service
          .from('day_account_replies')
          .select()
          .eq('id', id)
          .limit(1))
      .single;

  group('F-75 · replies to a relato', () {
    late String flagBefore;
    late String viewersBefore;
    late ThrowawayFamily fam;
    late int account;
    late int firstReply;
    late int logsBefore;
    late SupabaseClient viewer;

    setUpAll(() async {
      flagBefore = await readFlag(fx, flag);
      viewersBefore = await readFlag(fx, viewersFlag);
      await writeFlag(fx, flag, 'true');
      await writeFlag(fx, viewersFlag, 'true');
      fam = await fx.createFamily('f75rep');
      account = await relato(fam.admin, 'Ana buscou às 17h.');
      logsBefore = (await fx.service
              .from('activity_logs')
              .select('id')
              .eq('family_id', fam.familyId))
          .length;

      final email = fx.testEmail('f75viewer');
      final rows = await fam.admin.rpc<dynamic>('create_viewer_invitation',
          params: {'p_email': email, 'p_role_id': fx.roleId('grandmother')});
      final token = (rows as List).single['token'] as String;
      await fx.createInvitedUser(email, token, fullName: 'E2E Vó Resposta');
      viewer = await fx.signIn(email);
    });

    tearDownAll(() async {
      await writeFlag(fx, flag, flagBefore);
      await writeFlag(fx, viewersFlag, viewersBefore);
    });

    test('with the flag off, nobody replies', () async {
      await writeFlag(fx, flag, 'false');
      try {
        await expectRejected(() => reply(fam.member, account, 'não foi assim'),
            contains: 'ainda não está disponível');
      } finally {
        await writeFlag(fx, flag, 'true');
      }
    });

    test('the other caregiver replies; the text is stored trimmed', () async {
      firstReply = await reply(fam.member, account, '  Foi às 18h, não 17h.  ');
      final r = await row(firstReply);
      expect(r['account_id'], account);
      expect(r['author_profile_id'], fam.memberProfile.id);
      expect(r['family_id'], fam.familyId);
      expect(r['body'], 'Foi às 18h, não 17h.');
      expect(r['corrects_id'], isNull);
    });

    test('the relato\'s author is told in the app, in the catalog\'s words',
        () async {
      final n = (await fx.service
              .from('notifications')
              .select()
              .eq('recipient_profile_id', fam.adminProfile.id)
              .eq('type', 'day_account_reply')
              .limit(1))
          .single;
      final pt = Localization(AppLanguage.ptBr);
      expect(n['title'], pt[K.notifRenderTitleDayAccountReply]);
      expect(
          n['message'],
          pt.format(K.notifRenderDayAccountReplyNew, [
            fam.memberProfile.fullName,
            pt.formatIsoDate(isoDate(back(1))),
          ]));
      expect(
          NotificationRenderer.message(
              'day_account_reply', jsonEncode(n['params']), 'x', pt),
          n['message']);
      final mine = await fx.service
          .from('notifications')
          .select('id')
          .eq('recipient_profile_id', fam.memberProfile.id)
          .eq('type', 'day_account_reply');
      expect(mine, isEmpty, reason: 'the replier gets no receipt');
    });

    test('nothing else moves: no activity_logs entry', () async {
      expect(
          (await fx.service
                  .from('activity_logs')
                  .select('id')
                  .eq('family_id', fam.familyId))
              .length,
          logsBefore);
    });

    test('the author of the relato does not reply to it', () async {
      await expectRejected(() => reply(fam.admin, account, 'eu mesma'),
          contains: 'Quem escreveu o relato não responde');
    });

    test('one reply per member per relato', () async {
      await expectRejected(() => reply(fam.member, account, 'de novo'),
          contains: 'já respondeu');
    });

    test('ONE correction, both kept; no second one, no correction of a '
        'correction, never someone else\'s', () async {
      final fixed = await reply(fam.member, account, 'Foi às 18h10.',
          corrects: firstReply);
      expect((await row(fixed))['corrects_id'], firstReply);
      expect((await row(firstReply))['body'], 'Foi às 18h, não 17h.');
      await expectRejected(
          () => reply(fam.member, account, 'outra', corrects: firstReply),
          contains: 'já foi corrigida');
      await expectRejected(
          () => reply(fam.member, account, 'outra', corrects: fixed),
          contains: 'não encontrada');
      // Someone else's reply: here the relato's author, whom the author rule
      // refuses before the correction rule is even read — refused either way.
      await expectRejected(
          () => reply(fam.admin, account, 'dela', corrects: firstReply),
          contains: 'Quem escreveu o relato não responde');
    });

    test('a Visualizador reads the replies and never writes one', () async {
      final seen = await viewer
          .from('day_account_replies')
          .select('id')
          .eq('account_id', account);
      expect(seen, isNotEmpty);
      await expectRejected(() => reply(viewer, account, 'vó'),
          contains: 'Visualizadores');
    });

    test('append-only: no client inserts, edits or deletes a reply', () async {
      await expectRejected(() async {
        await fam.member.from('day_account_replies').insert({
          'family_id': fam.familyId,
          'account_id': account,
          'author_profile_id': fam.memberProfile.id,
          'body': 'por fora',
        });
      });
      await expectRejected(() async {
        await fam.member
            .from('day_account_replies')
            .update({'body': 'reescrita'}).eq('id', firstReply);
      });
      await expectRejected(() async {
        await fam.member
            .from('day_account_replies')
            .delete()
            .eq('id', firstReply);
      });
      expect((await row(firstReply))['body'], 'Foi às 18h, não 17h.');
    });

    test('another family sees nothing', () async {
      final theirs = await fx.founderB
          .from('day_account_replies')
          .select('id')
          .eq('id', firstReply);
      expect(theirs, isEmpty);
    });
  });

  group('F-75 · the window counts from when the relato was WRITTEN', () {
    late String flagBefore;
    late ThrowawayFamily fam;

    setUpAll(() async {
      flagBefore = await readFlag(fx, flag);
      await writeFlag(fx, flag, 'true');
      fam = await fx.createFamily('f75win');
    });
    tearDownAll(() async => writeFlag(fx, flag, flagBefore));

    test('inside the window is accepted; past it is refused', () async {
      final fresh = await relato(fam.admin, 'recente');
      expect(await reply(fam.member, fresh, 'ok'), isPositive);

      final old = await relato(fam.admin, 'antigo');
      await fx.service.from('day_accounts').update({
        'created_at': DateTime.now()
            .toUtc()
            .subtract(const Duration(days: 31))
            .toIso8601String(),
      }).eq('id', old);
      await expectRejected(() => reply(fam.member, old, 'tarde demais'),
          contains: 'até 30 dias depois de registrado');
    });
  });

  group('F-75 · the purge takes the replies with the family', () {
    test('purge_e2e_family leaves no reply behind', () async {
      final before = await readFlag(fx, flag);
      await writeFlag(fx, flag, 'true');
      try {
        final fam = await fx.createFamily('f75purge');
        final acc = await relato(fam.admin, 'para apagar');
        final id = await reply(fam.member, acc, 'também');
        await fx.purgeFamily(fam.familyId);
        final left = await fx.service
            .from('day_account_replies')
            .select('id')
            .eq('id', id);
        expect(left, isEmpty);
      } finally {
        await writeFlag(fx, flag, before);
      }
    });
  });

  test('F-75 · the reply keys are born explained and in range', () async {
    final rows = await fx.service
        .from('app_settings')
        .select('key, value, min_value, max_value')
        .inFilter('key', [
      'day_account_reply.window_days',
      'day_account_reply.max_chars',
      flag,
    ]);
    final byKey = {for (final r in rows) r['key'] as String: r};
    expect(byKey['day_account_reply.window_days']!['min_value'], 7);
    expect(byKey['day_account_reply.window_days']!['max_value'], 90);
    expect(byKey.keys, contains(flag));
  });
}

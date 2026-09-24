import 'package:entrelares_db_contracts/entrelares_db_contracts.dart';
import 'package:entrelares_db_gate/entrelares_db_gate.dart';
import 'package:supabase/supabase.dart';
import 'package:test/test.dart';

import '_helpers.dart';

/// F-35 (PR 1) — the family's Conversa, where it is enforced.
///
/// * **dark + Premium** — `feature.chat` and `chat.premium_only`;
/// * **immutable** — no edit, no delete, for anyone (service_role included),
///   and no client writes the table directly;
/// * **a viewer reads, never writes** — and marks what it read;
/// * **"lida por"** — who read and when, visible to the family, never the
///   author's own;
/// * **the notice** reaches every reader but the author; a reader who
///   silenced the chat gets it in-app only (`params.push = 'false'`);
/// * **the operator's keys** — the length limit and the flood brake.
void chatTests(GateFixture fx) {
  const flag = 'feature.chat';
  const viewersFlag = 'feature.viewers';

  group('F-35 · chat', () {
    late ThrowawayFamily fam;
    late ThrowawayFamily other;
    late String flagBefore;
    late String viewersBefore;
    late SupabaseClient viewer;
    late Member viewerProfile;
    late int firstId;

    Future<int> send(SupabaseClient who, String body,
            {int? quote, String? day}) async =>
        await who.rpc<dynamic>('send_chat_message', params: {
          'p_body': body,
          'p_quote_id': quote,
          'p_day': day,
        }) as int;

    setUpAll(() async {
      flagBefore = await readFlag(fx, flag);
      viewersBefore = await readFlag(fx, viewersFlag);
      await writeFlag(fx, flag, 'true');
      await writeFlag(fx, viewersFlag, 'true');
      fam = await fx.createFamily('f35chat');
      other = await fx.createFamily('f35oth');
      await fx.service.from('families').update({
        'plan': 'free',
        'trial_ends_at': null,
        'comp_premium_at': null,
      }).eq('id', fam.familyId);

      final email = fx.testEmail('f35viewer');
      final rows = await fam.admin.rpc<dynamic>('create_viewer_invitation',
          params: {'p_email': email, 'p_role_id': fx.roleId('grandmother')});
      final token = (rows as List).single['token'] as String;
      await fx.createInvitedUser(email, token, fullName: 'E2E Vó Conversa');
      viewer = await fx.signIn(email);
      viewerProfile = Member.fromJson((await fx.service
              .from('profiles')
              .select()
              .eq('family_id', fam.familyId)
              .eq('email', email)
              .limit(1))
          .single);
    });

    tearDownAll(() async {
      await writeFlag(fx, flag, flagBefore);
      await writeFlag(fx, viewersFlag, viewersBefore);
    });

    test('flag OFF and free plan are refused', () async {
      await writeFlag(fx, flag, 'false');
      try {
        await expectRejected(() => send(fam.admin, 'oi'),
            contains: 'ainda não está disponível');
      } finally {
        await writeFlag(fx, flag, 'true');
      }
      await expectRejected(() => send(fam.admin, 'oi'),
          contains: 'recurso Premium');
    });

    test('a caregiver sends; everyone but the author is told', () async {
      await fx.service
          .from('families')
          .update({'comp_premium_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', fam.familyId);
      firstId = await send(fam.admin, '  Busco às 18h.  ');
      final row = (await fx.service
              .from('chat_messages')
              .select()
              .eq('id', firstId)
              .limit(1))
          .single;
      expect(row['body'], 'Busco às 18h.');
      expect(row['author_profile_id'], fam.adminProfile.id);

      final told = await fx.service
          .from('notifications')
          .select()
          .eq('type', 'chat_message')
          .inFilter('recipient_profile_id',
              [fam.adminProfile.id, fam.memberProfile.id, viewerProfile.id]);
      final to = {for (final n in told) n['recipient_profile_id'] as int};
      expect(to, {fam.memberProfile.id, viewerProfile.id});
      final params = told.first['params'] as Map;
      expect(params['msg'], 'Busco às 18h.');
      expect(params['push'], 'true');
      expect(params['date'], isNotNull);
    });

    test('immutable: no edit and no delete, for anyone', () async {
      await expectRejected(() => fx.service
          .from('chat_messages')
          .update({'body': 'outra coisa'}).eq('id', firstId));
      await expectRejected(
          () => fx.service.from('chat_messages').delete().eq('id', firstId));
      await expectRejected(() => fam.admin.from('chat_messages').insert({
            'family_id': fam.familyId,
            'author_profile_id': fam.adminProfile.id,
            'body': 'direto na tabela',
          }));
    });

    test('a viewer reads and marks read, but never writes', () async {
      final seen = await viewer.from('chat_messages').select('id, body');
      expect(seen.map((m) => m['id']), contains(firstId));
      await expectRejected(() => send(viewer, 'oi'), contains: 'não escreve');
      expect(
          await viewer
              .rpc<dynamic>('mark_chat_read', params: {'p_up_to': firstId}),
          1);
      // Marking again adds nothing; the author never marks their own.
      expect(
          await viewer
              .rpc<dynamic>('mark_chat_read', params: {'p_up_to': firstId}),
          0);
      expect(
          await fam.admin
              .rpc<dynamic>('mark_chat_read', params: {'p_up_to': firstId}),
          0);
      final reads = await fam.member
          .from('chat_reads')
          .select()
          .eq('message_id', firstId);
      expect(reads.map((r) => r['profile_id']), [viewerProfile.id]);
    });

    test('a reply quotes a message of the same family only', () async {
      final reply =
          await send(fam.member, 'Combinado.', quote: firstId, day: '2026-10-01');
      final row = (await fx.service
              .from('chat_messages')
              .select()
              .eq('id', reply)
              .limit(1))
          .single;
      expect(row['quote_id'], firstId);
      expect(row['quoted_day'], '2026-10-01');

      await fx.service
          .from('families')
          .update({'comp_premium_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', other.familyId);
      await expectRejected(() => send(other.admin, 'intruso', quote: firstId),
          contains: 'não está nesta Conversa');
    });

    test('a reader who silenced the chat gets the in-app notice only',
        () async {
      await fam.member
          .rpc<dynamic>('set_chat_push_muted', params: {'p_muted': true});
      final id = await send(fam.admin, 'Sem push para você.');
      final n = (await fx.service
              .from('notifications')
              .select()
              .eq('type', 'chat_message')
              .eq('recipient_profile_id', fam.memberProfile.id)
              .eq('params->>id', '$id')
              .limit(1))
          .single;
      expect((n['params'] as Map)['push'], 'false');
      await fam.member
          .rpc<dynamic>('set_chat_push_muted', params: {'p_muted': false});
    });

    test('the operator keys: the length and the flood brake', () async {
      final maxBefore = await readFlag(fx, 'chat.message_max_chars');
      final perHourBefore = await readFlag(fx, 'chat.messages_per_hour');
      try {
        await writeFlag(fx, 'chat.message_max_chars', '200');
        await expectRejected(() => send(fam.admin, 'x' * 201),
            contains: 'limitado a 200 caracteres');
        await writeFlag(fx, 'chat.messages_per_hour', '10');
        await expectRejected(() async {
          for (var i = 0; i < 12; i++) {
            await send(fam.member, 'enxurrada $i');
          }
        }, contains: 'limite de 10 envios por hora');
      } finally {
        await writeFlag(fx, 'chat.message_max_chars', maxBefore);
        await writeFlag(fx, 'chat.messages_per_hour', perHourBefore);
      }
    });

    test('another family reads nothing', () async {
      expect(
          await other.admin
              .from('chat_messages')
              .select('id')
              .eq('family_id', fam.familyId),
          isEmpty);
    });
  });
}

import 'package:entrelares_db_gate/entrelares_db_gate.dart';
import 'package:supabase/supabase.dart';
import 'package:test/test.dart';

import '_helpers.dart';

/// T-104 — PostgREST cuts every response at `max_rows` (1,000 on the local
/// stack and the hosted default) with a plain 200. The app read the Conversa,
/// its read marks, the expenses and the PDF's history in ONE request each,
/// ordered ascending — so past the cap the NEWEST rows were the ones cut: new
/// texts stopped showing and every new text read "Ainda não lida".
///
/// This suite seeds a family past the cap and proves, against the real
/// PostgREST, the three reads the app now does instead:
///
/// * the premise — one unpaged ascending read really stops short of the
///   newest row (if the cap ever changes, this test says so);
/// * the Conversa's page — the newest [pageSize] by id, which always holds
///   the newest text, and the read marks of THOSE texts only;
/// * `_allPages` — count on the first page, then advance by what each page
///   returned — which reads every row whatever the cap. The loop below is
///   the app's `SupabaseCustodyDataSource._allPages`, line for line: the app
///   package imports Flutter, so the gate cannot call it.
void pagedReadsTests(GateFixture fx) {
  const flag = 'feature.chat';
  const seeded = 1050;
  const pageSize = 200; // the app's `chatPageSize`

  Future<List<Map<String, dynamic>>> allPages(
      PostgrestTransformBuilder<PostgrestList> Function() query) async {
    const page = 1000;
    final first = await query().range(0, page - 1).count(CountOption.exact);
    final rows = <Map<String, dynamic>>[...first.data];
    while (rows.length < first.count) {
      final next = await query().range(rows.length, rows.length + page - 1);
      if (next.isEmpty) break;
      rows.addAll(next);
    }
    return rows;
  }

  group('T-104 · reads past the cap', () {
    late ThrowawayFamily fam;
    late String flagBefore;
    late int newestId;

    setUpAll(() async {
      flagBefore = await readFlag(fx, flag);
      await writeFlag(fx, flag, 'true');
      fam = await fx.createFamily('t104pg');
      // The texts go in through the service role: the RPC's hourly brake
      // would stop a seed of a thousand long before the cap.
      for (var start = 0; start < seeded; start += 500) {
        await fx.service.from('chat_messages').insert([
          for (var i = start; i < start + 500 && i < seeded; i++)
            {
              'family_id': fam.familyId,
              'author_profile_id': fam.adminProfile.id,
              'body': 'T-104 texto $i',
            }
        ]);
      }
      newestId = (await fx.service
              .from('chat_messages')
              .select('id')
              .eq('family_id', fam.familyId)
              .order('id', ascending: false)
              .limit(1))
          .single['id'] as int;
      // The other caregiver reads everything: one mark per text, past the cap.
      await fam.member
          .rpc<dynamic>('mark_chat_read', params: {'p_up_to': newestId});
    });

    tearDownAll(() async {
      await writeFlag(fx, flag, flagBefore);
    });

    test('the premise: one unpaged ascending read misses the newest text',
        () async {
      final rows = await fam.member
          .from('chat_messages')
          .select('id')
          .order('id', ascending: true);
      expect(rows.length, lessThan(seeded),
          reason: 'max_rows no longer cuts at 1,000 — re-read T-104');
      expect(rows.map((r) => r['id']), isNot(contains(newestId)));
    });

    test('the Conversa page is the newest texts, newest included', () async {
      final rows = await fam.member
          .from('chat_messages')
          .select('id')
          .order('id', ascending: false)
          .limit(pageSize);
      expect(rows.length, pageSize);
      expect(rows.first['id'], newestId);
    });

    test('the read marks of the loaded texts are all there, so unread is 0',
        () async {
      final page = (await fam.member
              .from('chat_messages')
              .select('id')
              .order('id', ascending: false)
              .limit(pageSize))
          .map((r) => r['id'] as int)
          .toList();
      final marks = await allPages(() => fam.admin
          .from('chat_reads')
          .select('message_id, profile_id')
          .inFilter('message_id', page)
          .order('message_id', ascending: true)
          .order('profile_id', ascending: true));
      final readByMember = {
        for (final m in marks)
          if (m['profile_id'] == fam.memberProfile.id) m['message_id'] as int
      };
      // Every loaded text of the admin was read by the member — including
      // the newest, which the whole-table read reported as "Ainda não lida".
      expect(readByMember, containsAll(page));
    });

    test('paging by count + range reads every row whatever the cap',
        () async {
      final texts = await allPages(() => fam.member
          .from('chat_messages')
          .select('id')
          .order('id', ascending: true));
      expect(texts.length, seeded);
      expect(texts.last['id'], newestId);
      expect({for (final r in texts) r['id']}.length, seeded,
          reason: 'a row read twice means the order is not unique');

      final marks = await allPages(() => fam.member
          .from('chat_reads')
          .select('message_id, profile_id')
          .order('message_id', ascending: true)
          .order('profile_id', ascending: true));
      expect(marks.length, seeded);
    });
  });
}

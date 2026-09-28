import 'package:entrelares_core/entrelares_core.dart';
import 'package:entrelares_db_contracts/entrelares_db_contracts.dart';
import 'package:entrelares_db_gate/entrelares_db_gate.dart';
import 'package:supabase/supabase.dart';
import 'package:test/test.dart';

import '_helpers.dart';
import 'day_notice.dart' show saoPauloToday;

/// F-76 — `search_history`, the word search over the texts the Histórico
/// shows, where it is actually enforced:
///
/// * **the fold** — `history_fold` returns, byte for byte, what
///   `ChatRules.fold` returns (the core mirror pins the map; this pins the
///   OUTPUT on a real database, whatever its ctype does to capitals);
/// * **the matching** — every word, any order, accents and case forgiven;
/// * **the cut** — SECURITY INVOKER: another family finds nothing, and a
///   Visualizador never finds a swap's message (F-50's RESTRICTIVE policy),
///   while it does find the relato it can read;
/// * **nothing is stored** — a search writes no row.
void historySearchTests(GateFixture fx) {
  final today = saoPauloToday();

  Future<List<Map<String, dynamic>>> search(
          SupabaseClient who, String query) async =>
      ((await who.rpc<dynamic>('search_history', params: {'p_query': query}))
              as List)
          .cast<Map<String, dynamic>>();

  group('F-76 · history_fold is ChatRules.fold', () {
    test('byte for byte, capitals and accents included', () async {
      for (final s in [
        'Ônibus ESCOLAR',
        'Ação, pão e mãe',
        'Crème brûlée com ñ',
        'ÇÃO ÉÊË ÍÌ ÕÖ ÜÚ',
        'sem acento nenhum 123',
      ]) {
        final sql = await fx.service
            .rpc<dynamic>('history_fold', params: {'p_text': s});
        expect(sql, ChatRules.fold(s), reason: s);
      }
    });
  });

  group('F-76 · search_history', () {
    late String viewersBefore;
    late ThrowawayFamily fam;
    late SupabaseClient viewer;
    late int logsBefore;

    setUpAll(() async {
      viewersBefore = await readFlag(fx, 'feature.viewers');
      await writeFlag(fx, 'feature.viewers', 'true');
      fam = await fx.createFamily('f76srch');

      // A relato (F-67), readable by the whole family.
      await fam.admin.rpc<dynamic>('add_day_account', params: {
        'p_date': isoDate(addDays(today, -1)),
        'p_body': 'Febre de 38 graus; levei ao pronto-socorro de Ônibus.',
        'p_corrects_id': null,
      });

      // A RESOLVED swap with the requester's message — the F-45 origin the
      // Histórico prints under the change. The real write path: the member
      // asks for the admin's day, the admin applies it and resolves.
      final date = addDays(today, 5);
      await fam.admin.from('care_schedules').insert({
        'schedule_date': isoDate(date),
        'scheduled_parent_id': fam.adminProfile.id,
      });
      final day = await readDay(fam.admin, date);
      final request = SwapRequest.fromJson((await fam.member
              .from('swap_requests')
              .insert({
                'schedule_date': isoDate(date),
                'schedule_id': day.id,
                'requesting_profile_id': fam.memberProfile.id,
                'target_profile_id': fam.adminProfile.id,
                'previous_actual_parent_id': null,
                'proposed_actual_parent_id': fam.memberProfile.id,
                'status': 'pending',
                'request_message': 'Ela está com febre, posso ficar com ela?',
                'created_at': DateTime.now()
                    .toUtc()
                    .subtract(const Duration(minutes: 1))
                    .toIso8601String(),
              })
              .select())
          .single);
      final fresh = await readDayById(fam.admin, day.id);
      await saveDay(fam.admin,
          fresh.copyWith(actualParentId: request.proposedActualParentId));
      await fam.admin.from('swap_requests').update({
        'status': 'approved',
        'resolved_at': DateTime.now().toUtc().toIso8601String(),
        'approval_note': 'Claro, melhoras para ela.',
      }).eq('id', request.id);

      final email = fx.testEmail('f76viewer');
      final rows = await fam.admin.rpc<dynamic>('create_viewer_invitation',
          params: {'p_email': email, 'p_role_id': fx.roleId('grandmother')});
      final token = (rows as List).single['token'] as String;
      await fx.createInvitedUser(email, token, fullName: 'E2E Vó Busca');
      viewer = await fx.signIn(email);

      logsBefore = (await fx.service
              .from('activity_logs')
              .select('id')
              .eq('family_id', fam.familyId))
          .length;
    });

    tearDownAll(() async => writeFlag(fx, 'feature.viewers', viewersBefore));

    test('every word, any order, accents and case forgiven', () async {
      final hits = await search(fam.member, 'ONIBUS  febre');
      expect(hits.map((h) => h['kind']), contains('relato'));
      final relato = hits.firstWhere((h) => h['kind'] == 'relato');
      expect(relato['day'], isoDate(addDays(today, -1)));
      expect(relato['author_profile_id'], fam.adminProfile.id);
      expect(await search(fam.member, 'febre aviao'), isEmpty);
    });

    test('a resolved swap\'s message and note are found by the family',
        () async {
      final kinds =
          (await search(fam.member, 'febre')).map((h) => h['kind']).toSet();
      expect(kinds, containsAll(['relato', 'swap_message']));
      final note = await search(fam.admin, 'melhoras');
      expect(note.single['kind'], 'swap_note');
    });

    test('a Visualizador finds the relato, never the swap negotiation',
        () async {
      final kinds =
          (await search(viewer, 'febre')).map((h) => h['kind']).toSet();
      expect(kinds, contains('relato'));
      expect(kinds, isNot(contains('swap_message')));
      expect(await search(viewer, 'melhoras'), isEmpty);
    });

    test('another family finds nothing', () async {
      expect(await search(fx.founderB, 'febre'), isEmpty);
    });

    test('a blank query returns nothing and nothing is stored', () async {
      expect(await search(fam.member, '   '), isEmpty);
      expect(
          (await fx.service
                  .from('activity_logs')
                  .select('id')
                  .eq('family_id', fam.familyId))
              .length,
          logsBefore);
    });
  });
}

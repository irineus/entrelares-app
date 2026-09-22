import 'dart:convert';

import 'package:entrelares_core/entrelares_core.dart';
import 'package:entrelares_db_gate/entrelares_db_gate.dart';
import 'package:supabase/supabase.dart';
import 'package:test/test.dart';

import '_helpers.dart';
import 'day_notice.dart' show saoPauloToday;

/// F-67 — the relato do dia, where it is actually enforced.
///
/// The plan is immutable; what happened is APPENDED. What is worth proving
/// against a real database:
///
/// * **the window** — D-1 … D-30 in `America/Sao_Paulo`; today, the future
///   and D-31 are refused by the RPC, not only hidden by the sheet;
/// * **who** — an active member with an account; a departed one is refused;
/// * **append-only by GRANT** — no client inserts, edits or deletes a relato;
/// * **corrections** — only the author, only the same day and family, one
///   correction per relato;
/// * **nothing else moves** — no `care_schedules` row, no `activity_logs`
///   entry, so no F-61 `admin_override` stamp can come out of a relato;
/// * **the in-app notification** reaches the other members with a stored
///   PT-BR sentence byte-identical to the catalog (U-13), and not the author.
///
/// Each group owns a throwaway family: the daily cap is counted per author per
/// day WRITTEN, and a shared family would exhaust it for the next test.
void dayAccountTests(GateFixture fx) {
  final today = saoPauloToday();
  DateTime back(int days) => addDays(today, -days);

  Future<int> add(SupabaseClient who, DateTime date, String body,
          {int? corrects}) async =>
      await who.rpc<dynamic>('add_day_account', params: {
        'p_date': isoDate(date),
        'p_body': body,
        'p_corrects_id': corrects,
      }) as int;

  Future<Map<String, dynamic>> row(int id) async => (await fx.service
          .from('day_accounts')
          .select()
          .eq('id', id)
          .limit(1))
      .single;

  group('F-67 · the window', () {
    late ThrowawayFamily fam;
    setUpAll(() async => fam = await fx.createFamily('f67win'));

    test('yesterday is accepted, the day and the body stored as written',
        () async {
      final id = await add(fam.admin, back(1), '  buscou no aeroporto  ');
      final r = await row(id);
      expect(r['account_date'], isoDate(back(1)));
      expect(r['author_profile_id'], fam.adminProfile.id);
      expect(r['family_id'], fam.familyId);
      // Trimmed server-side, by the rule the client mirrors.
      expect(r['body'], 'buscou no aeroporto');
      expect(r['corrects_id'], isNull);
    });

    test('the 30th day back is the edge, and is accepted', () async {
      expect(await add(fam.member, back(30), 'ok'), isPositive);
    });

    test('the 31st day back is refused', () async {
      await expectRejected(() => add(fam.admin, back(31), 'tarde demais'),
          contains: 'até 30 dias depois');
    });

    test('today is refused — it has the Observação and the aviso', () async {
      await expectRejected(() => add(fam.admin, today, 'hoje'),
          contains: 'dia que já passou');
    });

    test('a future day is refused', () async {
      await expectRejected(() => add(fam.admin, addDays(today, 3), 'futuro'),
          contains: 'dia que já passou');
    });
  });

  group('F-67 · the body', () {
    late ThrowawayFamily fam;
    setUpAll(() async => fam = await fx.createFamily('f67body'));

    test('an empty body is refused', () async {
      await expectRejected(() => add(fam.admin, back(2), '   '),
          contains: 'não pode ficar vazio');
    });

    test('1 000 characters go through, 1 001 do not', () async {
      expect(await add(fam.admin, back(2), 'a' * 1000), isPositive);
      await expectRejected(() => add(fam.admin, back(2), 'a' * 1001),
          contains: 'limitado a 1000 caracteres');
    });
  });

  group('F-67 · nothing else moves, and the family is told', () {
    late ThrowawayFamily fam;
    late int logsBefore;
    late int schedulesBefore;

    setUpAll(() async {
      fam = await fx.createFamily('f67side');
      // A planned past day, so "no row changed" is a claim about a real row.
      await fx.service.from('care_schedules').insert({
        'family_id': fam.familyId,
        'schedule_date': isoDate(back(1)),
        'scheduled_parent_id': fam.memberProfile.id,
      });
      logsBefore = (await fx.service
              .from('activity_logs')
              .select('id')
              .eq('family_id', fam.familyId))
          .length;
      schedulesBefore = (await fx.service
              .from('care_schedules')
              .select('id')
              .eq('family_id', fam.familyId))
          .length;
      await add(fam.admin, back(1), 'Bruno buscou às 17h e deixou às 19h20.');
    });

    test('no care_schedules row and no activity_logs entry is written',
        () async {
      final day = (await fx.service
              .from('care_schedules')
              .select()
              .eq('family_id', fam.familyId)
              .eq('schedule_date', isoDate(back(1)))
              .limit(1))
          .single;
      expect(day['scheduled_parent_id'], fam.memberProfile.id);
      expect(day['actual_parent_id'], isNull);
      expect(day['notes'], isNull);
      expect(
          (await fx.service
                  .from('care_schedules')
                  .select('id')
                  .eq('family_id', fam.familyId))
              .length,
          schedulesBefore);
      expect(
          (await fx.service
                  .from('activity_logs')
                  .select('id')
                  .eq('family_id', fam.familyId))
              .length,
          logsBefore);
    });

    test('the other member is told in the app, in the catalog\'s own words',
        () async {
      final n = (await fx.service
              .from('notifications')
              .select()
              .eq('recipient_profile_id', fam.memberProfile.id)
              .eq('type', 'day_account')
              .limit(1))
          .single;
      final pt = Localization(AppLanguage.ptBr);
      expect(n['title'], pt[K.notifRenderTitleDayAccount]);
      // The stored PT-BR fallback is what the PT-BR reader's renderer
      // produces from the same params — byte for byte (U-13).
      expect(
          n['message'],
          pt.format(K.notifRenderDayAccountNew, [
            fam.adminProfile.fullName,
            pt.formatIsoDate(isoDate(back(1))),
          ]));
      expect(
          NotificationRenderer.message(
              'day_account', jsonEncode(n['params']), 'x', pt),
          n['message']);
      final params = n['params'] as Map<String, dynamic>;
      expect(params['kind'], 'new');
      expect(params['date'], isoDate(back(1)));
      expect(params['name'], fam.adminProfile.fullName);
    });

    test('the author gets no receipt', () async {
      final mine = await fx.service
          .from('notifications')
          .select('id')
          .eq('recipient_profile_id', fam.adminProfile.id)
          .eq('type', 'day_account');
      expect(mine, isEmpty);
    });
  });

  group('F-67 · corrections', () {
    late ThrowawayFamily fam;
    late int original;

    setUpAll(() async {
      fam = await fx.createFamily('f67fix');
      original = await add(fam.admin, back(3), 'buscou às 17h');
    });

    test('someone else cannot correct it — they write their own', () async {
      await expectRejected(
          () => add(fam.member, back(3), 'foi às 18h', corrects: original),
          contains: 'Relato a corrigir não encontrado');
    });

    test('a correction must be about the same day', () async {
      await expectRejected(
          () => add(fam.admin, back(4), 'outro dia', corrects: original),
          contains: 'Relato a corrigir não encontrado');
    });

    test('another family cannot point at it', () async {
      await expectRejected(
          () => add(fx.founderB, back(3), 'de fora', corrects: original),
          contains: 'Relato a corrigir não encontrado');
    });

    test('the author corrects it once; both rows stay', () async {
      final fix = await add(fam.admin, back(3), 'buscou às 17h30',
          corrects: original);
      expect((await row(fix))['corrects_id'], original);
      expect((await row(original))['body'], 'buscou às 17h');
      final n = (await fx.service
              .from('notifications')
              .select()
              .eq('recipient_profile_id', fam.memberProfile.id)
              .eq('type', 'day_account')
              .order('id', ascending: false)
              .limit(1))
          .single;
      expect((n['params'] as Map)['kind'], 'correction');
      expect(
          n['message'],
          Localization(AppLanguage.ptBr).format(
              K.notifRenderDayAccountCorrection, [
            fam.adminProfile.fullName,
            Localization(AppLanguage.ptBr).formatIsoDate(isoDate(back(3))),
          ]));
    });

    test('a corrected relato is not corrected twice', () async {
      await expectRejected(
          () => add(fam.admin, back(3), 'de novo', corrects: original),
          contains: 'já foi corrigido');
    });
  });

  group('F-67 · append-only and family-scoped', () {
    late ThrowawayFamily fam;
    late int id;

    setUpAll(() async {
      fam = await fx.createFamily('f67lock');
      id = await add(fam.admin, back(1), 'registro');
    });

    test('no client writes a relato directly', () async {
      await expectRejected(() async {
        await fam.admin.from('day_accounts').insert({
          'family_id': fam.familyId,
          'account_date': isoDate(back(1)),
          'author_profile_id': fam.adminProfile.id,
          'body': 'por fora',
        });
      });
    });

    test('a relato is never edited or deleted', () async {
      await expectRejected(() async {
        await fam.admin
            .from('day_accounts')
            .update({'body': 'reescrito'}).eq('id', id);
      });
      await expectRejected(() async {
        await fam.admin.from('day_accounts').delete().eq('id', id);
      });
      expect((await row(id))['body'], 'registro');
    });

    test('the family reads it; another family sees nothing', () async {
      final mine = await fam.member.from('day_accounts').select('id').eq('id', id);
      expect(mine, hasLength(1));
      final theirs =
          await fx.founderB.from('day_accounts').select('id').eq('id', id);
      expect(theirs, isEmpty);
    });
  });

  group('F-67 · the daily cap', () {
    late ThrowawayFamily fam;
    setUpAll(() async => fam = await fx.createFamily('f67cap'));

    test('ten go through and the eleventh is refused', () async {
      for (var i = 0; i < 10; i++) {
        await add(fam.admin, back(1 + i), 'relato $i');
      }
      await expectRejected(() => add(fam.admin, back(12), 'mais um'),
          contains: 'já registrou 10 relatos hoje');
    });

    test('the cap is per author', () async {
      expect(await add(fam.member, back(1), 'o meu'), isPositive);
    });
  });

  group('F-67 · a departed member', () {
    test('is refused', () async {
      final fam = await fx.createFamily('f67left');
      await fx.elevate(fam.memberProfile);
      await fam.member.rpc<dynamic>('request_account_deletion');
      await expectRejected(() => add(fam.member, back(1), 'depois de sair'),
          contains: 'não pode registrar relatos');
    });
  });
}

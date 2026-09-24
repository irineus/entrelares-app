import 'package:entrelares_db_gate/entrelares_db_gate.dart';
import 'package:test/test.dart';

import '_helpers.dart';
import 'day_notice.dart' show saoPauloToday;

/// F-64 (PR 1) — the verifiable report, where it is enforced.
///
/// * **dark + Premium** — the flag and `report_attestation.premium_only`;
/// * **the server attests** a summary with initials and counts — never a name;
/// * **the fingerprint** is attached once, by whoever issued it;
/// * **the public answer** is a closed state — valid, pending, revoked,
///   expired, unknown — never a 404, and the purge keeps "expired" true;
/// * **the admin revokes**; another family touches nothing.
void reportAttestationTests(GateFixture fx) {
  const flag = 'feature.report_attestation';
  final today = saoPauloToday();
  final hash = 'ab' * 32;

  group('F-64 · report attestation', () {
    late ThrowawayFamily fam;
    late ThrowawayFamily other;
    late String flagBefore;
    late String id;

    setUpAll(() async {
      flagBefore = await readFlag(fx, flag);
      await writeFlag(fx, flag, 'true');
      fam = await fx.createFamily('f64att');
      other = await fx.createFamily('f64oth');
      await fx.service.from('families').update({
        'plan': 'free',
        'trial_ends_at': null,
        'comp_premium_at': null,
      }).eq('id', fam.familyId);
      await fx.service.from('care_schedules').insert([
        for (var i = 0; i < 4; i++)
          {
            'family_id': fam.familyId,
            'schedule_date': isoDate(addDays(today, i)),
            'scheduled_parent_id':
                i.isEven ? fam.adminProfile.id : fam.memberProfile.id,
          }
      ]);
    });

    tearDownAll(() async => writeFlag(fx, flag, flagBefore));

    Future<Map<String, dynamic>> issue(dynamic who) async => Map<String, dynamic>.from(
        await who.rpc('issue_report_attestation', params: {
          'p_from': isoDate(today),
          'p_to': isoDate(addDays(today, 3)),
        }) as Map);

    Future<Map<String, dynamic>> verify(String id) async =>
        Map<String, dynamic>.from(await fx.newAnonClient().rpc<dynamic>(
            'verify_report_attestation',
            params: {'p_id': id}) as Map);

    test('with the flag OFF nothing is issued', () async {
      await writeFlag(fx, flag, 'false');
      try {
        await expectRejected(() => issue(fam.admin),
            contains: 'ainda não está disponível');
      } finally {
        await writeFlag(fx, flag, 'true');
      }
    });

    test('a free family is refused: it is Premium', () async {
      await expectRejected(() => issue(fam.admin), contains: 'recurso Premium');
    });

    test('Premium: the server attests initials and counts, no name', () async {
      await fx.service
          .from('families')
          .update({'comp_premium_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', fam.familyId);
      final r = await issue(fam.member);
      id = r['id'] as String;
      final summary = r['summary'] as Map;
      expect(summary['days_planned'], 4);
      final byCarer = (summary['days_by_caregiver'] as List)
          .map((e) => '${e['initials']}:${e['days']}')
          .toSet();
      // "E2E f64att Adm" / "E2E f64att Mbr" — first and last word.
      expect(byCarer, {'EA:2', 'EM:2'});
      final text = summary.toString();
      expect(text, isNot(contains('f64att')));
      expect((await verify(id))['state'], 'pending');
    });

    test('the fingerprint is attached once, by whoever issued it', () async {
      await expectRejected(
          () => fam.admin.rpc<dynamic>('attach_report_hash',
              params: {'p_id': id, 'p_sha256': hash}),
          contains: 'não encontrado');
      await fam.member.rpc<dynamic>('attach_report_hash',
          params: {'p_id': id, 'p_sha256': hash});
      await expectRejected(
          () => fam.member.rpc<dynamic>('attach_report_hash',
              params: {'p_id': id, 'p_sha256': hash}),
          contains: 'já tem a impressão digital');

      final v = await verify(id);
      expect(v['state'], 'valid');
      expect(v['sha256'], hash);
      expect(v['period_from'], isoDate(today));
      expect(v['summary'], isA<Map>());
    });

    test('an unknown id says so — never a 404', () async {
      expect((await verify('00000000-0000-4000-8000-000000000000'))['state'],
          'unknown');
    });

    test('another family neither reads nor revokes it', () async {
      expect(
          await other.admin.from('report_attestations').select('id').eq('id', id),
          isEmpty);
      await expectRejected(
          () => other.admin
              .rpc<dynamic>('revoke_report_attestation', params: {'p_id': id}),
          contains: 'não encontrado');
      expect(
          await fam.member.from('report_attestations').select('id').eq('id', id),
          hasLength(1));
    });

    test('only the admin revokes; revoked says so, without the summary',
        () async {
      await expectRejected(
          () => fam.member
              .rpc<dynamic>('revoke_report_attestation', params: {'p_id': id}),
          contains: 'Somente administradores');
      await fam.admin
          .rpc<dynamic>('revoke_report_attestation', params: {'p_id': id});
      final v = await verify(id);
      expect(v['state'], 'revoked');
      expect(v.containsKey('summary'), isFalse);
      expect(v.containsKey('sha256'), isFalse);
    });

    test('expired, and after the purge still "expired"', () async {
      final r = await issue(fam.admin);
      final gone = r['id'] as String;
      await fx.service.from('report_attestations').update({
        'expires_at': DateTime.now().toUtc().subtract(const Duration(days: 1))
            .toIso8601String(),
      }).eq('id', gone);
      expect((await verify(gone))['state'], 'expired');

      await fx.service.rpc<dynamic>('purge_expired_report_attestations');
      final row = (await fx.service
              .from('report_attestations')
              .select()
              .eq('id', gone)
              .limit(1))
          .single;
      expect(row['summary'], isNull);
      expect(row['family_id'], isNull);
      expect(row['purged_at'], isNotNull);
      expect((await verify(gone))['state'], 'expired');
    });

    test('no client writes the table', () async {
      await expectRejected(() => fam.admin.from('report_attestations').insert({
            'family_id': fam.familyId,
            'expires_at': DateTime.now().toUtc().toIso8601String(),
          }));
    });
  });
}

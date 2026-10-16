import 'package:entrelares_db_gate/entrelares_db_gate.dart';
import 'package:test/test.dart';

import '_helpers.dart';

/// F-102 — `request_premium_from_admin(p_gate)`: a non-admin member tells the
/// family's admins they want Premium. ONE notification per live admin (type
/// `premium_request`, params kind/name/gate, the catalog's PT-BR sentence), at
/// most once per requester per São Paulo day; an admin, a Premium family and a
/// second ask on the same day are refused. Who may pay does not change.
void premiumRequestTests(GateFixture fx) {
  Future<void> plan(ThrowawayFamily fam, String plan) =>
      fx.service.rpc<dynamic>('set_family_plan',
          params: {'p_family_id': fam.familyId, 'p_plan': plan});

  Future<List<Map<String, dynamic>>> asks(int profileId) async =>
      (await fx.service
              .from('notifications')
              .select()
              .eq('recipient_profile_id', profileId)
              .eq('type', 'premium_request')
              .order('id', ascending: true))
          .cast<Map<String, dynamic>>();

  group('F-102 · premium request to the admins', () {
    test('the member asks, every live admin is told once, in the catalog\'s '
        'words — and not the member', () async {
      final fam = await fx.createFamily('f102ask');
      await plan(fam, 'free');

      final told = await fam.member.rpc<dynamic>('request_premium_from_admin',
          params: {'p_gate': 'agenda'}) as int;
      expect(told, 1);

      final n = await asks(fam.adminProfile.id);
      expect(n, hasLength(1));
      expect(n.single['title'], 'Pedido de Premium');
      expect(n.single['message'],
          '${fam.memberProfile.fullName} quer o Premium para a agenda da criança.');
      expect(n.single['params'], {
        'kind': 'ask',
        'name': fam.memberProfile.fullName,
        'gate': 'agenda',
      });
      expect(await asks(fam.memberProfile.id), isEmpty);

      final ledger = await fx.service
          .from('premium_requests')
          .select()
          .eq('family_id', fam.familyId);
      expect(ledger, hasLength(1));
      expect(ledger.single['gate'], 'agenda');
    });

    test('a second ask on the same day is refused; nothing is written',
        () async {
      final fam = await fx.createFamily('f102twice');
      await plan(fam, 'free');
      await fam.member.rpc<dynamic>('request_premium_from_admin',
          params: {'p_gate': 'chat'});

      await expectRejected(
          () => fam.member.rpc<dynamic>('request_premium_from_admin',
              params: {'p_gate': 'pdf'}),
          contains: 'já pediu o Premium hoje');
      expect(await asks(fam.adminProfile.id), hasLength(1));
    });

    test('an unknown gate is the generic ask', () async {
      final fam = await fx.createFamily('f102gen');
      await plan(fam, 'free');
      await fam.member.rpc<dynamic>('request_premium_from_admin',
          params: {'p_gate': 'something-else'});
      final n = await asks(fam.adminProfile.id);
      expect(n.single['params']['gate'], 'premium');
      expect(n.single['message'], endsWith('quer o Premium para a família.'));
    });

    test('an admin, a Premium family and a stranger are refused', () async {
      final fam = await fx.createFamily('f102ref');
      await plan(fam, 'free');
      await expectRejected(
          () => fam.admin.rpc<dynamic>('request_premium_from_admin',
              params: {'p_gate': 'chat'}),
          contains: 'administrador');

      await plan(fam, 'premium');
      await expectRejected(
          () => fam.member.rpc<dynamic>('request_premium_from_admin',
              params: {'p_gate': 'chat'}),
          contains: 'já tem o Premium');
      expect(await asks(fam.adminProfile.id), isEmpty);

      // No client reads or writes the ledger.
      await expectRejected(
          () => fam.member.from('premium_requests').select(),
          contains: 'permission denied');
    });
  });
}

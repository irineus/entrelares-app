import 'package:entrelares_db_gate/entrelares_db_gate.dart';
import 'package:supabase/supabase.dart';
import 'package:test/test.dart';

import '_helpers.dart';

/// F-55 (PR 1) — the child entity, where it is actually enforced.
///
/// * **dark by construction** — with `feature.child_agenda` off the server
///   refuses every write, whatever the client shows;
/// * **only an admin** registers, renames or removes a child, and only through
///   the RPCs: the table carries no client write grant at all;
/// * **the name** is the first name, trimmed and collapsed, 1–40 characters,
///   unique per family ignoring case;
/// * **family-scoped** — another family neither reads nor touches the row.
///
/// The flag is a shared dev row: the suite turns it ON for its own run and puts
/// back whatever it found, so a concurrent reader of the dev project is never
/// left with a value it did not choose.
void childrenTests(GateFixture fx) {
  const flag = 'feature.child_agenda';

  Future<String> getFlag() async => (await fx.service
          .from('app_settings')
          .select('value')
          .eq('key', flag))
      .single['value'] as String;

  Future<void> setFlag(String value) =>
      fx.service.from('app_settings').update({'value': value}).eq('key', flag);

  Future<int> add(SupabaseClient who, String name) async =>
      await who.rpc<dynamic>('add_child', params: {'p_first_name': name})
          as int;

  Future<List<Map<String, dynamic>>> childrenOf(int familyId) async =>
      (await fx.service
              .from('children')
              .select()
              .eq('family_id', familyId)
              .order('sort_order'))
          .cast<Map<String, dynamic>>();

  group('F-55 · children', () {
    late ThrowawayFamily fam;
    late String flagBefore;

    setUpAll(() async {
      flagBefore = await getFlag();
      await setFlag('true');
      fam = await fx.createFamily('f55kids');
    });

    tearDownAll(() async => setFlag(flagBefore));

    test('with the flag OFF the server refuses the write', () async {
      await setFlag('false');
      try {
        await expectRejected(() => add(fam.admin, 'Lia'),
            contains: 'ainda não está disponível');
      } finally {
        await setFlag('true');
      }
      expect(await childrenOf(fam.familyId), isEmpty);
    });

    test('an admin registers the first name, trimmed and collapsed', () async {
      final id = await add(fam.admin, '  Maria   Clara ');
      final rows = await childrenOf(fam.familyId);
      expect(rows, hasLength(1));
      expect(rows.single['id'], id);
      expect(rows.single['first_name'], 'Maria Clara');
      expect(rows.single['sort_order'], 0);
      expect(rows.single['created_by'], fam.adminProfile.id);
    });

    test('a second child goes after the first', () async {
      await add(fam.admin, 'Theo');
      final rows = await childrenOf(fam.familyId);
      expect([for (final r in rows) r['first_name']], ['Maria Clara', 'Theo']);
      expect(rows.last['sort_order'], 1);
    });

    test('a name already in the family is refused, ignoring case', () async {
      await expectRejected(() => add(fam.admin, 'THEO'),
          contains: 'Já existe uma criança com esse nome');
    });

    test('an empty name is refused; 40 characters pass, 41 do not', () async {
      await expectRejected(() => add(fam.admin, '   '),
          contains: 'Informe o primeiro nome');
      await expectRejected(() => add(fam.admin, 'a' * 41),
          contains: 'no máximo 40 caracteres');
      expect(await add(fam.admin, 'b' * 40), isPositive);
    });

    test('a member who is not an admin cannot register a child', () async {
      await expectRejected(() => add(fam.member, 'Nina'),
          contains: 'Somente administradores');
    });

    test('the member READS the family children', () async {
      final rows = await fam.member.from('children').select('first_name');
      expect([for (final r in rows) r['first_name']],
          containsAll(['Maria Clara', 'Theo']));
    });

    test('no client writes the table directly', () async {
      await expectRejected(() async {
        await fam.admin.from('children').insert({
          'family_id': fam.familyId,
          'first_name': 'Direto',
        });
      });
      final theo = (await childrenOf(fam.familyId))
          .firstWhere((r) => r['first_name'] == 'Theo');
      // An UPDATE with no grant touches nothing (PostgREST answers an error).
      await expectRejected(() async {
        await fam.admin
            .from('children')
            .update({'first_name': 'Outro'}).eq('id', theo['id'] as int);
      });
      expect((await childrenOf(fam.familyId))
          .firstWhere((r) => r['id'] == theo['id'])['first_name'], 'Theo');
    });

    test('another family neither reads nor renames nor removes it', () async {
      final theoId = (await childrenOf(fam.familyId))
          .firstWhere((r) => r['first_name'] == 'Theo')['id'] as int;
      final seen = await fx.founderB.from('children').select('id').eq('id', theoId);
      expect(seen, isEmpty);

      // founderB is an admin of ANOTHER family: the RPCs look only at theirs.
      await expectRejected(
          () => fx.founderB.rpc<dynamic>('rename_child',
              params: {'p_child_id': theoId, 'p_first_name': 'Roubado'}),
          contains: 'não encontrada');
      await expectRejected(
          () => fx.founderB
              .rpc<dynamic>('remove_child', params: {'p_child_id': theoId}),
          contains: 'não encontrada');
    });

    test('an admin renames; a name taken by a sibling is refused', () async {
      final rows = await childrenOf(fam.familyId);
      final theoId = rows.firstWhere((r) => r['first_name'] == 'Theo')['id'];
      await fam.admin.rpc<dynamic>('rename_child',
          params: {'p_child_id': theoId, 'p_first_name': ' Téo '});
      expect(
          (await childrenOf(fam.familyId))
              .firstWhere((r) => r['id'] == theoId)['first_name'],
          'Téo');
      await expectRejected(
          () => fam.admin.rpc<dynamic>('rename_child',
              params: {'p_child_id': theoId, 'p_first_name': 'maria clara'}),
          contains: 'Já existe uma criança com esse nome');
      await expectRejected(
          () => fam.member.rpc<dynamic>('rename_child',
              params: {'p_child_id': theoId, 'p_first_name': 'Nina'}),
          contains: 'Somente administradores');
    });

    test('an admin removes; a second removal says it is gone', () async {
      final rows = await childrenOf(fam.familyId);
      final id = rows.firstWhere((r) => r['first_name'] == 'b' * 40)['id'];
      await expectRejected(
          () => fam.member
              .rpc<dynamic>('remove_child', params: {'p_child_id': id}),
          contains: 'Somente administradores');
      await fam.admin.rpc<dynamic>('remove_child', params: {'p_child_id': id});
      expect((await childrenOf(fam.familyId)).map((r) => r['id']),
          isNot(contains(id)));
      await expectRejected(
          () => fam.admin
              .rpc<dynamic>('remove_child', params: {'p_child_id': id}),
          contains: 'não encontrada');
    });
  });
}

import 'package:entrelares_db_gate/entrelares_db_gate.dart';
import 'package:test/test.dart';

/// F-103 — granting or removing admin is TOLD to the person it happens to:
///   · one `admin_changed` row per real change (kind granted|revoked, name =
///     who did it), with the PT-BR sentence the catalog says;
///   · nothing when the bit does not change (granting an admin again);
///   · never to the actor themself.
void adminBitNoticeTests(GateFixture fx) {
  Future<void> setAdmin(int profileId, bool isAdmin) =>
      fx.founder.rpc<dynamic>('set_member_admin',
          params: {'p_profile_id': profileId, 'p_is_admin': isAdmin});

  Future<List<Map<String, dynamic>>> noticesOf(int profileId) async =>
      List<Map<String, dynamic>>.from(await fx.service
          .from('notifications')
          .select()
          .eq('recipient_profile_id', profileId)
          .eq('type', 'admin_changed')
          .order('id', ascending: true));

  Future<void> clearNotices() => fx.service
      .from('notifications')
      .delete()
      .eq('type', 'admin_changed')
      .inFilter('recipient_profile_id',
          [fx.memberProfile.id, fx.founderProfile.id]);

  group('AdminBitNoticeTests', () {
    test('a grant and a removal each tell the member, once, by name',
        () async {
      await clearNotices();
      await fx.elevate(fx.founderProfile);
      try {
        await setAdmin(fx.memberProfile.id, true);
        // The same value again changes nothing — and tells nothing.
        await setAdmin(fx.memberProfile.id, true);
        await setAdmin(fx.memberProfile.id, false);
      } finally {
        await setAdmin(fx.memberProfile.id, false);
        await fx.clearElevation(fx.founderProfile);
      }

      final rows = await noticesOf(fx.memberProfile.id);
      expect(rows, hasLength(2), reason: 'one per real change');
      final name = fx.founderProfile.fullName.trim();
      expect(rows[0]['params'], {'kind': 'granted', 'name': name});
      expect(rows[0]['title'], 'Você agora é administrador(a)');
      expect(
          rows[0]['message'], '$name tornou você administrador(a) da família.');
      expect(rows[1]['params'], {'kind': 'revoked', 'name': name});
      expect(rows[1]['message'],
          '$name removeu a sua permissão de administrador(a) da família.');

      // The member reads their own notice (RLS), as the app does.
      final own = await fx.member
          .from('notifications')
          .select('id')
          .eq('type', 'admin_changed');
      expect(own, hasLength(2));

      expect(await noticesOf(fx.founderProfile.id), isEmpty,
          reason: 'the actor is never told about their own act');
      await clearNotices();
    });
  });
}

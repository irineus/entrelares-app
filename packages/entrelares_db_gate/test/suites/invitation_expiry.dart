import 'package:entrelares_db_gate/entrelares_db_gate.dart';
import 'package:test/test.dart';

/// F-101 — `invitation_expiry_notices_due()`: the inviting admin is told, ONCE
/// per invitation, that an open invitation expired unanswered. Push + in-app
/// (type `invitation_expired`), no e-mail (F-59). Nothing for an accepted or
/// revoked row, nothing past the 30-day purge window, nothing to an inviter
/// who left, nothing while the family's deletion is pending.
///
/// Every call is scoped to the test's family; expiry is simulated through the
/// service client (`expires_at` backdated), the way the lifecycle suite does.
void invitationExpiryTests(GateFixture fx) {
  Future<int> invite(ThrowawayFamily fam, String tag) async {
    await fx.service.rpc<dynamic>('set_family_plan',
        params: {'p_family_id': fam.familyId, 'p_plan': 'premium'});
    final rows = await fam.admin.rpc<dynamic>('create_invitation', params: {
      'p_email': fx.testEmail(tag),
      'p_role_id': fx.roleId('grandmother'),
    });
    return ((rows is List ? rows.first : rows) as Map)['invitation_id'] as int;
  }

  Future<void> expire(int invitationId) => fx.service
      .from('family_invitations')
      .update({
        'expires_at': DateTime.now()
            .toUtc()
            .subtract(const Duration(hours: 1))
            .toIso8601String()
      })
      .eq('id', invitationId);

  Future<List<Map<String, dynamic>>> run(ThrowawayFamily fam) async {
    final rows = await fx.service.rpc<dynamic>('invitation_expiry_notices_due',
        params: {'p_family_id': fam.familyId});
    return (rows as List).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> notices(int profileId) async =>
      (await fx.service
              .from('notifications')
              .select()
              .eq('recipient_profile_id', profileId)
              .eq('type', 'invitation_expired')
              .order('id', ascending: true))
          .cast<Map<String, dynamic>>();

  group('F-101 · invitation expiry notice', () {
    test('an expired invitation tells the inviter once, in the catalog\'s '
        'words, and stamps the row', () async {
      final fam = await fx.createFamily('f101exp');
      final id = await invite(fam, 'f101-exp');
      expect(await run(fam), isEmpty, reason: 'still valid: nothing to say');

      await expire(id);
      final due = await run(fam);
      expect(due, hasLength(1));
      expect(due.single['invitation_id'], id);
      expect(due.single['profile_id'], fam.adminProfile.id);

      final n = await notices(fam.adminProfile.id);
      expect(n, hasLength(1));
      expect(n.single['title'], 'O convite expirou');
      final email = fx.testEmail('f101-exp');
      expect(n.single['message'],
          '$email não respondeu ao convite e o link expirou. Compartilhe de '
          'novo — um link pelo WhatsApp costuma funcionar melhor.');
      expect(n.single['params'],
          {'kind': 'expired', 'name': email, 'invitation_id': id});

      // The member did not send it and hears nothing.
      expect(await notices(fam.memberProfile.id), isEmpty);

      // Once.
      expect(await run(fam), isEmpty);
      expect(await notices(fam.adminProfile.id), hasLength(1));
      final row = (await fx.service
              .from('family_invitations')
              .select('expiry_notified_at')
              .eq('id', id))
          .single;
      expect(row['expiry_notified_at'], isNotNull);
    });

    test('a placeholder\'s invitation names the person, not the address (F-56)',
        () async {
      final fam = await fx.createFamily('f101ph');
      await fx.service.rpc<dynamic>('set_family_plan',
          params: {'p_family_id': fam.familyId, 'p_plan': 'premium'});
      final born = await fam.admin.rpc<dynamic>('add_pending_member', params: {
        'p_full_name': 'Vovó Lurdes',
        'p_role_id': fx.roleId('grandmother'),
        'p_email': fx.testEmail('f101-ph'),
      });
      final id = ((born is List ? born.first : born) as Map)['invitation_id'] as int;
      await expire(id);

      expect(await run(fam), hasLength(1));
      final n = await notices(fam.adminProfile.id);
      expect(n.single['params']['name'], 'Vovó Lurdes');
      expect(n.single['message'], startsWith('Vovó Lurdes não respondeu'));
    });

    test('a revoked or accepted invitation is nobody\'s news', () async {
      final fam = await fx.createFamily('f101rev');
      final id = await invite(fam, 'f101-rev');
      await fam.admin
          .rpc<dynamic>('revoke_invitation', params: {'p_invitation_id': id});
      await expire(id);
      expect(await run(fam), isEmpty);
      expect(await notices(fam.adminProfile.id), isEmpty);
    });

    test('past the 30-day purge window the card is gone, so is the notice',
        () async {
      final fam = await fx.createFamily('f101old');
      final id = await invite(fam, 'f101-old');
      await fx.service.from('family_invitations').update({
        'created_at': DateTime.now()
            .toUtc()
            .subtract(const Duration(days: 31))
            .toIso8601String(),
        'expires_at': DateTime.now()
            .toUtc()
            .subtract(const Duration(days: 24))
            .toIso8601String(),
      }).eq('id', id);
      expect(await run(fam), isEmpty);
    });

    test('a resend is a new row and may be told again', () async {
      final fam = await fx.createFamily('f101again');
      final first = await invite(fam, 'f101-again');
      await expire(first);
      expect(await run(fam), hasLength(1));

      // Resend = create_invitation for the same address: the old row is
      // revoked, the new one is open again.
      final second = await invite(fam, 'f101-again');
      expect(second, isNot(first));
      expect(await run(fam), isEmpty, reason: 'the new link is still valid');
      await expire(second);
      expect(await run(fam), hasLength(1));
      expect(await notices(fam.adminProfile.id), hasLength(2));
    });
  });
}

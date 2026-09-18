import 'package:entrelares_db_gate/entrelares_db_gate.dart';
import 'package:supabase/supabase.dart';
import 'package:test/test.dart';

import '_helpers.dart';

/// U-50 — `session_has_password()`: the one fact about an account the client
/// cannot read for itself.
///
/// The profile screen used to infer it from `app_metadata.providers` ("no
/// `email` among them, so no password"). Production carries the counter-proof
/// — providers `["google"]` alone, and a password. The gate cannot forge a
/// Google provider, but it can build the mirror image: the `email` provider
/// with NO password. What the suite pins is that the answer follows
/// `encrypted_password` and is indifferent to the provider list, in both
/// directions.
///
/// The trap this suite found on its first two runs: GoTrue writes a RANDOM
/// password both when the Admin API creates a user without one (the S-21
/// "password-less" fixture) and when an invite link is redeemed. Unknown to
/// everyone, which is all the sudo gate cared about — and non-empty, which is
/// all this function can read. So `true` means "a credential is stored", never
/// "the person knows one"; `AdminApi.noPasswordSession` is the one path found
/// that leaves the column empty.
void sessionHasPasswordTests(GateFixture fx) {
  Future<bool> ask(SupabaseClient who) async =>
      await who.rpc<dynamic>('session_has_password') as bool;

  group('SessionHasPasswordTests', () {
    test('a password-backed session is told it has a password', () async {
      expect(await ask(fx.founder), isTrue);
      expect(await ask(fx.member), isTrue);
    });

    test('an account with the `email` provider and NO password is told it has '
        'none — and is told otherwise the moment one exists, with the '
        'providers untouched', () async {
      final who = await fx.createNoPasswordSession('u50');

      // The guess the screen used to make would have said "has a password":
      // the provider list names `email`.
      final before = await fx.service.auth.admin.getUserById(who.userId);
      final providersBefore = before.user!.appMetadata['providers'];
      expect(providersBefore, contains('email'),
          reason: 'the fixture no longer builds the email-provider shape');

      expect(await ask(who.client), isFalse);

      // The production shape in reverse order: the credential appears and the
      // provider list does not move. Same session, same token.
      await fx.service.auth.admin.updateUserById(who.userId,
          attributes: AdminUserAttributes(password: fx.password));
      final after = await fx.service.auth.admin.getUserById(who.userId);
      expect(after.user!.appMetadata['providers'], providersBefore);

      expect(await ask(who.client), isTrue);
    });

    test('the anon key without a session may not ask', () async {
      final anon = fx.newAnonClient();
      try {
        await expectRejected(() => anon.rpc<dynamic>('session_has_password'));
      } finally {
        await anon.dispose();
      }
    });

    test('there is no way to ask about somebody else', () async {
      // The function takes no argument by design. PostgREST resolves an RPC by
      // its named parameters, so a caller who invents one finds no function.
      await expectRejected(() => fx.founder.rpc<dynamic>('session_has_password',
          params: {'p_user_id': fx.memberProfile.userId}));
    });
  });
}

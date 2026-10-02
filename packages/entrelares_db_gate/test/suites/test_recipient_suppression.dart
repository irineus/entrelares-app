import 'dart:convert';

import 'package:entrelares_db_contracts/entrelares_db_contracts.dart';
import 'package:entrelares_db_gate/entrelares_db_gate.dart';
import 'package:http/http.dart' as http;
import 'package:supabase/supabase.dart';
import 'package:test/test.dart';

/// T-49 — the suites drive the REAL flows, so every run used to hand the
/// fixture's throwaway addresses to Resend for real: ~86 e-mails a day, all from
/// CI, against the allowance PRODUCTION shares (one Resend account, one domain —
/// including the GoTrue SMTP that sends sign-up confirmations). The functions now
/// suppress the outbound call for `@resend.dev` recipients.
///
/// This is the red gate for that. Without it the guard is invisible when it
/// regresses: nothing in the app reads the functions' response, and no test ever
/// asserted delivery — the quota would simply start bleeding again, and the first
/// sign would be a Resend warning days later. The casualty of a 429 in production
/// is not a red test: it is a real user who cannot confirm a sign-up or reset a
/// password, with nothing surfacing the failure.
///
/// It asserts the DISTINCTION, not merely "nothing was sent": `suppressed` must
/// COUNT the message and `failed` must stay zero, which is what proves the send
/// was skipped on purpose rather than broken.
///
/// Port of `db-gate/Entrelares.IntegrationTests/TestRecipientSuppressionTests.cs`.
void testRecipientSuppressionTests(GateFixture fx) {
  Future<http.Response> callSendSwapEmail(
      SupabaseClient client, Map<String, Object?> payload) {
    // S-16: the app calls with the publishable key on `apikey` and the user's
    // session on Authorization — the same shape the function's own check
    // expects.
    final accessToken = client.auth.currentSession?.accessToken;
    expect(accessToken, isNotNull,
        reason: 'the client has no session — the fixture sign-in did not '
            'complete');
    return http.post(
      Uri.parse('${TestEnv.supabaseUrl.replaceAll(RegExp(r'/+$'), '')}'
          '/functions/v1/send-swap-email'),
      headers: {
        'apikey': TestEnv.anonKey,
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(payload),
    );
  }

  group('TestRecipientSuppressionTests', () {
    test('an invitation e-mail to a test recipient is suppressed, not failed',
        () async {
      // F-59: the invitation is the one message send-swap-email still sends,
      // so it is the path this guard watches. A Premium family has a free
      // seat for a third caregiver; the address is the fixture's @resend.dev.
      final fam = await fx.createFamily('t49inv');
      await fx.service.rpc<dynamic>('set_family_plan',
          params: {'p_family_id': fam.familyId, 'p_plan': 'premium'});
      final rows = await fam.admin.rpc<dynamic>('create_invitation', params: {
        'p_email': fx.testEmail('t49-invite'),
        'p_role_id': fx.roleId('grandmother'),
      });
      final invitationId = ((rows is List ? rows.first : rows)
          as Map)['invitation_id'] as int;

      final response = await callSendSwapEmail(fam.admin, {
        'invitationId': invitationId,
        'emailType': 'invitation',
        'environmentPrefix': '[T-49] ',
      });

      expect(response.statusCode, 200,
          reason: 'send-swap-email answered ${response.statusCode} '
              '(expected 200). Body: ${response.body}');

      final body = jsonDecode(response.body) as Map<String, dynamic>;

      expect(body['suppressed'], isNotNull,
          reason: "the response carries no 'suppressed' count — the T-49 guard "
              'is gone and the fixture e-mails are reaching Resend again. '
              'Body: ${response.body}');
      expect(body['suppressed'], 1,
          reason: 'expected the test recipient to be suppressed. '
              'Body: ${response.body}');
      expect(body['sent'], 0);
      expect(body['failed'], 0);
    });

    test('a swap e-mail is no longer sent at all — push and in-app only',
        () async {
      // F-59 (02/10/2026): the swap workflow left e-mail. Android builds in
      // Production still dispatch it from the client after every action, so
      // the function answers 200 and says why nothing went out — never a 400
      // the app would log as a failure.
      final request = SwapRequest.fromJson((await fx.member
              .from('swap_requests')
              .insert({
                'schedule_date': isoDate(fx.nextFutureDate()),
                'requesting_profile_id': fx.memberProfile.id,
                'target_profile_id': fx.founderProfile.id,
                'previous_actual_parent_id': null,
                'proposed_actual_parent_id': fx.memberProfile.id,
                'status': 'pending',
              })
              .select())
          .single);

      final response = await callSendSwapEmail(fx.member, {
        'swapRequestId': request.id,
        'emailType': 'swap_requested',
        'environmentPrefix': '[T-49] ',
      });

      expect(response.statusCode, 200, reason: response.body);
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      expect(body['skipped'], 'push_only', reason: response.body);
      expect(body['sent'], 0);
      expect(body['suppressed'], 0,
          reason: 'nothing reached the recipient check — there is no e-mail '
              'to suppress any more.');
    });
  });
}

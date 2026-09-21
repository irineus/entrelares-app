import 'dart:convert';

import 'package:entrelares_db_gate/entrelares_db_gate.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import '_helpers.dart';

/// F-68 — Help & contact: `send-support-request` and the `support_requests`
/// table behind it.
///
/// It calls the DEPLOYED function on the dev project exactly as the `/help`
/// screen does: the anon key alone when signed out, the anon key plus the
/// member's access token when signed in. Every reply address here is on
/// `@resend.dev`, so the function suppresses BOTH e-mails (T-49) — the team's
/// inbox included — and records no IP hash, so the CI runner's shared IP never
/// counts against the next run. That makes the IP limit unreachable end to end
/// on purpose; it is asserted at the RPC, with a synthetic hash, where the
/// function hands it the same numbers.
///
/// What this suite cannot see is Resend accepting the message, the Reply-To
/// header or the rendered confirmation — that is the owner's check on the inbox
/// (card F-68, handoff).
void supportRequestTests(GateFixture fx) {
  final endpoint = Uri.parse(
      '${TestEnv.supabaseUrl.replaceAll(RegExp(r'/+$'), '')}/functions/v1/send-support-request');

  Future<(int, Map<String, dynamic>)> post(Map<String, dynamic> payload,
      {String? accessToken}) async {
    final response = await http.post(
      endpoint,
      headers: {
        ...TestEnv.keyHeaders(TestEnv.anonKey),
        if (accessToken != null) 'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(payload),
    );
    final body = response.body.isEmpty
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    return (response.statusCode, body);
  }

  Future<Map<String, dynamic>> rowOf(int id) async =>
      Map<String, dynamic>.from((await fx.service
              .from('support_requests')
              .select()
              .eq('id', id))
          .single as Map);

  /// Same numbers the function passes (`ANON_*` in its index.ts).
  Future<Map<String, dynamic>> record({
    required String email,
    String? ipHash,
    int? profileId,
    int hourLimit = 3,
    int dayLimit = 10,
  }) async {
    final result = await fx.service.rpc<dynamic>('record_support_request', params: {
      'p_profile_id': profileId,
      'p_family_id': null,
      'p_category': 'other',
      'p_reply_email': email,
      'p_message': 'Mensagem do gate, só para contar.',
      'p_diagnostics': null,
      'p_language': 'pt-BR',
      'p_ip_hash': ipHash,
      'p_hour_limit': hourLimit,
      'p_day_limit': dayLimit,
    });
    final row = result is List ? result.first : result;
    return Map<String, dynamic>.from(row as Map);
  }

  final touchedEmails = <String>{};
  final touchedIps = <String>{};
  final touchedProfiles = <int>{};

  tearDownAll(() async {
    for (final e in touchedEmails) {
      await fx.service.from('support_requests').delete().eq('reply_email', e);
    }
    for (final ip in touchedIps) {
      await fx.service.from('support_requests').delete().eq('ip_hash', ip);
    }
    for (final p in touchedProfiles) {
      await fx.service.from('support_requests').delete().eq('profile_id', p);
    }
  });

  group('SupportRequestTests', () {
    test('signed out: the request is recorded with the typed address, and '
        'only the allowed diagnostics survive', () async {
      final email = fx.testEmail('support-anon');
      touchedEmails.add(email);

      final (status, body) = await post({
        'category': 'problem',
        'message': '  O calendário não abre no meu celular.  ',
        'replyEmail': email,
        'language': 'en',
        'diagnostics': {
          'appVersion': '2.7.4+124',
          'channel': 'web',
          'route': '/register?invite=SEGREDO#access_token=x',
          'familyName': 'nunca deveria chegar',
        },
      });
      expect(status, 200, reason: '$body');
      final row = await rowOf(body['requestId'] as int);

      expect(row['profile_id'], isNull);
      expect(row['family_id'], isNull);
      expect(row['reply_email'], email);
      expect(row['category'], 'problem');
      expect(row['message'], 'O calendário não abre no meu celular.');
      expect(row['language'], 'en');
      expect(row['status'], 'open');
      // A test address records no IP — see the suite's doc comment.
      expect(row['ip_hash'], isNull);
      expect(row['diagnostics'], {
        'appVersion': '2.7.4+124',
        'channel': 'web',
        'route': '/register',
      });
    });

    test('signed in: the reply address is the ACCOUNT\'s, whatever the client '
        'sends', () async {
      final token = fx.founder.auth.currentSession!.accessToken;
      touchedProfiles.add(fx.founderProfile.id);

      final (status, body) = await post({
        'category': 'question',
        'message': 'Como faço para trocar um dia com o outro responsável?',
        'replyEmail': 'outra-pessoa@exemplo.com',
      }, accessToken: token);
      expect(status, 200, reason: '$body');
      final row = await rowOf(body['requestId'] as int);

      expect(row['reply_email'], fx.founderProfile.email);
      expect(row['profile_id'], fx.founderProfile.id);
      expect(row['family_id'], fx.founderProfile.familyId);
      expect(row['diagnostics'], isNull);
    });

    test('invalid input is refused before anything is recorded', () async {
      final email = fx.testEmail('support-invalid');
      touchedEmails.add(email);

      final short = await post(
          {'category': 'other', 'message': 'curta', 'replyEmail': email});
      expect(short.$1, 400);
      expect(short.$2['error'], 'invalid_message');

      final long = await post(
          {'category': 'other', 'message': 'a' * 2001, 'replyEmail': email});
      expect(long.$2['error'], 'invalid_message');

      final category = await post({
        'category': 'billing',
        'message': 'Uma mensagem longa o bastante.',
        'replyEmail': email,
      });
      expect(category.$2['error'], 'invalid_category');

      final badEmail = await post({
        'category': 'other',
        'message': 'Uma mensagem longa o bastante.',
        'replyEmail': 'sem-arroba',
      });
      expect(badEmail.$2['error'], 'invalid_email');

      final rows =
          await fx.service.from('support_requests').select('id').eq('reply_email', email);
      expect(rows, isEmpty);
    });

    test('signed out: the 4th message from one address in an hour is refused',
        () async {
      final email = fx.testEmail('support-limit');
      touchedEmails.add(email);
      final payload = {
        'category': 'suggestion',
        'message': 'Seria bom poder exportar o mês em imagem.',
        'replyEmail': email,
      };

      for (var i = 0; i < 3; i++) {
        final (status, body) = await post(payload);
        expect(status, 200, reason: 'message ${i + 1}: $body');
      }
      final (status, body) = await post(payload);
      expect(status, 429);
      expect(body['error'], 'rate_limited');
    });

    test('the IP limit holds across different addresses (at the RPC)',
        () async {
      final ip = 'gate-ip-${fx.runId}';
      touchedIps.add(ip);
      for (var i = 0; i < 3; i++) {
        final email = fx.testEmail('support-ip-$i');
        touchedEmails.add(email);
        expect((await record(email: email, ipHash: ip))['status'], 'ok');
      }
      final fourth = fx.testEmail('support-ip-3');
      touchedEmails.add(fourth);
      expect((await record(email: fourth, ipHash: ip))['status'], 'rate_limited');
    });

    test('an undelivered request does not count, so the person can retry',
        () async {
      final email = fx.testEmail('support-undelivered');
      touchedEmails.add(email);
      for (var i = 0; i < 3; i++) {
        final r = await record(email: email);
        await fx.service
            .from('support_requests')
            .update({'status': 'undelivered'}).eq('id', r['request_id'] as int);
      }
      expect((await record(email: email))['status'], 'ok');
    });

    test('retention removes requests older than 12 months, and only those',
        () async {
      final email = fx.testEmail('support-retention');
      touchedEmails.add(email);
      final old = await record(email: email);
      final fresh = await record(email: email);
      await fx.service.from('support_requests').update({
        'created_at': DateTime.now()
            .toUtc()
            .subtract(const Duration(days: 370))
            .toIso8601String(),
      }).eq('id', old['request_id'] as int);

      await fx.service.rpc<dynamic>('purge_old_support_requests');

      final left = await fx.service
          .from('support_requests')
          .select('id')
          .eq('reply_email', email);
      expect(left.map((r) => r['id']), [fresh['request_id']]);
    });

    // ── The security property ───────────────────────────────────────────────

    test('no client can read the requests or record one directly', () async {
      // No grant at all to `authenticated`/`anon`: PostgREST refuses with 42501
      // before any policy — stronger than an empty read, which a table with no
      // rows would also give.
      await expectRejected(
        () => fx.founder.from('support_requests').select(),
        contains: 'permission denied',
        caseInsensitive: true,
      );
      await expectRejected(
        () => fx.newAnonClient().from('support_requests').select(),
        contains: 'permission denied',
        caseInsensitive: true,
      );
      await expectRejected(
        () => fx.founder.rpc<dynamic>('record_support_request', params: {
          'p_profile_id': null,
          'p_family_id': null,
          'p_category': 'other',
          'p_reply_email': 'x@exemplo.com',
          'p_message': 'Tentativa direta pelo cliente.',
          'p_diagnostics': null,
          'p_language': null,
          'p_ip_hash': null,
          'p_hour_limit': 1000,
          'p_day_limit': 1000,
        }),
      );
      await expectRejected(
          () => fx.founder.rpc<dynamic>('purge_old_support_requests'));
    });
  });
}

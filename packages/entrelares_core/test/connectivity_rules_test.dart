import 'package:entrelares_core/entrelares_core.dart';
import 'package:test/test.dart';

void main() {
  final ptBr = Localization(AppLanguage.ptBr);
  final en = Localization(AppLanguage.en);

  group('isNetworkFailure — the transport failing, not the server answering', () {
    test('the shapes each layer of the stack actually throws are offline', () {
      for (final raw in [
        // package:http on native, wrapping the socket error.
        "ClientException with SocketException: Failed host lookup: "
            "'x.supabase.co' (OS Error: No address associated with hostname, "
            "errno = 7), uri=https://x.supabase.co/rest/v1/care_schedules",
        // package:http on the web — the browser gives no detail at all.
        'ClientException: XMLHttpRequest error., uri=https://x.supabase.co/rest/v1/profiles',
        'SocketException: Network is unreachable',
        'SocketException: Connection refused',
        'HandshakeException: Connection terminated during handshake',
        // postgrest's own per-attempt timeout.
        'TimeoutException after 0:00:10.000000: Request timed out',
        // gotrue's way of saying "no network" on a token refresh.
        'AuthRetryableFetchException(message: ClientException with '
            'SocketException: Failed host lookup, statusCode: null)',
        'ClientException: Connection closed before full header was received',
      ]) {
        expect(isNetworkFailure(raw), isTrue, reason: raw);
      }
    });

    test('the server ANSWERING is never offline, however it failed', () {
      for (final raw in [
        // RLS without a session — "sessão expirada", not "sem conexão".
        'PostgrestException(message: permission denied for table profiles, '
            'code: 42501, details: Forbidden, hint: null)',
        // A trigger's own sentence.
        'PostgrestException(message: Outro membro salvou este dia primeiro., '
            'code: P0001, details: null, hint: null)',
        // A refresh token that is DEAD — this one must sign the reader out.
        'AuthApiException(message: Invalid Refresh Token: Refresh Token Not '
            'Found, statusCode: 400, code: refresh_token_not_found)',
        'FormatException: Unexpected character',
        '',
      ]) {
        expect(isNetworkFailure(raw), isFalse, reason: raw);
      }
    });

    test('a server message that merely MENTIONS a timeout is still an answer',
        () {
      // The PostgrestException guard: a statement_timeout raised by the
      // database comes back from our server, so the network is fine.
      expect(
          isNetworkFailure('PostgrestException(message: canceling statement '
              'due to statement timeout (TimeoutException), code: 57014, '
              'details: null, hint: null)'),
          isFalse);
    });
  });

  group('isServerResponse — did the answer come from OUR server?', () {
    test('JSON and empty bodies are ours', () {
      expect(isServerResponse(contentType: 'application/json; charset=utf-8'),
          isTrue);
      expect(
          isServerResponse(
              contentType: 'application/vnd.pgrst.object+json; charset=utf-8'),
          isTrue);
      // A 204 from a minimal-return write carries no content type at all.
      expect(isServerResponse(contentType: null), isTrue);
    });

    test('an HTML page in its place is a captive portal or an edge error', () {
      expect(isServerResponse(contentType: 'text/html; charset=UTF-8'), isFalse);
      expect(isServerResponse(contentType: 'TEXT/HTML'), isFalse);
    });
  });

  group('ConnectivitySnapshot — two states, and the age survives the loss', () {
    final nineOClock = DateTime(2026, 9, 14, 9, 0);

    test('it starts online with nothing loaded', () {
      expect(ConnectivitySnapshot.initial.offline, isFalse);
      expect(ConnectivitySnapshot.initial.dataAsOf, isNull);
    });

    test('losing the server keeps the moment the data was read', () {
      final s = ConnectivitySnapshot.initial.loadedData(nineOClock).lostServer();
      expect(s.offline, isTrue);
      expect(s.dataAsOf, nineOClock);
    });

    test('reaching the server again goes back online, age intact', () {
      final s = ConnectivitySnapshot.initial
          .loadedData(nineOClock)
          .lostServer()
          .reachedServer();
      expect(s.offline, isFalse);
      expect(s.dataAsOf, nineOClock);
    });

    test('transitions that change nothing return the SAME snapshot', () {
      // The app's notifier compares by value; a no-op must not repaint.
      final online = ConnectivitySnapshot.initial.loadedData(nineOClock);
      expect(identical(online.reachedServer(), online), isTrue);
      final offline = online.lostServer();
      expect(identical(offline.lostServer(), offline), isTrue);
    });

    test('a load while offline dates the data without claiming the network',
        () {
      // PR 2's cache serves a load with no server behind it.
      final s = ConnectivitySnapshot.initial.lostServer().loadedData(nineOClock);
      expect(s.offline, isTrue);
      expect(s.dataAsOf, nineOClock);
    });

    test('signing out forgets the age, never the network state', () {
      final s = ConnectivitySnapshot.initial
          .loadedData(nineOClock)
          .lostServer()
          .forgetData();
      expect(s.offline, isTrue);
      expect(s.dataAsOf, isNull);
    });
  });

  group('offlineStripText — how OLD what is on screen is', () {
    final now = DateTime(2026, 9, 14, 10, 30);

    test('data read today names the time alone, per language (U-24)', () {
      final asOf = DateTime(2026, 9, 14, 8, 12);
      expect(offlineStripText(ptBr, dataAsOf: asOf, now: now),
          'Sem conexão · dados de 08:12');
      expect(offlineStripText(en, dataAsOf: asOf, now: now),
          'Offline · data from 8:12 AM');
    });

    test('data from an earlier day names the day too', () {
      // "08:12" on Monday about Friday's plan is the mistake the strip exists
      // to prevent.
      final friday = DateTime(2026, 9, 11, 18, 5);
      expect(offlineStripText(ptBr, dataAsOf: friday, now: now),
          'Sem conexão · dados de 11/09 18:05');
      expect(offlineStripText(en, dataAsOf: friday, now: now),
          'Offline · data from 11 Sep 6:05 PM');
    });

    test('same time of day, different day, is still a different day', () {
      final yesterday = DateTime(2026, 9, 13, 10, 30);
      expect(offlineStripText(ptBr, dataAsOf: yesterday, now: now),
          contains('13/09'));
    });

    test('nothing loaded yet dates nothing', () {
      expect(offlineStripText(ptBr, dataAsOf: null, now: now),
          'Sem conexão · nada carregado ainda');
      expect(offlineStripText(en, dataAsOf: null, now: now),
          'Offline · nothing loaded yet');
    });
  });
}

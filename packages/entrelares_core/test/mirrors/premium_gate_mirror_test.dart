/// F-102 + F-08 — the Premium gate tokens live in THREE languages.
///
/// A non-admin who meets a gate asks the admins (`request_premium_from_admin`),
/// and the notification says what was wanted: "Bruno quer o Premium para
/// exportar para outro calendário". The token list and its words exist in:
///   * Dart — `PremiumAskRules.gates` and `gateLabelKey`, the catalog's
///     `notifRender.premiumGate.*` (the in-app rendering);
///   * the migration — the `IN (...)` that accepts a token and the `CASE` that
///     STORES the PT-BR sentence (what an old client reads);
///   * `_shared/push.ts` — the push body's own map.
///
/// Each side can grow alone and each failure is silent: a token the server
/// does not list is stored as the generic `premium` ("quer o Premium para a
/// família"), with every build green. F-08 added the sixth token, and this
/// suite is what makes the next one land on all three sides.
library;

import 'dart:io';

import 'package:entrelares_core/entrelares_core.dart';
import 'package:test/test.dart';

import 'repo_files.dart';

/// The newest migration body defining `request_premium_from_admin` — the last
/// CREATE OR REPLACE wins, as in the other function mirrors.
String _liveBody() {
  final files = migrationsDirectory()
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.sql'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  String? body;
  for (final file in files) {
    final sql = file.readAsStringSync();
    final start = sql.indexOf(RegExp(
        r'CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.request_premium_from_admin'));
    if (start == -1) continue;
    final end = sql.indexOf('\n\$\$;', start);
    body = end == -1 ? sql.substring(start) : sql.substring(start, end);
  }
  if (body == null) {
    throw StateError('no migration defines request_premium_from_admin().');
  }
  return body;
}

void main() {
  final body = _liveBody();
  final pt = Localization(AppLanguage.ptBr);

  test('the server accepts exactly the tokens PremiumAskRules sends', () {
    final inList = RegExp(r"p_gate IN \(([^)]*)\)").firstMatch(body);
    expect(inList, isNotNull, reason: 'the IN (...) list moved or vanished');
    final serverTokens = RegExp(r"'([a-z-]+)'")
        .allMatches(inList!.group(1)!)
        .map((m) => m.group(1)!)
        .toSet();
    expect(serverTokens, PremiumAskRules.gates);
  });

  test('the stored PT-BR label of every token is the catalog\'s, byte for '
      'byte', () {
    for (final gate in PremiumAskRules.gates) {
      final when = RegExp("WHEN '${RegExp.escape(gate)}'\\s+THEN '([^']*)'")
          .firstMatch(body);
      expect(when, isNotNull, reason: 'no CASE branch for "$gate"');
      expect(when!.group(1), pt[PremiumAskRules.gateLabelKey(gate)],
          reason: 'the stored sentence and the in-app one differ for "$gate"');
    }
  });

  test('push.ts maps every token to its own words, not the generic ones', () {
    final push = repoFile('supabase/functions/_shared/push.ts');
    for (final gate in PremiumAskRules.gates) {
      expect(push, contains('gate === "$gate" ? K.premiumGate'),
          reason: 'push.ts renders "$gate" as the generic family words');
      final key = PremiumAskRules.gateLabelKey(gate);
      expect(push, contains('"$key": "${pt[key]}"'),
          reason: 'push.ts PT-BR text for $key differs from the catalog');
    }
  });
}

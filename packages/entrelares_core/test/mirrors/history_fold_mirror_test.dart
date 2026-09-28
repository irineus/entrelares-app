/// F-76 — the Histórico search matches on the SERVER (`search_history`,
/// SECURITY INVOKER), and the Conversa's search matches on the client
/// (`ChatRules.matches`). One rule, two languages: `history_fold` is the SQL
/// mirror of `ChatRules.fold`, and this test reads the NEWEST migration that
/// defines it and pins its `translate()` map to `ChatRules.foldMap`, both
/// cases. Drift here means "ônibus" finds a relato in the Conversa and not in
/// the Histórico, with both sides compiling. The DB gate compares outputs
/// byte for byte on a real database; this is the cheap half.
library;

import 'dart:io';

import 'package:entrelares_core/entrelares_core.dart';
import 'package:test/test.dart';

import 'repo_files.dart';

String _liveFoldBody() {
  final files = migrationsDirectory()
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.sql'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  final bodies = <String>[];
  for (final file in files) {
    final sql = file.readAsStringSync();
    final start = sql.indexOf(
        RegExp(r'CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.history_fold\('));
    if (start == -1) continue;
    final end = sql.indexOf('\n\$\$;', start);
    bodies.add(end == -1 ? sql.substring(start) : sql.substring(start, end));
  }
  if (bodies.isEmpty) throw StateError('no migration defines history_fold().');
  return bodies.last;
}

void main() {
  final body = _liveFoldBody();
  // The two literals after the text: the map is the last two quoted strings
  // inside translate(...), whatever expression the text is.
  final m = RegExp(r"translate\(.*?'([^']{8,})',\s*'([^']{8,})'\)", dotAll: true)
      .firstMatch(body);

  test('history_fold is lower(translate(...)) with a literal map', () {
    expect(m, isNotNull, reason: 'history_fold must fold with a literal translate()');
    expect(body, contains('lower('));
  });

  test('the SQL map is ChatRules.foldMap, in both cases, pair by pair', () {
    final from = m!.group(1)!.runes.map(String.fromCharCode).toList();
    final to = m.group(2)!.runes.map(String.fromCharCode).toList();
    expect(from.length, to.length,
        reason: 'translate() pairs characters by position');
    final sqlMap = {for (var i = 0; i < from.length; i++) from[i]: to[i]};

    for (final MapEntry(key: accented, value: plain) in ChatRules.foldMap.entries) {
      expect(sqlMap[accented], plain, reason: '$accented in lower case');
      expect(sqlMap[accented.toUpperCase()], plain,
          reason: '${accented.toUpperCase()} in upper case');
    }
    // And nothing the Dart side does not fold.
    for (final accented in sqlMap.keys) {
      expect(ChatRules.foldMap[accented.toLowerCase()], isNotNull,
          reason: '$accented is folded in SQL but not by ChatRules');
    }
  });
}

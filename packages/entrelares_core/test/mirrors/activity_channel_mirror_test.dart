/// T-78 — the activity channels and the retention period are declared by the
/// MIGRATION (`member_activity_days.channel` CHECK, `touch_activity`'s own
/// guard, `purge_old_member_activity`'s window) and copied into
/// `ActivityRules` / `ActivityChannel` so the client can name what it sends.
///
/// Why a drift here is the silent kind: the app calls `touch_activity`
/// fire-and-forget — a failure is swallowed on purpose, because no signal is a
/// state (T-18). So a channel the server refused would not be an error anyone
/// sees; it would be a channel that stops existing in the data, and F-69 would
/// read "this member stopped using the app" off a spelling mistake.
library;

import 'dart:io';

import 'package:entrelares_core/entrelares_core.dart';
import 'package:test/test.dart';

import 'repo_files.dart';

/// Every migration that mentions [needle], newest last — the LAST one is what
/// production runs, exactly as the CLI applies them.
String _latestMigrationWith(String needle) {
  final files = migrationsDirectory()
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.sql'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  final hits = files.where((f) => f.readAsStringSync().contains(needle));
  expect(hits, isNotEmpty,
      reason: 'No migration mentions `$needle`. If it was renamed, rename it '
          'here too.');
  return hits.last.readAsStringSync();
}

Set<String> _inList(String source, String anchor) {
  final match = RegExp('${RegExp.escape(anchor)}\\s+IN\\s*\\(([^)]*)\\)')
      .firstMatch(source);
  expect(match, isNotNull, reason: '`$anchor IN (...)` not found.');
  return RegExp("'([^']+)'")
      .allMatches(match!.group(1)!)
      .map((m) => m.group(1)!)
      .toSet();
}

void main() {
  final wires = ActivityChannel.values.map((c) => c.wire).toSet();

  test('the table CHECK accepts exactly the channels the client can send', () {
    final table = _latestMigrationWith('public.member_activity_days (');
    expect(_inList(table, 'CHECK (channel'), wires);
  });

  test('touch_activity guards the same channels as the CHECK', () {
    final rpc = _latestMigrationWith('FUNCTION public.touch_activity(');
    expect(_inList(rpc, 'p_channel NOT'), wires);
  });

  test('the purge keeps the days the policy promises', () {
    final purge =
        _latestMigrationWith('FUNCTION public.purge_old_member_activity(');
    final window = RegExp(r'day\s*<\s*today\s*-\s*(\d+)').firstMatch(purge);
    expect(window, isNotNull,
        reason: '`day < today - <days>` not found in purge_old_member_activity.');
    expect(int.parse(window!.group(1)!), ActivityRules.retentionDays,
        reason: 'The retention is printed in §11 of privacidade.html — moving '
            'it here means moving the policy text in the same delivery.');
  });
}

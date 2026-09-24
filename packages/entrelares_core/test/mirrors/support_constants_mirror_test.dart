/// F-68 — the numbers of the support door are declared ONCE, in
/// `supabase/functions/send-support-request/index.ts`, and copied into
/// `SupportRules` so the form can refuse and explain without a round-trip.
/// This suite reads that file and fails when the copies drift.
///
/// Why it earns its place, in the terms of the mirrors beside it: Deno cannot
/// call Dart, and every drift here is SILENT. Lower the server's minimum and the
/// form keeps refusing a message the server would take; raise the maximum on
/// the client alone and a long report is typed, sent and answered
/// `invalid_message` — after the person wrote it. Change the limit and the
/// screen keeps promising a number the server no longer honours. The person
/// affected is, by construction, someone who was already stuck.
library;

import 'dart:io';

import 'package:entrelares_core/entrelares_core.dart';
import 'package:test/test.dart';

import 'repo_files.dart';

const _functionPath = 'supabase/functions/send-support-request/index.ts';

int _readTsNumber(String name) {
  final match = RegExp('const\\s+${RegExp.escape(name)}\\s*=\\s*(\\d+)\\s*;')
      .firstMatch(repoFile(_functionPath));
  expect(match, isNotNull,
      reason: '`const $name = <number>` not found in $_functionPath. If it was '
          'renamed, rename it here too — these numbers have exactly one home.');
  return int.parse(match!.group(1)!);
}

void main() {
  test('the message bounds are the same on both sides', () {
    expect(SupportRules.messageMinChars, _readTsNumber('MESSAGE_MIN_CHARS'));
    expect(SupportRules.messageMaxChars, _readTsNumber('MESSAGE_MAX_CHARS'));
    expect(SupportRules.emailMaxChars, _readTsNumber('EMAIL_MAX_CHARS'));
  });

  test('the limits are the same on both sides', () {
    expect(SupportRules.anonHourlyLimit, _readTsNumber('ANON_HOURLY_LIMIT'));
    expect(SupportRules.anonDailyLimit, _readTsNumber('ANON_DAILY_LIMIT'));
    expect(SupportRules.memberHourlyLimit, _readTsNumber('MEMBER_HOURLY_LIMIT'));
    expect(SupportRules.memberDailyLimit, _readTsNumber('MEMBER_DAILY_LIMIT'));
  });

  test('the function hands the OPERATOR limits to the RPC', () {
    // T-83: the limits are `support.*` in app_settings; the constants are only
    // the fallbacks. Agreeing constants are worth nothing if the call used a
    // literal, or a constant instead of the key.
    final source = repoFile(_functionPath);
    expect(source,
        contains('p_hour_limit: byProfile ? memberHourly : anonHourly'));
    expect(source, contains('p_day_limit: byProfile ? memberDaily : anonDaily'));
    for (final (key, constant) in const [
      ('support.message_max_chars', 'MESSAGE_MAX_CHARS'),
      ('support.anon_hourly', 'ANON_HOURLY_LIMIT'),
      ('support.anon_daily', 'ANON_DAILY_LIMIT'),
      ('support.member_hourly', 'MEMBER_HOURLY_LIMIT'),
      ('support.member_daily', 'MEMBER_DAILY_LIMIT'),
    ]) {
      expect(source, contains('setting("$key", $constant)'), reason: key);
    }
  });

  test('every fallback is the migration seed of its key', () {
    final seeds = migrationsDirectory()
        .listSync()
        .whereType<File>()
        .map((f) => f.readAsStringSync())
        .join('\n');
    int seed(String key) {
      final m = RegExp("\\('${RegExp.escape(key)}', '(\\d+)'").firstMatch(seeds);
      expect(m, isNotNull, reason: 'no migration seeds $key');
      return int.parse(m!.group(1)!);
    }

    expect(_readTsNumber('MESSAGE_MAX_CHARS'), seed('support.message_max_chars'));
    expect(_readTsNumber('ANON_HOURLY_LIMIT'), seed('support.anon_hourly'));
    expect(_readTsNumber('ANON_DAILY_LIMIT'), seed('support.anon_daily'));
    expect(_readTsNumber('MEMBER_HOURLY_LIMIT'), seed('support.member_hourly'));
    expect(_readTsNumber('MEMBER_DAILY_LIMIT'), seed('support.member_daily'));
    expect(PublicSettings.unloaded.supportMessageMaxChars,
        SupportRules.messageMaxChars);
  });

  test('the categories are the same set on both sides', () {
    final match = RegExp(r'const CATEGORIES: SupportCategory\[\] = \[([^\]]*)\]')
        .firstMatch(repoFile(_functionPath));
    expect(match, isNotNull, reason: 'CATEGORIES not found in $_functionPath.');
    final server = RegExp(r'"(\w+)"')
        .allMatches(match!.group(1)!)
        .map((m) => m.group(1))
        .toList();
    expect(server, SupportCategory.values.map((c) => c.wire).toList());
  });

  test('the database CHECK accepts exactly those categories', () {
    // The third copy: `support_requests.category`. A category the client offers
    // and the CHECK refuses turns into a 500 after the person pressed Send.
    final migration = repoFile(
        'supabase/migrations/20260921130000_f68_support_requests.sql');
    final check = RegExp(r"category IN \(([^)]*)\)").firstMatch(migration);
    expect(check, isNotNull);
    final values =
        RegExp(r"'(\w+)'").allMatches(check!.group(1)!).map((m) => m.group(1));
    expect(values.toList(), SupportCategory.values.map((c) => c.wire).toList());
  });

  test('the privacy category goes to the inbox the function uses', () {
    final source = repoFile(_functionPath);
    expect(source, contains('"${SupportRules.privacyEmail}"'));
    expect(source, contains('"${SupportRules.supportEmail}"'));
  });

  test('the diagnostics keys are the ones the function keeps', () {
    // A key the client adds and the function does not list is dropped on the
    // server — the preview would then promise something that never arrives.
    final match = RegExp(r'const DIAGNOSTIC_KEYS = \[([^\]]*)\]')
        .firstMatch(repoFile(_functionPath));
    expect(match, isNotNull);
    final server =
        RegExp(r'"(\w+)"').allMatches(match!.group(1)!).map((m) => m.group(1));
    final client = SupportDiagnostics.build(
        appVersion: '', channel: '', platform: '', language: '', route: '/');
    expect(client.keys.toList(), server.toList());
  });
}

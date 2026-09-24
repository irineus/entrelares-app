/// U-13 — the gate that keeps a notification writer from being FORGOTTEN.
///
/// `notification_renderer.dart` proves the client can rebuild a sentence from
/// `type` + `params`, but that is worthless for a trigger that never writes the
/// payload: that row silently keeps rendering the stored PT-BR for an English
/// reader, and nothing fails. Twelve functions and fourteen client call sites
/// write notifications — "we remembered all of them" is not a claim a human
/// should be making on every future change.
///
/// So this scans the migrations and requires every INSERT into `notifications`
/// that is STILL LIVE to carry `params`.
///
/// "Still live" is the whole difficulty, and it is why this cannot be a naive
/// grep: `CREATE OR REPLACE FUNCTION` replaces the entire body, so the same
/// function is defined many times across the migration history and only the
/// LAST definition runs. The superseded ones legitimately have no `params` and
/// must be ignored — the same CREATE OR REPLACE semantics the `CLAUDE.md`
/// gotcha warns about, applied here as a rule instead of as a memory.
///
/// It reads the FILES rather than `pg_proc` on purpose: the file is what CI
/// applies to production, it needs no database or secret, and it fails in the
/// same second the migration is written.
///
/// Ported from `entrelares-app`
/// `Entrelares.Tests/NotificationParamsCoverageTests.cs` (T-56, 24/08/2026).
library;

import 'dart:io';

import 'package:test/test.dart';

import 'repo_files.dart';

/// Handles both spellings in the repo: `public.name(` (CLI-authored migrations)
/// and `"public"."name"(` (the pg_dump baseline).
final _functionHeader = RegExp(
  r'CREATE\s+OR\s+REPLACE\s+FUNCTION\s+"?public"?\s*\.\s*"?(\w+)"?\s*\(',
  caseSensitive: false,
);

final _notificationInsert = RegExp(
  r'INSERT\s+INTO\s+public\.notifications\s*\(([^)]*)\)',
  caseSensitive: false,
);

/// Latest definition of every function, keyed by name — migrations applied in
/// filename order, exactly as the CLI and CI apply them.
Map<String, String> _liveFunctionBodies() {
  final live = <String, String>{};

  final files = migrationsDirectory()
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.sql'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  for (final file in files) {
    final sql = file.readAsStringSync();
    for (final header in _functionHeader.allMatches(sql)) {
      // The body ends at the dollar-quote terminator; anything after it
      // (grants, comments) is not part of the definition.
      final end = sql.indexOf(r'$$;', header.start);
      live[header.group(1)!] =
          end < 0 ? sql.substring(header.start) : sql.substring(header.start, end + 3);
    }
  }

  return live;
}

void main() {
  test('every live notification INSERT carries params', () {
    final offenders = <String>[];

    _liveFunctionBodies().forEach((name, body) {
      for (final insert in _notificationInsert.allMatches(body)) {
        if (!insert.group(1)!.toLowerCase().contains('params')) {
          offenders.add('$name: INSERT (${insert.group(1)!.trim()})');
        }
      }
    });

    expect(offenders, isEmpty,
        reason: 'These live functions still write a notification with no '
            'render payload, so the sentence stays PT-BR for every reader:\n  '
            '${offenders.join("\n  ")}');
  });

  // Sanity check on the parser itself. A regex that matched NOTHING would make
  // the gate above pass forever while proving nothing — the classic way a green
  // test hides a missing check.
  test('the scanner actually finds the known writers', () {
    final writers = _liveFunctionBodies()
        .entries
        .where((e) => _notificationInsert.hasMatch(e.value))
        .map((e) => e.key)
        .toSet();

    for (final expected in const [
      'auto_approve_expired',
      'notify_member_joined',
      'cancel_account_deletion',
      'request_account_deletion',
      'request_family_deletion',
      'respond_family_deletion',
      'withdraw_family_deletion',
      'family_deletion_reminders_due',
      'notify_family_email_cap',
      'billing_grace_warnings_due',
      'plan_end_reminders_due',
      'agenda_notify',
    ]) {
      expect(writers, contains(expected));
    }
  });

  // The superseded bodies must still be visible to the parser but NOT to the
  // gate — otherwise the only way to keep it green would be to rewrite history,
  // which is exactly what migrations forbid.
  test('superseded bodies are ignored, not rewritten', () {
    final baseline = File(
            '${migrationsDirectory().path}/20260713000000_baseline_v1_4_0.sql')
        .readAsStringSync();
    expect(
        baseline,
        contains('INSERT INTO public.notifications (recipient_profile_id, '
            'type, title, message, swap_request_id'));

    // ...and the live body of that same function is the one that carries params.
    expect(_liveFunctionBodies()['auto_approve_expired'], contains('params'));
  });
}

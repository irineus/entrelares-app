/// F-09 — the push copy is rendered in Deno, from a catalog that duplicates the
/// Dart one on purpose.
///
/// **Why the duplication exists.** In-app, a notification is rendered on the
/// reader's device by [NotificationRenderer]: the row stores `params` and the
/// sentence is built in that reader's language. A push has no device to render
/// on — the OS shows what arrives, and on iOS a data-only message is throttled
/// and may never be delivered — so the text is assembled server-side, per
/// recipient, exactly as `send-swap-email` already assembles an e-mail. Deno
/// cannot call Dart, so `_shared/push.ts` carries its own copy of the strings.
///
/// **Why it needs a gate.** Every failure mode here is silent. Edit a sentence
/// in the Dart catalog and the push keeps sending the old one — a valid,
/// well-formed sentence that no longer matches what the app shows for the same
/// event. Add a type to the trigger's filter and forget the function's list and
/// the push is dropped after paying for the HTTP call. Drop a key from one
/// language and that reader silently gets Portuguese. None of it breaks a
/// build; all of it is visible only to the person being interrupted.
///
/// Same reasoning as the role-catalog, e-mail-date and auth-mail mirrors — the
/// fourth crossing of the Dart/Deno boundary to get a suite that reads BOTH
/// sides.
library;

import 'dart:io';

import 'package:entrelares_core/entrelares_core.dart';
import 'package:test/test.dart';

import 'repo_files.dart';

String _pushSource() => repoFile('supabase/functions/_shared/push.ts');

/// The migration that installs the dispatcher trigger, found by content rather
/// than by name: migrations are timestamped and a later one may rewrite the
/// function, and the gate must read whichever file is current.
String _dispatcherMigration() {
  final files = migrationsDirectory()
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.sql'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  final matches = files
      .map((f) => f.readAsStringSync())
      .where((s) => s.contains('FUNCTION public.dispatch_push_notification()'))
      .toList();

  expect(matches, isNotEmpty,
      reason: 'no migration defines dispatch_push_notification().');
  // The newest body wins — the same rule the CLAUDE.md gotcha states for every
  // CREATE OR REPLACE of a shared trigger function.
  return matches.last;
}

/// The `PUSH_TYPES` array from the Deno module.
List<String> _pushTypesFromTs() {
  final block = RegExp(r'export const PUSH_TYPES[^=]*=\s*\[([\s\S]*?)\]')
      .firstMatch(_pushSource());
  expect(block, isNotNull, reason: '`export const PUSH_TYPES` not found in push.ts.');
  return RegExp('"([a-z_]+)"')
      .allMatches(block!.group(1)!)
      .map((m) => m.group(1)!)
      .toList();
}

/// The trigger's own filter list — the cheap first refusal, in SQL.
List<String> _pushTypesFromTrigger() {
  final block = RegExp(r'NEW\.type NOT IN \(([\s\S]*?)\)')
      .firstMatch(_dispatcherMigration());
  expect(block, isNotNull,
      reason: 'the dispatcher trigger has no `NEW.type NOT IN (...)` filter.');
  return RegExp("'([a-z_]+)'")
      .allMatches(block!.group(1)!)
      .map((m) => m.group(1)!)
      .toList();
}

/// One language block of the Deno catalog, as key → value.
Map<String, String> _tsCatalog(String lang) {
  final block = RegExp('"${RegExp.escape(lang)}": \\{([\\s\\S]*?)\\n\\t\\},')
      .firstMatch(_pushSource());
  expect(block, isNotNull,
      reason: 'no "$lang" block in the STRINGS catalog of push.ts.');

  final entries = <String, String>{};
  for (final m in RegExp(r'"([^"]+)":\s*"((?:[^"\\]|\\.)*)"')
      .allMatches(block!.group(1)!)) {
    entries[m.group(1)!] =
        m.group(2)!.replaceAll(r'\"', '"').replaceAll(r'\\', r'\');
  }
  return entries;
}

void main() {
  group('push notification mirror (Dart catalog ↔ _shared/push.ts)', () {
    test('the Deno catalog is byte-identical to the Dart one, in both languages',
        () {
      for (final (lang, dart) in [
        ('pt-BR', StringsPtBr.values),
        ('en', StringsEn.values),
      ]) {
        final ts = _tsCatalog(lang);
        expect(ts, isNotEmpty, reason: 'the $lang block of push.ts is empty.');

        for (final entry in ts.entries) {
          expect(dart, contains(entry.key),
              reason: 'push.ts declares `${entry.key}` ($lang), which the Dart '
                  'catalog does not have — a renamed or deleted key.');
          expect(entry.value, dart[entry.key],
              reason: 'the $lang text of `${entry.key}` has drifted. The push '
                  'would say something the app no longer says for the same event.');
        }
      }
    });

    test('both languages carry exactly the same keys', () {
      expect(_tsCatalog('en').keys.toSet(), _tsCatalog('pt-BR').keys.toSet(),
          reason: 'a key present in one language only falls back to Portuguese '
              'for the reader of the other — silently, and forever.');
    });

    test('the trigger filter and the function list name the same types', () {
      expect(_pushTypesFromTrigger().toSet(), _pushTypesFromTs().toSet(),
          reason: 'the SQL filter and PUSH_TYPES disagree. A type in the trigger '
              'only pays for an HTTP call that drops it; a type in push.ts only '
              'never fires at all.');
    });

    test('every pushable type is one the in-app renderer also knows', () {
      final renderer =
          repoFile('packages/entrelares_core/lib/src/localization/notification_renderer.dart');

      for (final type in _pushTypesFromTs()) {
        expect(renderer, contains("case '$type'"),
            reason: 'push sends `$type`, but NotificationRenderer has no branch '
                'for it — the push and the notification the user opens would not '
                'be the same text.');
      }
    });

    test('a receipt for your own action is never pushed', () {
      // The line the subset is drawn on: push only what the recipient did NOT
      // just do. These four reach a person holding the phone that produced
      // them, and `swap_family_info` is information rather than a call to act.
      const selfReceipts = [
        'swap_sent',
        'revert_sent',
        'swap_approved_self',
        'revert_approved_self',
        'swap_family_info',
      ];

      final pushable = _pushTypesFromTs().toSet();
      for (final type in selfReceipts) {
        expect(pushable, isNot(contains(type)),
            reason: '`$type` became pushable. It notifies the person who caused '
                'it — interrupting them with their own action is the one thing '
                'this subset exists to avoid.');
      }
    });

    // F-52 — the assertion that exists because its defect SHIPPED, twice, and
    // was silent both times.
    //
    // `day_notice` carries SIX wordings under one type. The first version hid
    // three of them behind a `kind` filter in the trigger, so they never
    // reached this module and nobody noticed there was no copy for them here.
    // When the filter was dropped — so that a courtesy aviso could finally
    // reach a phone — those three arrived at `renderPush` for the first time,
    // matched no template, and were dropped as "unrenderable payload". The
    // notification, the badge and the screen were all fine; only the
    // interruption was missing, and the only trace was a log line nobody
    // reads.
    //
    // The catalog mirror above cannot catch this: it compares strings that
    // EXIST on both sides, and the failure was a wording that existed on
    // neither. This reads the closed sets the database writes from — the two
    // core enums — and requires the Deno branch to name every one of them.
    test('every day_notice kind the database can write has push copy', () {
      final source = _pushSource();
      final kinds = [
        ...NoticeRequest.values.map((r) => r.wire),
        ...NoticeOutcome.values.map((o) => o.wire),
      ];
      expect(kinds, hasLength(6),
          reason: 'the enums moved; this gate counts on covering both');

      for (final kind in kinds) {
        expect(source, contains('$kind:'),
            reason: 'push.ts has no branch for the `$kind` wording of '
                '`day_notice`. The trigger sends it, renderPush returns null, '
                'and the push is dropped with a log line — the person simply '
                'is not interrupted, and nothing is red.');
      }
    });

    test('the renderer reads params the writers actually send', () {
      // `renderPush` refuses anything without `params.date`, so a pushable type
      // whose writer never sets one would be dropped on every single send —
      // green everywhere, silent in production. `swap_notifications.dart` is
      // the client-side writer; the SQL writers are covered by the U-13
      // params-coverage mirror next door.
      final source = _pushSource();
      expect(source, contains('params["date"]'),
          reason: 'renderPush no longer reads params.date.');
      expect(source, contains('if (date === null) return null;'),
          reason: 'renderPush must drop a payload with no day rather than push '
              'a sentence with a hole in it.');
    });
  });
}

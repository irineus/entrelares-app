/// F-60 — the auto-approval deadline is said in FOUR places, and three of them
/// are outside Dart.
///
/// The rule never moved: `auto_approve_expired()` anchors on the DAY
/// (`schedule_date + handoff`), reminds at `+24 h` and approves at `+48 h`.
/// What was wrong was the account the product gave of itself — every sentence
/// described a window measured from the REQUEST, and so missed in both
/// directions: a request opened a week ahead was told "24h", and production
/// request #32, opened at 16:20 on its own day, was told 48 h when it had ~31.
///
/// The sentences live in four languages of their own:
///   * the Dart catalog (`strings_*.dart`) — pinned next door, by
///     `notification_renderer_test.dart`;
///   * `_shared/push.ts` — the F-09 duplicate, pinned byte-for-byte against
///     Dart by `push_notification_mirror_test.dart`;
///   * `_shared/i18n.ts` — the e-mail copy, until F-59 (02/10/2026) made the
///     reminder and the auto-approval push + in-app only; what is pinned now is
///     that it stays gone;
///   * the migration's STORED sentence, the fallback record every reader with
///     an old client still sees.
///
/// Each one can be edited alone, and each failure is silent: the e-mail kept
/// promising 24 h while the app named an instant, and both were well-formed
/// sentences nobody's build complained about. So this suite reads the non-Dart
/// sides and refuses the two things that made F-60 a defect — a quoted window,
/// and a reminder that does not carry the instant.
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'repo_files.dart';

/// Every spelling of the window that used to be quoted. `48-hour` is the
/// English e-mail's, which no `48h` search would have found.
const _windows = ['24h', '48h', '24 h', '48 h', '24 horas', '48 horas',
  '24-hour', '48-hour', '24 hours', '48 hours'];

/// The lines of a TypeScript file that define one of the auto-approval texts,
/// by key. Read as source rather than evaluated: Deno cannot be run from the
/// core lane, and the string is what ships either way.
List<String> _tsLinesFor(String source, List<String> keys) => source
    .split('\n')
    .where((line) => keys.any((k) => line.trimLeft().startsWith('$k:')))
    .toList();

/// The newest migration body that defines `auto_approve_expired` — the same
/// "last CREATE OR REPLACE wins" rule the params-coverage mirror applies, and
/// the reason this cannot be a naive grep over the whole directory.
String _liveAutoApproveBody() {
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
        RegExp(r'CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.auto_approve_expired'));
    if (start == -1) continue;
    final end = sql.indexOf('\n\$\$;', start);
    bodies.add(end == -1 ? sql.substring(start) : sql.substring(start, end));
  }

  if (bodies.isEmpty) {
    // Loudly, and not as a skipped test: a mirror that silently reads nothing
    // is worse than no mirror — it reads as coverage on every future review.
    throw StateError('no migration defines auto_approve_expired().');
  }
  return bodies.last;
}

void main() {
  group('F-59 · no e-mail states the deadline any more', () {
    // The reminder and the auto-approval stopped being e-mail on 02/10/2026:
    // push + in-app only. This mirror used to read their e-mail copy; what it
    // pins now is that the copy is really gone, so a reminder e-mail cannot
    // come back without bringing its own guard against a quoted window.
    test('_shared/i18n.ts carries no reminder or auto-approval text', () {
      expect(
          _tsLinesFor(i18nSource(), [
            'subjReminder',
            'reminderTitle',
            'reminderBanner',
            'reminderHeading',
            'reminderBody',
            'autoApprovedApprover',
            'autoApprovedRequester',
          ]),
          isEmpty,
          reason: 'an auto-approval e-mail is back. Restore the F-60 checks '
              'for it here (no quoted window, the instant in every text) in '
              'the same delivery.');
    });
  });

  group('F-60 · the push copy (_shared/push.ts)', () {
    // The byte-identity with Dart is `push_notification_mirror_test`'s job;
    // what is pinned here is that the push can SAY an instant at all — it is
    // the only one of the three renderings whose params reach it second-hand,
    // through the trigger's payload.
    final source = repoFile('supabase/functions/_shared/push.ts');

    test('the reminder branch reads params.deadline and falls back without it',
        () {
      expect(source, contains('params["deadline"]'),
          reason: 'the push no longer reads the deadline — it would keep '
              'sending the sentence with no instant, for every request.');
      expect(source, contains('notifRender.autoReminder.deadline'),
          reason: 'the deadline sentence is gone from the push catalog.');
      // U-63: the instant is said as a person says it, by the twin of
      // Dart's `formatDeadline` — the weekday tables and the à/às rule.
      expect(source, contains('formatDeadlineIn(lang, deadline)'));
      for (final day in ['segunda-feira', 'terça-feira', 'quarta-feira',
          'quinta-feira', 'sexta-feira', 'sábado', 'domingo']) {
        expect(source, contains('"$day"'));
      }
      expect(source, contains('h <= 1 ? "à" : "às"'));
      expect(source, contains('fmt(lang, K.autoReminder, [date])'),
          reason: 'a row written before F-60 carries no deadline and must '
              'still render — in the reader language, not in stored PT-BR.');
    });
  });

  group('F-60 · the stored sentence (the live auto_approve_expired)', () {
    test('the reminder writes the deadline into params', () {
      final body = _liveAutoApproveBody();
      expect(body, contains("'deadline', deadline_iso"),
          reason: 'the reminder no longer carries the instant, so every '
              'reader falls back to the sentence without one.');
      // U-63: the stored PT-BR instant is `pt_deadline_words`, the SQL twin
      // of Dart's `formatDeadline`.
      expect(body, contains('public.pt_deadline_words(deadline AT TIME ZONE tz)'));
      expect(body, contains("'YYYY-MM-DD\"T\"HH24:MI'"),
          reason: 'the deadline must be the wall clock the clients parse; '
              'any other shape is refused by both renderers and silently '
              'drops the instant.');
      expect(body, contains("deadline := expiry + interval '48 hours'"),
          reason: 'the instant must be the DAY\'s expiry plus 48 h — the same '
              'anchor the approval itself uses. Re-anchoring it is option 2 '
              'of the card and a separate decision.');
    });

    test('no stored sentence quotes a window', () {
      // Only the SENTENCES — the arithmetic beside them is allowed to say
      // `interval '48 hours'`, and must: that is the rule, which F-60 did not
      // touch. A sentence here is a literal long enough to be prose and not a
      // format mask (`'DD/MM/YYYY'`) or a timezone name.
      final sentences = const LineSplitter()
          .convert(_liveAutoApproveBody())
          .where((line) => !line.trimLeft().startsWith('--'))
          .expand((line) => RegExp("'([^']{20,})'")
              .allMatches(line)
              .map((m) => m.group(1)!))
          .where((s) => ' '.allMatches(s).length >= 2)
          .where((s) => !s.contains('YYYY') && !s.contains('HH24'))
          .toList();

      expect(sentences, isNotEmpty,
          reason: 'no stored sentence was read at all — the scan is broken, '
              'not the copy.');
      for (final sentence in sentences) {
        for (final window in _windows) {
          expect(sentence, isNot(contains(window)),
              reason: 'the stored PT-BR sentence promises "$window" again. It '
                  'is the fallback record — the reader whose client cannot '
                  'rebuild the sentence sees exactly this: $sentence');
        }
      }
    });
  });
}

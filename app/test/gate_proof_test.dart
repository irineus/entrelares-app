// 04/11/2026 — the two cuts in `verify.yml`'s minutes, pinned.
//
//   · the schedule runs the whole gate on MONDAY only (the other days run
//     `verify` and the emulator lane);
//   · a push to `main` skips `db-gate` and `web-e2e` when `gate-proof` finds
//     the merged tree already proven by the PR run.
//
// The second one moves a gate out of the path to production, so what these
// tests hold is the shape that keeps it safe: a skip happens only on PROOF,
// and every publishing job still refuses a gate that failed or was cancelled.
// The workflow reads the conditions; nothing else does — a typo in one of them
// either publishes behind a red gate or stops publishing in silence, and both
// compile.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final _source = File('../.github/workflows/verify.yml').readAsStringSync();

/// The workflow without comment lines: the comments quote the conditions to
/// explain them, and a guard that matches its own explanation passes over a
/// workflow whose code changed (the T-68 lesson).
final _code = _source
    .split(RegExp(r'\r?\n'))
    .where((line) => !line.trimLeft().startsWith('#'))
    .join('\n');

final _lines = _code.split('\n');

/// One job's body: from `  <name>:` to the next top-level job.
String _job(String name) {
  final start = _lines.indexOf('  $name:');
  expect(start, isNot(-1), reason: 'job $name exists');
  final end = _lines.indexWhere(
      (l) => RegExp(r'^  [a-z0-9-]+:$').hasMatch(l), start + 1);
  return _lines.sublist(start, end == -1 ? _lines.length : end).join('\n');
}

/// The job's own `if:`, folded onto one line (a `>-` block included).
String _if(String name) {
  final start = _lines.indexOf('  $name:');
  expect(start, isNot(-1), reason: 'job $name exists');
  final at = _lines.indexWhere((l) => l.startsWith('    if:'), start);
  final next = _lines.indexWhere(
      (l) => RegExp(r'^  [a-z0-9-]+:$').hasMatch(l), start + 1);
  expect(at, allOf(greaterThan(start), lessThan(next == -1 ? 1 << 30 : next)),
      reason: 'job $name has its own if:');
  final condition = StringBuffer(_lines[at].substring('    if:'.length).trim());
  for (var i = at + 1; _lines[i].startsWith('      '); i++) {
    condition.write(' ${_lines[i].trim()}');
  }
  return condition.toString().replaceFirst(RegExp(r'^>-\s*'), '');
}

String _needs(String name) =>
    RegExp(r'needs:\s*(\[[^\]]*\]|\S+)').firstMatch(_job(name))!.group(1)!;

/// The clause that lets a gate count as passed: green here, or skipped on
/// proof. Written once, compared verbatim in every publishing job.
String _passed(String gate) => "(needs.$gate.result == 'success' || "
    "(needs.$gate.result == 'skipped' && "
    "needs.gate-proof.outputs.proven == 'true'))";

const _monday = '10 6 * * 1';

void main() {
  group('the schedule — full gate on Monday, emulator lane every day', () {
    test('two entries, Monday and the other six days, no gap and no overlap',
        () {
      final crons = RegExp(r'- cron: "([^"]+)"')
          .allMatches(_code)
          .map((m) => m.group(1))
          .toList();
      expect(crons, [_monday, '10 6 * * 0,2-6'],
          reason: 'together the two cover each day of the week exactly once, '
              'at the 06:10 UTC the emulator lane has always used');
    });

    test('db-gate and web-e2e run on a schedule only from the MONDAY entry',
        () {
      for (final gate in ['db-gate', 'web-e2e']) {
        expect(
            _if(gate),
            contains("(github.event_name != 'schedule' || "
                "github.event.schedule == '$_monday')"),
            reason: '`github.event.schedule` is the cron string verbatim — '
                'it must be the Monday entry, byte for byte');
      }
    });

    test('the emulator lane still runs on every scheduled day', () {
      expect(_if('e2e'), contains("github.event_name == 'schedule'"));
      expect(_if('e2e'), isNot(contains('github.event.schedule')),
          reason: 'the daily emulator run is the reason the schedule exists');
    });
  });

  group('a push skips the gates only on proof', () {
    test('gate-proof runs on push alone — a manual dispatch re-proves all', () {
      expect(_if('gate-proof'), "github.event_name == 'push'",
          reason: 'a dispatch on main is how HEAD is republished (F-63); it '
              'must run every gate, never borrow a PR\'s verdict');
      expect(_job('gate-proof'), contains('run: bash .github/gate_proof.sh'));
      expect(_job('gate-proof'),
          contains(r'proven: ${{ steps.proof.outputs.proven }}'));
    });

    test('db-gate and web-e2e skip only when gate-proof said true', () {
      for (final gate in ['db-gate', 'web-e2e']) {
        expect(_needs(gate), 'gate-proof');
        final condition = _if(gate);
        expect(condition, startsWith('!cancelled()'),
            reason: 'gate-proof SKIPS on every event but push; without a '
                'status function a skipped need would skip $gate on every PR');
        expect(condition,
            contains("needs.gate-proof.outputs.proven != 'true'"),
            reason: 'anything but an explicit true — empty, false, a failed '
                'gate-proof — must run the gate');
      }
    });

    test('every publishing job accepts a gate only as success or proven skip',
        () {
      const gatesOf = {
        'db-prod': ['db-gate'],
        'qa-web': ['db-gate'],
        'deploy-web': ['db-gate', 'web-e2e'],
        'play-internal': ['db-gate', 'web-e2e'],
      };
      gatesOf.forEach((job, gates) {
        final condition = _if(job);
        expect(condition, startsWith('!cancelled()'), reason: job);
        expect(condition, isNot(contains('always()')),
            reason: '$job: `always()` would run it after a CANCELLED run too');
        expect(condition, contains("needs.verify.result == 'success'"),
            reason: '$job: with a status function in the if, a red verify no '
                'longer stops it on its own');
        expect(_needs(job), contains('gate-proof'),
            reason: '$job reads gate-proof\'s output, so it must need it');
        for (final gate in gates) {
          expect(_needs(job), contains(gate), reason: job);
          expect(condition, contains(_passed(gate)),
              reason: '$job must refuse a $gate that failed or was cancelled');
        }
      });
      for (final job in ['deploy-web', 'play-internal']) {
        expect(_if(job), contains("needs.db-prod.result == 'success'"),
            reason: '$job: T-29\'s order, migrations before the app');
      }
    });

    test('every job downstream of a gate carries a status function', () {
      // GitHub's default `success()` reads EVERY ancestor job, not only the
      // ones in `needs:`. `gate-proof` skips on PRs, schedules and dispatches,
      // so a job that needs `db-gate` or `web-e2e` without a status function
      // skips with both of its needs green — PR #414's first run lost
      // `qa-preview` exactly that way, with no red anywhere.
      final jobs = RegExp(r'^  ([a-z0-9-]+):$', multiLine: true)
          .allMatches(_code)
          .map((m) => m.group(1)!)
          .where((name) => _lines.indexOf('  $name:') > _lines.indexOf('jobs:'));
      final downstream = [
        for (final name in jobs)
          if (RegExp(r'needs:\s*(\[[^\]]*\]|\S+)').firstMatch(_job(name))
                  case final m?
              when RegExp(r'\b(db-gate|web-e2e|gate-proof)\b')
                  .hasMatch(m.group(1)!))
            name,
      ];
      expect(downstream, containsAll(['db-gate', 'web-e2e', 'qa-preview',
          'db-prod', 'deploy-web', 'play-internal', 'qa-web', 'ops-alert']));
      for (final name in downstream) {
        expect(_if(name), anyOf(startsWith('!cancelled()'), startsWith('always()')),
            reason: '$name would skip whenever gate-proof skips');
      }
    });

    test('the PR run records the tree it tested', () {
      final verify = _job('verify');
      expect(verify, contains("run: git rev-parse 'HEAD^{tree}' > tested-tree.txt"));
      expect(verify, contains('name: tested-tree'));
      final record = verify.indexOf('tested-tree.txt');
      expect(verify.lastIndexOf("if: github.event_name == 'pull_request'", record),
          greaterThan(-1),
          reason: 'only a PR run tests a merge ref worth recording');
    });

    test('gate_proof.sh says true in exactly one place: equal trees', () {
      final script = File('../.github/gate_proof.sh')
          .readAsStringSync()
          .split(RegExp(r'\r?\n'))
          .where((line) => !line.trimLeft().startsWith('#'))
          .join('\n');
      expect(RegExp(r'answer true').allMatches(script).length, 1);
      final yes = script.indexOf('answer true');
      final guard = script.lastIndexOf(r'if [ "$tested" = "$tree" ]', yes);
      expect(guard, greaterThan(-1),
          reason: 'the only proof is the same tree, byte for byte');
      expect(script, contains('all(.conclusion == "success")'),
          reason: 'a run green with a gate skipped proves nothing');
      expect(script, contains('select(.name == "db-gate"'));
      expect(script, contains('startswith("web-e2e (")'));
      expect(script, isNot(contains('set -e')),
          reason: 'an error must end in `proven=false`, never in a red job '
              'that skips the publish chain');
    });
  });
}

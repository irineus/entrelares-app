// T-94 / Fulcrum 04.3.1 — the DB gate runs on a LOCAL stack, and stays there.
//
// The defect this pins was silent and cumulative: every gate run against the
// hosted dev project created ~344 auth users, the Free plan counted each one
// that signed in as a MAU whether the teardown deleted it or not, and 375 runs
// in one cycle put the org at 91,988 / 50,000 — nothing red anywhere until the
// provider's restriction would have turned every request to dev into a 402.
// A single line of YAML handing the gate the dev service key again, or a
// default URL creeping back into `TestEnv`, would restart the count with every
// check green. These assertions read the SOURCE, so they cost nothing to run.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _code(String source) => source
    .split(RegExp(r'\r?\n'))
    .where((line) => !line.trimLeft().startsWith('#'))
    .join('\n');

String _job(String workflow, String name) {
  final lines = workflow.split('\n');
  final start = lines.indexOf('  $name:');
  expect(start, isNot(-1), reason: 'job $name exists');
  final end = lines.indexWhere(
      (l) => RegExp(r'^  [a-z0-9-]+:$').hasMatch(l), start + 1);
  return lines.sublist(start, end == -1 ? lines.length : end).join('\n');
}

void main() {
  final workflow =
      _code(File('../.github/workflows/verify.yml').readAsStringSync());
  final script = File('../tool/db_gate_local.sh').readAsStringSync();
  final testEnv = File('../packages/entrelares_db_gate/lib/src/test_env.dart')
      .readAsStringSync();

  group('the DB gate runs on a local stack (T-94)', () {
    test('the db-gate job runs the suite through the local-stack script', () {
      final job = _job(workflow, 'db-gate');
      expect(job, contains('bash tool/db_gate_local.sh'));
      expect(job, isNot(contains('dart test')),
          reason: 'the suite runs only inside the script, after the stack is '
              'up and the URL has been checked to be local');
    });

    test('no dev credential that could reach the suite is in the job', () {
      final job = _job(workflow, 'db-gate');
      for (final secret in [
        'SUPABASE_SERVICE_ROLE_DEV',
        'ASAAS_WEBHOOK_TOKEN_DEV',
        'E2E_SUPABASE_URL',
        'E2E_SUPABASE_SERVICE_ROLE_KEY',
      ]) {
        expect(job, isNot(contains(secret)),
            reason: '$secret in db-gate would point the gate back at the '
                'hosted dev project, where each run is ~344 MAU');
      }
    });

    test('the script starts the stack and refuses a URL that is not local', () {
      expect(_code(script), contains(r'$SUPABASE start'));
      expect(script, contains('http://127.0.0.1:*|http://localhost:*) ;;'),
          reason: 'the last guard before `dart test`: a hosted URL exits 1');
      expect(script, contains('supabase/functions/.env'));
    });

    test('TestEnv has no hosted default to fall back to', () {
      expect(testEnv, isNot(contains('supabase.co')),
          reason: 'a missing E2E_SUPABASE_URL must fail with instructions, '
              'never quietly target a hosted project');
      expect(RegExp(r"'sb_(publishable|secret)_[A-Za-z0-9_-]{8,}'")
          .hasMatch(testEnv), isFalse,
          reason: 'no key literal of any project either');
    });

    test('the functions env the script writes is git-ignored', () {
      final ignored = File('../.gitignore').readAsLinesSync();
      expect(ignored, contains('supabase/functions/.env'));
    });
  });
}

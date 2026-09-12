// T-58 — the web flow gate's verdict, exercised on every way a run can END.
//
// The item's whole lesson: a probe proves what it exercises and nothing more.
// The lane was trusted on a probe that broke an ASSERTION and watched the job
// go red; it never asked whether the lane could report a suite that never got
// as far as asserting. So this file names each terminal state the browser can
// hand the driver — a failure, no report at all, a report without the list, an
// empty list, the wrong count, the right count — and pins the colour of each.
// Every red case was watched failing against a `judge` mutated to always
// pass before this file was trusted (12/09/2026).
import 'package:flutter_test/flutter_test.dart';

import '../test_driver/e2e_proof.dart';

Map<String, dynamic> _response({
  bool passed = true,
  Map<String, dynamic>? data,
  bool withData = true,
}) =>
    {
      'result': passed ? 'true' : 'false',
      'failureDetails': <String>[],
      if (withData) 'data': data,
    };

void main() {
  group('judge — the vacuous green, by name', () {
    test('a run that reported NOTHING is red', () {
      // The T-58 case: `setUpAll` threw, no test reached its tearDown, the
      // browser sent `{result: true}` with no data. Measured locally
      // 12/09/2026: `flutter drive` printed "All tests passed." over exactly
      // this and wrote `null` as its whole report.
      final verdict = judge(_response(withData: false), expected: 4);
      expect(verdict.passed, isFalse);
      expect(verdict.message, contains('não reportou NADA'));
      expect(verdict.executed, isEmpty);
    });

    test('a null report is the same red', () {
      final verdict = judge(_response(data: null), expected: 1);
      expect(verdict.passed, isFalse);
      expect(verdict.message, contains('não reportou NADA'));
    });

    test('a report without the executed list is red', () {
      // `reportData` can carry other things (screenshots, timelines); none of
      // them is proof. A driver and a suite that stop sharing the key name
      // must not produce a green about nothing.
      final verdict =
          judge(_response(data: {'screenshots': <String>[]}), expected: 1);
      expect(verdict.passed, isFalse);
      expect(verdict.message, contains('não traz a lista "$executedKey"'));
      expect(verdict.message, contains('screenshots'),
          reason: 'the message names what the report DID carry');
    });

    test('an empty executed list is red', () {
      final verdict = judge(
          _response(data: {executedKey: <String>[], failedKey: <String>[]}),
          expected: 1);
      expect(verdict.passed, isFalse);
      expect(verdict.message, contains('ZERO testes'));
    });
  });

  group('judge — the count the workflow demands', () {
    final twoRan = {
      executedKey: ['p0 — a', 'p0 — b'],
      failedKey: <String>[],
    };

    test('fewer than expected is red, and says which ran', () {
      final verdict = judge(_response(data: twoRan), expected: 3);
      expect(verdict.passed, isFalse);
      expect(verdict.message, contains('esperava 3'));
      expect(verdict.message, contains('executou 2'));
      expect(verdict.message, contains('p0 — a; p0 — b'));
    });

    test('more than expected is red too — the gate affirms what it declares',
        () {
      final verdict = judge(_response(data: twoRan), expected: 1);
      expect(verdict.passed, isFalse);
      expect(verdict.message, contains('esperava 1'));
    });

    test('the exact count is green, naming every test', () {
      final verdict = judge(_response(data: twoRan), expected: 2);
      expect(verdict.passed, isTrue);
      expect(verdict.message, contains('2 de 2 teste(s) PROVADO(S)'));
      expect(verdict.executed, ['p0 — a', 'p0 — b']);
    });

    test('with no expectation, any positive count is green', () {
      // A developer driving a suite by hand gets the zero-guard for free and
      // no count to type; CI always sets the variable (web_channel_test pins
      // that).
      final verdict = judge(_response(data: twoRan));
      expect(verdict.passed, isTrue);
      expect(verdict.message, contains(': 2 teste(s) PROVADO(S)'));
      expect(verdict.message, isNot(matches(RegExp(r' de \d+ teste'))),
          reason: 'no count was demanded, so none is claimed');
    });
  });

  group('judge — a failing suite stays red, whatever it reported', () {
    test('a failure is red even with a full executed list', () {
      final verdict = judge(
          _response(passed: false, data: {
            executedKey: ['p0 — a'],
            failedKey: ['p0 — b'],
          }),
          expected: 2);
      expect(verdict.passed, isFalse);
      expect(verdict.message, contains('teste(s) com falha: p0 — b'));
    });

    test('a failure with no report is red and says so', () {
      final verdict = judge(_response(passed: false, withData: false));
      expect(verdict.passed, isFalse);
      expect(verdict.message, contains('com falha'));
      expect(verdict.message, contains('without naming a test'));
    });
  });

  group('expectedTests — what the workflow hands the driver', () {
    test('absent means no fixed count', () {
      expect(expectedTests({}), isNull);
      expect(expectedTests({expectedTestsVariable: '  '}), isNull);
    });

    test('a positive integer is read as is', () {
      expect(expectedTests({expectedTestsVariable: '4'}), 4);
      expect(expectedTests({expectedTestsVariable: ' 1 '}), 1);
    });

    test('anything else is refused, never read as "anything goes"', () {
      // A guard whose expectation silently parsed to nothing would be the
      // vacuous green one level up.
      for (final bad in ['0', '-1', 'four', '1.5']) {
        expect(() => expectedTests({expectedTestsVariable: bad}),
            throwsFormatException,
            reason: '"$bad" must not be accepted');
      }
    });
  });

  test('the proof file lives under build/, where the workflow reads it', () {
    expect(proofFile, startsWith('build/'));
    expect(proofFile, endsWith('.json'));
  });
}

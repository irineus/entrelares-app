// T-58 — the verdict the driver applies to what the browser reported.
//
// On the web, `flutter drive` cannot tell an empty run from a full one. The
// `IntegrationTestWidgetsFlutterBinding` completes `allTestsPassed` with
// `failureMethodsDetails.isEmpty` in its own `tearDownAll`, and only a
// `testWidgets` that reached `runTest` is in `binding.results` — so a
// `setUpAll` that throws leaves the map EMPTY, the browser answers
// `{result: true}` with no data, the stock `integrationDriver()` prints
// "All tests passed." and exits 0. Measured in CI on 25/08/2026 (five days of
// green over a suite that never got past `setUpAll`) and reproduced locally on
// 12/09/2026: without the service-role key, `deep_link_test` goes green in
// 90 s with `null` as its entire report.
//
// This file is the other half of `integration_test/e2e_proof.dart`: the suite
// reports the tests that reached their end, and the driver REFUSES a run that
// reported nothing, or fewer than the workflow demands. Pure Dart on purpose —
// no `dart:io`, no `flutter_driver` — so `test/e2e_proof_test.dart` can run
// every verdict under `flutter test`, and so `integration_test/` can import the
// same key names instead of spelling them twice.
//
// T-71 (13/09/2026): the report also carries the setUpAll's window and, when
// it threw, the exception itself — the one piece of a "reported nothing" red
// that never reached the job log (a `-d web-server` drive has no DWDS, so the
// browser console is the only place the harness prints it). The verdict names
// the error, the proof file keeps it, and the window is printed green or red
// so a later red can be crossed against the db-gate's window on the shared dev
// project (H1) without reopening the log.
library;

/// The key under which the suite lists the tests that completed. Written by
/// `proveExecution` (`integration_test/e2e_proof.dart`), read by [judge].
const executedKey = 'executed';

/// The key under which the suite lists the tests that failed.
const failedKey = 'failed';

/// The key under which the suite reports its setUpAll (T-71): a map with
/// `startedAt`, `finishedAt`, `elapsedMs` and, only when it threw, `error` and
/// `stack`. Written by `provedSetUpAll` (`integration_test/e2e_proof.dart`).
const setUpAllKey = 'setUpAll';

/// The environment variable the workflow sets per target with the number of
/// tests that pack is expected to run. Absent = "at least one", which is what
/// a developer driving a suite by hand gets for free.
const expectedTestsVariable = 'E2E_EXPECTED_TESTS';

/// Where the driver writes the proof, relative to `app/`. The workflow reads
/// it back for the run summary, and removes it before each target so a stale
/// proof can never stand in for a missing one.
const proofFile = 'build/e2e_proof.json';

/// How many lines of the setUpAll's stack the verdict MESSAGE carries. The
/// proof file keeps the whole thing; the log line is for a human reading a
/// red, and a dart2js stack runs to hundreds of frames.
const stackLinesInMessage = 8;

/// What the driver decided, and why — the message is the whole log line.
class ProofVerdict {
  final bool passed;
  final String message;
  final List<String> executed;

  /// The setUpAll's report as the suite sent it (T-71), or `null` when the
  /// suite did not reach the point of writing one.
  final Map<String, Object?>? setUpAll;

  const ProofVerdict._(this.passed, this.message, this.executed,
      {this.setUpAll});

  Map<String, Object> toJson() => {
        'passed': passed,
        'message': message,
        executedKey: executed,
        setUpAllKey: ?setUpAll,
      };
}

/// Reads the expected count out of [environment]; `null` when the variable is
/// absent. A variable that is present but not a positive integer is refused
/// loudly rather than read as "anything goes".
int? expectedTests(Map<String, String> environment) {
  final raw = environment[expectedTestsVariable];
  if (raw == null || raw.trim().isEmpty) return null;
  final parsed = int.tryParse(raw.trim());
  if (parsed == null || parsed < 1) {
    throw FormatException(
        '$expectedTestsVariable must be a positive integer, got "$raw"');
  }
  return parsed;
}

/// Judges the decoded JSON the browser sent (`Response.toJson()` from
/// `package:integration_test/common.dart`):
/// `{'result': 'true'|'false', 'failureDetails': [...], 'data': {...}?}`.
///
/// Red, in this order: the harness reported a failure; the setUpAll threw
/// (T-71 — named, with the exception); the suite reported nothing at all; the
/// report has no [executedKey] list; the list is empty; the count differs
/// from [expected]. Green only when every test the workflow demanded is in
/// the list by name.
ProofVerdict judge(Map<String, dynamic> response, {int? expected}) {
  final data = response['data'];
  final report = data is Map<String, dynamic> ? data : null;
  final executed = _names(report?[executedKey]);
  final failed = _names(report?[failedKey]);
  final setUpAll = _setUpAll(report?[setUpAllKey]);
  final window = _window(setUpAll);

  if (response['result'] != 'true') {
    final who = failed.isNotEmpty
        ? failed.join('; ')
        : 'the harness reported the failure without naming a test';
    return ProofVerdict._(
        false, 'Gate de fluxo: VERMELHO — teste(s) com falha: $who$window',
        executed,
        setUpAll: setUpAll);
  }
  if (setUpAll != null && setUpAll['error'] != null) {
    return ProofVerdict._(
        false,
        'Gate de fluxo: VERMELHO — o setUpAll estourou e nenhum teste rodou'
        '$window: ${setUpAll['error']}\n${_stackHead(setUpAll['stack'])}',
        const [],
        setUpAll: setUpAll);
  }
  if (report == null) {
    return ProofVerdict._(
        false,
        'Gate de fluxo: VERMELHO — a suíte não reportou NADA. Nenhum teste '
        'chegou ao próprio tearDown, o que é a forma exata do verde vazio '
        '(T-58): um setUpAll que estoura, ou uma suíte sem proveExecution().',
        const []);
  }
  if (report[executedKey] is! List) {
    return ProofVerdict._(
        false,
        'Gate de fluxo: VERMELHO — o relatório da suíte não traz a lista '
        '"$executedKey" (chaves: ${report.keys.join(', ')}). O driver e a '
        'suíte deixaram de falar a mesma língua.',
        const [],
        setUpAll: setUpAll);
  }
  if (executed.isEmpty) {
    return ProofVerdict._(
        false,
        'Gate de fluxo: VERMELHO — a suíte reportou ZERO testes executados. '
        'Um verde aqui seria o verde vazio do T-58.$window',
        const [],
        setUpAll: setUpAll);
  }
  if (expected != null && executed.length != expected) {
    return ProofVerdict._(
        false,
        'Gate de fluxo: VERMELHO — o workflow esperava $expected teste(s) e a '
        'suíte executou ${executed.length}: ${executed.join('; ')}. Um teste '
        'novo bumpa a contagem no verify.yml; um teste a menos é o gate '
        'afirmando menos do que declara.$window',
        executed,
        setUpAll: setUpAll);
  }
  final demanded = expected == null ? '' : ' de $expected';
  return ProofVerdict._(
      true,
      'Gate de fluxo: ${executed.length}$demanded teste(s) PROVADO(S): '
      '${executed.join('; ')}$window',
      executed,
      setUpAll: setUpAll);
}

List<String> _names(Object? raw) =>
    raw is List ? raw.map((e) => e.toString()).toList() : const [];

Map<String, Object?>? _setUpAll(Object? raw) =>
    raw is Map ? raw.map((k, v) => MapEntry(k.toString(), v)) : null;

/// ` | setUpAll <start>→<end> (<n> s)` when the suite reported its window,
/// empty otherwise — appended to every verdict, green or red.
String _window(Map<String, Object?>? setUpAll) {
  if (setUpAll == null) return '';
  final started = setUpAll['startedAt'];
  final finished = setUpAll['finishedAt'];
  final elapsed = setUpAll['elapsedMs'];
  final seconds = elapsed is num ? (elapsed / 1000).toStringAsFixed(1) : '?';
  return ' | setUpAll $started→$finished ($seconds s)';
}

String _stackHead(Object? stack) {
  final lines = '${stack ?? ''}'.trim().split('\n');
  final head = lines.take(stackLinesInMessage).join('\n');
  return lines.length > stackLinesInMessage
      ? '$head\n… (${lines.length - stackLinesInMessage} linhas a mais em $proofFile)'
      : head;
}

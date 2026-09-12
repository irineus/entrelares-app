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
library;

/// The key under which the suite lists the tests that completed. Written by
/// `proveExecution` (`integration_test/e2e_proof.dart`), read by [judge].
const executedKey = 'executed';

/// The key under which the suite lists the tests that failed.
const failedKey = 'failed';

/// The environment variable the workflow sets per target with the number of
/// tests that pack is expected to run. Absent = "at least one", which is what
/// a developer driving a suite by hand gets for free.
const expectedTestsVariable = 'E2E_EXPECTED_TESTS';

/// Where the driver writes the proof, relative to `app/`. The workflow reads
/// it back for the run summary, and removes it before each target so a stale
/// proof can never stand in for a missing one.
const proofFile = 'build/e2e_proof.json';

/// What the driver decided, and why — the message is the whole log line.
class ProofVerdict {
  final bool passed;
  final String message;
  final List<String> executed;

  const ProofVerdict._(this.passed, this.message, this.executed);

  Map<String, Object> toJson() => {
        'passed': passed,
        'message': message,
        executedKey: executed,
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
/// Red, in this order: the harness reported a failure; the suite reported
/// nothing at all; the report has no [executedKey] list; the list is empty;
/// the count differs from [expected]. Green only when every test the
/// workflow demanded is in the list by name.
ProofVerdict judge(Map<String, dynamic> response, {int? expected}) {
  final data = response['data'];
  final report = data is Map<String, dynamic> ? data : null;
  final executed = _names(report?[executedKey]);
  final failed = _names(report?[failedKey]);

  if (response['result'] != 'true') {
    final who = failed.isNotEmpty
        ? failed.join('; ')
        : 'the harness reported the failure without naming a test';
    return ProofVerdict._(false,
        'Gate de fluxo: VERMELHO — teste(s) com falha: $who', executed);
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
        const []);
  }
  if (executed.isEmpty) {
    return ProofVerdict._(
        false,
        'Gate de fluxo: VERMELHO — a suíte reportou ZERO testes executados. '
        'Um verde aqui seria o verde vazio do T-58.',
        const []);
  }
  if (expected != null && executed.length != expected) {
    return ProofVerdict._(
        false,
        'Gate de fluxo: VERMELHO — o workflow esperava $expected teste(s) e a '
        'suíte executou ${executed.length}: ${executed.join('; ')}. Um teste '
        'novo bumpa a contagem no verify.yml; um teste a menos é o gate '
        'afirmando menos do que declara.',
        executed);
  }
  final demanded = expected == null ? '' : ' de $expected';
  return ProofVerdict._(
      true,
      'Gate de fluxo: ${executed.length}$demanded teste(s) PROVADO(S): '
      '${executed.join('; ')}',
      executed);
}

List<String> _names(Object? raw) =>
    raw is List ? raw.map((e) => e.toString()).toList() : const [];

// T-58 — the suite's own proof that it RAN.
//
// The web driver cannot tell an empty run from a full one (the whole story is
// in `test_driver/e2e_proof.dart`), so the suite reports what it did and the
// driver refuses a run with no report.
//
// It is a per-test `tearDown`, not a `tearDownAll`, on purpose. A `tearDownAll`
// still runs after a `setUpAll` that threw, so it could only ever report an
// honest zero — the same verdict, one more moving part that has to run, and
// one that shares its slot with `family.purge()`, which throws on an
// uninitialised `late` in exactly that case. A `tearDown` runs once per test
// that RAN: zero tests → zero tearDowns → `reportData` stays null → the driver
// goes red on "the suite reported nothing", which is the T-58 case by name.
//
// `binding.results` is the binding's own ledger: `runTest` writes `'success'`
// for a test that reached its end and `reportTestException` replaces it with
// a `Failure`, both BEFORE the test's tearDowns run. A test skipped with
// `skip:` never reaches `runTest` and so is never counted — which is why the
// full-pack tests are skipped that way and not with an early `return`: a body
// that returns on its first line would count as executed, the vacuous green
// in miniature.
//
// T-71 (13/09/2026) — the setUpAll reports too, and it reports its ERROR.
// On the web the suite runs in the browser and `flutter drive -d web-server`
// has no DWDS, so nothing the suite prints reaches the job log. When the
// `setUpAll` throws, `package:test` prints the exception to the browser
// console and the driver sees only "the suite reported nothing" — the SHAPE of
// the red, never its cause. Main run 34731668538 attempt 1 (13/09/2026,
// `account_flows_test`) was exactly that: a `setUpAll` that died ~11 s after
// the page was served, inside the db-gate's window, and no way to tell a 429
// from a 500 from a timeout afterwards. So the setUpAll is wrapped: its window
// (start, end, elapsed) always goes into `reportData`, and when it throws the
// exception and stack go with it, BEFORE the rethrow. The binding's own
// `tearDownAll` still completes `allTestsPassed` and `_requestData` sends
// `reportData` in every outcome (both read out of `integration_test` 3.44.7),
// so the error text rides the same channel as the proof.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// The keys the driver reads (`test_driver/e2e_proof.dart`). Spelled AGAIN
/// here on purpose: on the web `flutter drive` compiles `integration_test/`
/// as the application root, so `../test_driver/…` does not exist there
/// (measured 12/09/2026: "Error when reading
/// 'org-dartlang-app:/test_driver/e2e_proof.dart': File not found"). A
/// deliberate mirror, like the seven in `entrelares_core/test/mirrors/` —
/// `web_channel_test` pins the two spellings against each other.
const executedKey = 'executed';
const failedKey = 'failed';

/// The setUpAll's own report (T-71): `startedAt`/`finishedAt` (UTC ISO 8601),
/// `elapsedMs`, and — only when it threw — `error` and `stack`.
const setUpAllKey = 'setUpAll';

/// Call once in `main()`, right after `ensureInitialized()`, before any test
/// is declared. `web_channel_test` fails if a suite under `integration_test/`
/// forgets it.
void proveExecution(IntegrationTestWidgetsFlutterBinding binding) {
  tearDown(() {
    final executed = <String>[];
    final failed = <String>[];
    for (final entry in binding.results.entries) {
      (entry.value == 'success' ? executed : failed).add(entry.key);
    }
    binding.reportData = {
      ...?binding.reportData,
      executedKey: executed,
      failedKey: failed,
    };
  });
}

/// The suite's `setUpAll`, reporting (T-71). Use this INSTEAD of a bare
/// `setUpAll` in every suite under `integration_test/` — `web_channel_test`
/// refuses the bare one, because a setUpAll that throws outside this wrapper
/// is a red nobody can root-cause after the fact.
///
/// The window is reported in every outcome: a green run's setUpAll timestamps
/// are what cross a later red against the db-gate's window on the shared dev
/// project (hypothesis H1) without reopening the job log.
void provedSetUpAll(
  IntegrationTestWidgetsFlutterBinding binding,
  Future<void> Function() body,
) {
  setUpAll(() async {
    final started = DateTime.now().toUtc();
    Map<String, Object> window(DateTime finished) => {
          'startedAt': started.toIso8601String(),
          'finishedAt': finished.toIso8601String(),
          'elapsedMs': finished.difference(started).inMilliseconds,
        };
    try {
      await body();
      binding.reportData = {
        ...?binding.reportData,
        setUpAllKey: window(DateTime.now().toUtc()),
      };
    } catch (error, stack) {
      binding.reportData = {
        ...?binding.reportData,
        setUpAllKey: {
          ...window(DateTime.now().toUtc()),
          'error': '$error',
          'stack': '$stack',
        },
      };
      rethrow;
    }
  });
}

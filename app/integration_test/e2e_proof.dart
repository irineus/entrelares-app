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

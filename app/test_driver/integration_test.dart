// The driver half of the web E2E lane (T-56, PR 5 — the spike that looks for a
// replacement for the Playwright flow gate that dies with the Blazor client).
//
// On Android `flutter test integration_test/` is enough: the harness runs INSIDE
// the app process. On the web it is not — the test code runs in the browser and
// needs a driver process outside it to talk to chromedriver. This file is that
// process, and the same `integration_test` files run unchanged on both targets.
//
// It used to be `integrationDriver()` and nothing else, and that is the T-58
// defect: the stock driver prints "All tests passed." and exits 0 whenever the
// browser reports no FAILURE — which it also does when no test ran at all. So
// this is the stock driver's sequence (connect → request the result → close),
// with one difference that is the whole item: before saying anything, it asks
// `judge()` whether the suite PROVED it ran, and it exits 1 when it did not.
// The proof is written to `build/e2e_proof.json` in every outcome, so the
// workflow can print what ran, and its absence is a red in its own right.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';
import 'package:integration_test/common.dart';

import 'e2e_proof.dart';

Future<void> main() async {
  final driver = await FlutterDriver.connect();
  final jsonResult =
      await driver.requestData(null, timeout: const Duration(minutes: 20));
  await driver.close();

  final response = Response.fromJson(jsonResult);
  if (!response.allTestsPassed) {
    // The harness's own account of a failing assertion, kept verbatim — it is
    // the Expected/Actual a red run is read from.
    stdout.writeln('Failure Details:\n${response.formattedFailureDetails}');
  }

  final verdict = judge(jsonDecode(jsonResult) as Map<String, dynamic>,
      expected: expectedTests(Platform.environment));

  final proof = File(proofFile);
  await proof.parent.create(recursive: true);
  await proof.writeAsString(
      const JsonEncoder.withIndent('  ').convert(verdict.toJson()));

  stdout.writeln(verdict.message);
  exit(verdict.passed ? 0 : 1);
}

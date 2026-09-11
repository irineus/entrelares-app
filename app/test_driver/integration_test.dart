// The driver half of the web E2E lane (T-56, PR 5 — the spike that looks for a
// replacement for the Playwright flow gate that dies with the Blazor client).
//
// On Android `flutter test integration_test/` is enough: the harness runs INSIDE
// the app process. On the web it is not — the test code runs in the browser and
// needs a driver process outside it to talk to chromedriver. This file is that
// process, and `integrationDriver()` is its whole body: the same
// `integration_test` files then run unchanged on both targets.
library;

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver();

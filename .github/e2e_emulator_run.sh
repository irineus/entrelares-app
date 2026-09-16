#!/usr/bin/env bash
# T-77 (16/09/2026) — one integration suite on the running emulator, bounded,
# and when it does not pass, the evidence is taken BEFORE the action kills the
# emulator.
#
# Why each piece exists:
#   * `--reporter expanded`: on GitHub the default reporter prints a test only
#     when it ENDS. Run 35099892758 sat 30 min after "Installing …apk" with no
#     line at all until the job timeout cancelled it, and nothing said whether
#     it was setUpAll, the p0 test or the teardown. Expanded prints each test
#     as it STARTS, so the last progress line names where it stopped.
#   * `timeout`: the testWidgets `Timeout(5 min)` never fired in that run, so
#     the bound has to live outside Dart. 124 is a hang; anything else is a
#     real failure.
#   * the screenshot and the `flutter` logcat: the only view of the app state
#     at the moment it stopped. The repository is PUBLIC, so the logcat goes to
#     the job log (where GitHub masks secrets) and only the image becomes an
#     artifact.
#
# Usage (from app/): bash ../.github/e2e_emulator_run.sh integration_test/<file>.dart
# Env: E2E_SUPABASE_SERVICE_ROLE_KEY (secret), E2E_PACK (p0|full),
#      E2E_TEST_TIMEOUT (default 15m).
set -uo pipefail

target="$1"
name="$(basename "$target" .dart)"
limit="${E2E_TEST_TIMEOUT:-15m}"
adb="${ANDROID_HOME:-/usr/local/lib/android/sdk}/platform-tools/adb"
diag="build/e2e-diag"
mkdir -p "$diag"

timeout --signal=INT --kill-after=30s "$limit" \
  flutter test "$target" --flavor dev --reporter expanded \
    --dart-define=E2E_SUPABASE_SERVICE_ROLE_KEY="$E2E_SUPABASE_SERVICE_ROLE_KEY" \
    --dart-define=E2E_PACK="${E2E_PACK:-p0}"
status=$?

if [ "$status" -ne 0 ]; then
  if [ "$status" -eq 124 ]; then
    echo "::error::$name did not finish within $limit — the last progress line above names the test it was in."
  fi
  "$adb" exec-out screencap -p > "$diag/$name.png" || true
  echo "::group::logcat (flutter tag, last 300 lines) — $name"
  "$adb" logcat -d -s flutter:V | tail -n 300 || true
  echo "::endgroup::"
fi
exit "$status"

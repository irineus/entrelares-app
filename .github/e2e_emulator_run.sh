#!/usr/bin/env bash
# T-77 (16/09/2026) — the integration suites on the running emulator, one after
# the other, each bounded, and when one does not pass, the evidence is taken
# BEFORE the action kills the emulator.
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
#   * the screenshot and the logcat: the only view of the device at the moment
#     it stopped. The repository is PUBLIC, so the logcat goes to the job log
#     (where GitHub masks secrets) and only the image becomes an artifact.
#
# 21/09/2026 — ONE boot for every suite, and the device made ready before each.
# From 16 to 21/09 the second suite (account_flows_test, then in its own
# emulator step) hung in `setUpAll` in 6 of its 7 runs, run 454 the one green,
# while swap_workflow_test before it passed every time. The dev project's edge
# logs show NO request at all in the 12 minutes of run 511's hang — not even
# the fixture's first GET, whose every call is bounded at 45 s — and both
# screenshots show the launcher with the app off screen (511: "Pixel Launcher
# isn't responding"). A Dart isolate that fires no timer and sends nothing is
# a process that is not running: on API 34 an app that leaves the foreground
# is cached and then FROZEN. So, before each suite:
#   * the app is uninstalled — the second suite starts from the same device
#     state the first one did, instead of over the first one's install;
#   * the cached-apps freezer is turned off, and the setting is read back;
#   * system dialogs (an ANR included) are closed, and the suite waits until
#     no "not responding" window holds the focus.
# And on a red, the logcat carries ActivityManager / AndroidRuntime too, with
# the app's process state: whether it was frozen, killed or never came to the
# front is then in the log, not in a guess.
#
# Usage (from app/): bash ../.github/e2e_emulator_run.sh integration_test/<a>.dart [integration_test/<b>.dart …]
# Env: E2E_SUPABASE_SERVICE_ROLE_KEY (secret), E2E_PACK (p0|full),
#      E2E_TEST_TIMEOUT (per suite, default 15m).
set -uo pipefail

limit="${E2E_TEST_TIMEOUT:-15m}"
adb="${ANDROID_HOME:-/usr/local/lib/android/sdk}/platform-tools/adb"
package="com.entrelares.flutter" # the dev flavour's applicationId
diag="build/e2e-diag"
mkdir -p "$diag"

prepare_device() {
  "$adb" wait-for-device
  "$adb" uninstall "$package" >/dev/null 2>&1 || true
  "$adb" shell settings put global cached_apps_freezer disabled || true
  echo "freezer: $("$adb" shell settings get global cached_apps_freezer | tr -d '\r')" \
    "| $("$adb" shell dumpsys activity settings | grep -i 'use_freezer' | tr -d '\r' | xargs)"
  "$adb" shell input keyevent KEYCODE_WAKEUP || true
  "$adb" shell wm dismiss-keyguard || true
  for _ in $(seq 1 30); do
    "$adb" shell am broadcast -a android.intent.action.CLOSE_SYSTEM_DIALOGS >/dev/null 2>&1 || true
    focus="$("$adb" shell dumpsys window | grep -m1 mCurrentFocus | tr -d '\r')"
    case "$focus" in
      *"Not Responding"*|*"not responding"*|*null*) sleep 2 ;;
      *) break ;;
    esac
  done
  echo "focus before the suite: ${focus:-unknown}"
}

collect_evidence() {
  local name="$1"
  "$adb" exec-out screencap -p > "$diag/$name.png" || true
  echo "::group::device state — $name"
  "$adb" shell dumpsys window | grep -m1 mCurrentFocus || true
  "$adb" shell dumpsys activity processes | grep -A3 "$package" | head -n 40 || true
  echo "::endgroup::"
  echo "::group::logcat (flutter, ActivityManager, AndroidRuntime; last 400 lines) — $name"
  "$adb" logcat -d -s flutter:V ActivityManager:I AndroidRuntime:E DEBUG:E | tail -n 400 || true
  echo "::endgroup::"
}

overall=0
for target in "$@"; do
  name="$(basename "$target" .dart)"
  echo "::group::prepare the device — $name"
  prepare_device
  echo "::endgroup::"
  "$adb" logcat -c || true

  timeout --signal=INT --kill-after=30s "$limit" \
    flutter test "$target" --flavor dev --reporter expanded \
      --dart-define=E2E_SUPABASE_SERVICE_ROLE_KEY="$E2E_SUPABASE_SERVICE_ROLE_KEY" \
      --dart-define=E2E_PACK="${E2E_PACK:-p0}"
  status=$?

  if [ "$status" -ne 0 ]; then
    if [ "$status" -eq 124 ]; then
      echo "::error::$name did not finish within $limit — the last progress line above names the test it was in."
    else
      echo "::error::$name failed (exit $status)."
    fi
    collect_evidence "$name"
    overall=1
  fi
done
exit "$overall"

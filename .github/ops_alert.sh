#!/usr/bin/env bash
# T-68 — a red `main` reaching a human, through the destination T-66 already
# stood up.
#
# WHY NOT THE PRODUCT'S OWN RAILS (the card's explicit trap):
#   * Resend is ONE shared account capped at 100/day and `send-auth-email` has
#     no fallback behind it (§5). An alert storm competing with sign-up
#     confirmations is the failure T-67 exists to prevent.
#   * Push hangs off an AFTER INSERT trigger on `notifications` (F-09), whose
#     rows are FAMILY data with ten pinned types. An ops alert is not a family
#     notification and must never enter that table.
# Neither name appears in this file, and a test in `web_channel_test` keeps it
# that way.
#
# WHY SENTRY AND NOT A SECOND NOTIFIER: the GitHub failure e-mail already
# arrives — measured on the 10/09 incident, 20 seconds after the run concluded.
# What it cannot do is stand out: in those same three days GitHub sent 13
# CI-failure e-mails, 10 of them routine PR noise. This one carries the
# exception type `PipelineFailure` in its subject and lands in the stream that
# already means "production is breaking" (runbook §13.5).
#
# The DSN is PUBLIC config by construction — it can only WRITE events, which is
# why it ships in every browser that loads the web channel (`env.dart`). It is
# passed in rather than repeated here, and `web_channel_test` pins the value in
# the workflow against `Env.prod.sentryDsn`.
set -euo pipefail

dsn="${1:?usage: ops_alert.sh <dsn> <failed jobs> <run url> <sha>}"
jobs="${2:?usage: ops_alert.sh <dsn> <failed jobs> <run url> <sha>}"
run_url="${3:?usage: ops_alert.sh <dsn> <failed jobs> <run url> <sha>}"
sha="${4:?usage: ops_alert.sh <dsn> <failed jobs> <run url> <sha>}"

# https://<key>@<host>/<project>
key="${dsn#https://}"; key="${key%%@*}"
rest="${dsn#*@}"; host="${rest%%/*}"; project="${rest##*/}"

event_id=$(cat /proc/sys/kernel/random/uuid | tr -d '-')
now=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)
short="${sha:0:7}"

# PT-BR because a human reads it at whatever hour it fires, and this repo already
# writes its run summaries that way. Code and comments stay English.
title="main vermelha em $short: $jobs — web.entrelares.app não publicou"

# The fingerprint carries the SHA on purpose. Grouping by job alone would make
# the SECOND incident land inside an existing issue, and an issue that is open
# but unresolved fires no new-issue alert — a silent alarm, which is the exact
# defect this item exists to close. One issue per failing commit; re-runs of the
# SAME commit group together, so an incident alerts once, not once per attempt.
event=$(jq -nc \
  --arg id "$event_id" --arg ts "$now" --arg title "$title" \
  --arg jobs "$jobs" --arg run "$run_url" --arg sha "$sha" --arg short "$short" \
  '{
    event_id: $id, timestamp: $ts, platform: "other", level: "error",
    environment: "prod", logger: "ci",
    exception: { values: [ { type: "PipelineFailure", value: $title } ] },
    fingerprint: [ "ci", "verify", $jobs, $sha ],
    tags: { channel: "ci", workflow: "verify", job: $jobs, branch: "main", commit: $short },
    extra: {
      run_url: $run,
      consequencia: "O merge NÃO chegou a web.entrelares.app. O canal segue servindo o build anterior.",
      item: "T-68"
    }
  }')

printf '%s\n%s\n%s\n' \
  "$(jq -nc --arg id "$event_id" --arg ts "$now" '{event_id: $id, sent_at: $ts}')" \
  "$(jq -nc --argjson len "$(printf '%s' "$event" | wc -c)" '{type: "event", content_type: "application/json", length: $len}')" \
  "$event" > /tmp/ops_alert.envelope

# Auth in the QUERY and a `text/plain` body — the same shape the client uses and
# the runbook verifies by hand (§13.4). The envelope is written in binary-safe
# form above: a CRLF anywhere in it is rejected with
# `missing newline after header or payload`, which reads like a malformed JSON
# and is not one.
code=$(curl -sS --max-time 30 -o /tmp/ops_alert.out -w '%{http_code}' \
  -X POST -H 'Content-Type: text/plain;charset=UTF-8' \
  --data-binary @/tmp/ops_alert.envelope \
  "https://$host/api/$project/envelope/?sentry_key=$key&sentry_version=7")

if [ "$code" = "200" ]; then
  echo "Sentry aceitou o alerta ($(cat /tmp/ops_alert.out))."
  exit 0
fi

echo "::error title=Alerta não enviado::Sentry respondeu $code: $(cat /tmp/ops_alert.out)"
exit 1

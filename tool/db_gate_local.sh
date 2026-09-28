#!/usr/bin/env bash
# The DB gate on an EPHEMERAL local Supabase stack — Fulcrum 04.3.1 / T-94 (28/09/2026).
#
# Why this exists: the gate used to run against the hosted DEV project, and every
# run creates ~344 real auth users through the GoTrue Admin API (measured on this
# stack: 343 sign-ups + 1 invite, 333 of them signing in). The Free plan counts
# every user that authenticated in the billing cycle as a MAU, deleted at
# teardown or not — so 375 gate runs in the 09/09–09/10/2026 cycle put the org
# "Entrelares Dev" at 91,988 / 50,000 MAU, and past the grace period every
# request to the dev project answers 402 (QA web, previews, E2E, api-dev).
#
# Here the stack is built from THIS checkout: `supabase start` applies every
# migration from zero, `supabase/seed.sql` adds the reference rows the hosted
# projects carry as data, and the local edge runtime serves `supabase/functions/`
# — so the gate judges the schema and the functions the branch proposes, with no
# deploy and no shared state between runs.
#
# The functions get three values and nothing real (`supabase/functions/.env`,
# git-ignored, written here):
#   · RESEND_API_KEY — a dummy. Every gate recipient is on `@resend.dev`, which
#     `_shared/mail.ts` suppresses before the outbound call; the key only has to
#     EXIST, because the senders refuse to start without one.
#   · ASAAS_WEBHOOK_TOKEN — random per run, handed to the suite too, so the
#     positive billing-webhook cases are always armed (on dev they depended on an
#     optional secret).
#   · APP_ENVIRONMENT=Development — the "[Dev] " subject tag, as on dev.
#
# Usage (repository root):  bash tool/db_gate_local.sh
#   DART=<cmd>        how to call dart (default: `dart`; locally `fvm dart`)
#   SUPABASE=<cmd>    how to call the CLI (default: `supabase`; locally
#                     `npx --yes supabase@2.105.0` — keep the CI pin)
#   KEEP_STACK=1      leave the stack running afterwards (default: stop it)
# On Windows the default ports 54321-54329 may sit inside a Hyper-V excluded
# range (`netsh interface ipv4 show excludedportrange protocol=tcp`); run from a
# copy of `supabase/` with other ports in `config.toml` — never commit them.
set -euo pipefail

DART=${DART:-dart}
SUPABASE=${SUPABASE:-supabase}
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"

webhook_token=$(openssl rand -hex 24)
cat > supabase/functions/.env <<EOF
RESEND_API_KEY=re_db_gate_local_never_sent
ASAAS_WEBHOOK_TOKEN=$webhook_token
APP_ENVIRONMENT=Development
EOF

# Only what the gate talks to: Postgres, GoTrue, PostgREST, Kong, the edge
# runtime, Realtime and Storage (the start health-checks them). Studio,
# analytics, image proxy, pooler and pg-meta are dead weight on a runner.
# Its banner prints the local keys; they are the CLI's public defaults, identical on every
# machine, and still kept out of a public log (pipefail carries a failed start through).
$SUPABASE start -x studio,logflare,vector,imgproxy,supavisor,postgres-meta |
  sed -E 's/sb_(secret|publishable)_[A-Za-z0-9_-]+/sb_\1_<local default>/g'

# The suite runs from the package directory, so the trap goes back to the root
# first — a relative path here left the .env behind on the first rehearsal.
cleanup() {
  cd "$root"
  rm -f supabase/functions/.env
  if [ "${KEEP_STACK:-0}" != 1 ]; then $SUPABASE stop --no-backup || true; fi
}
trap cleanup EXIT

# `status -o env` prints KEY="value" lines, captured here and never echoed.
status=$($SUPABASE status -o env)
value() { printf '%s\n' "$status" | sed -n "s/^$1=\"\{0,1\}\([^\"]*\)\"\{0,1\}$/\1/p"; }
E2E_SUPABASE_URL=$(value API_URL)
E2E_SUPABASE_ANON_KEY=$(value PUBLISHABLE_KEY)
E2E_SUPABASE_SERVICE_ROLE_KEY=$(value SECRET_KEY)
for name in E2E_SUPABASE_URL E2E_SUPABASE_ANON_KEY E2E_SUPABASE_SERVICE_ROLE_KEY; do
  if [ -z "${!name}" ]; then
    echo "::error::supabase status não devolveu o valor de $name — a stack local subiu?"
    exit 1
  fi
done
case "$E2E_SUPABASE_URL" in
  http://127.0.0.1:*|http://localhost:*) ;;
  *) echo "::error::o gate só roda contra a stack LOCAL, e a URL veio $E2E_SUPABASE_URL"; exit 1 ;;
esac
export E2E_SUPABASE_URL E2E_SUPABASE_ANON_KEY E2E_SUPABASE_SERVICE_ROLE_KEY
export E2E_ASAAS_WEBHOOK_TOKEN=$webhook_token

cd packages/entrelares_db_gate
$DART pub get
$DART analyze --fatal-infos
$DART test --reporter expanded

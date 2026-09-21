#!/usr/bin/env bash
# The Edge Functions this project deploys, in ONE place.
#
# The app repo kept this list twice — once for the dev lane and once for the prod
# lane — and the two drifted: `billing-store-verify` and `billing-store-webhook`
# shipped to dev in lote 5 and only reached the prod list a promotion later, so
# for a while the store rail had a schema and a switch in production with nothing
# to answer the RTDN. Deploying from a single list is what makes that impossible,
# and `assert_function_list_matches_disk` closes the other half: a function added
# to `supabase/functions/` without being added here fails the run instead of being
# silently never deployed.
#
# The split is about JWT verification, and it is not cosmetic. Anything a THIRD
# PARTY calls (Resend, Asaas, Google RTDN, the GoTrue auth hook) or that runs on a
# schedule carries `--no-verify-jwt`, because the caller has no Supabase session
# and the function does its own authentication (shared token, signature, service
# role). Anything a LOGGED-IN user calls keeps verification on, so the platform
# rejects an anonymous request before our code runs.

FUNCTIONS_NO_JWT="send-swap-email auto-approve-expired register-invitee purge-deleted send-account-email billing-webhook billing-store-verify billing-store-webhook send-auth-email send-push-notification send-support-request"
FUNCTIONS_WITH_JWT="elevate billing-checkout admin-update-member-email claim-invitation"

# esm.sh 522s and rate limits have taken whole runs down on transient failure
# alone. `db push` and `functions deploy` are both idempotent, so retrying is free.
retry() {
  local n=1
  while true; do
    "$@" && return 0
    [ $n -ge 3 ] && return 1
    echo "Tentativa $n falhou — aguardando $((n * 15))s"
    sleep $((n * 15))
    n=$((n + 1))
  done
}

assert_function_list_matches_disk() {
  local declared ondisk d name
  declared=$(printf '%s\n' $FUNCTIONS_NO_JWT $FUNCTIONS_WITH_JWT | sort)
  # `_shared` is a library, not a deployable function. Filtered in the shell
  # rather than with `grep -v`, which exits 1 when it matches nothing and would
  # take the whole step down under `set -e`.
  ondisk=$(for d in supabase/functions/*/; do
    name=$(basename "$d")
    case "$name" in _*) ;; *) echo "$name" ;; esac
  done | sort)
  if [ "$declared" != "$ondisk" ]; then
    echo "::error::A lista de Edge Functions em .github/functions.sh divergiu de supabase/functions/."
    diff <(echo "$declared") <(echo "$ondisk") || true
    return 1
  fi
}

deploy_functions() {
  local ref="$1" f
  assert_function_list_matches_disk || return 1
  for f in $FUNCTIONS_NO_JWT; do
    retry supabase functions deploy "$f" --no-verify-jwt --project-ref "$ref" || return 1
  done
  for f in $FUNCTIONS_WITH_JWT; do
    retry supabase functions deploy "$f" --project-ref "$ref" || return 1
  done
  # Warm-up of send-auth-email: GoTrue gives the Send Email Hook a FIXED 5s, and
  # the first boot after a redeploy can exceed it (12/08/2026: a ~5,12s cold start
  # became hook_timeout → signup 422 → red smoke; in production the victim would be
  # a real sign-up). An empty POST is refused by the signature check in
  # milliseconds, but it forces the isolate up before the first real use.
  curl -s -o /dev/null -X POST "https://$ref.supabase.co/functions/v1/send-auth-email" || true
}

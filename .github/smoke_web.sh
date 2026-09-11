#!/usr/bin/env bash
# T-68 — proving the web channel is serving the commit that was just merged.
#
# Exit code 0 from `wrangler pages deploy` is not proof. T-58 is already on the
# board for exactly this: a gate that reported "All tests passed." while running
# zero tests. A publish can succeed loudly and deliver nothing, and the first
# symptom would be a future delivery that "didn't go up".
#
# THE TRAP THIS SCRIPT IS SHAPED AROUND: `web/_redirects` ends with
# `/*  /index.html  200`, the SPA fallback every deep link needs. So a request
# for a file that IS NOT THERE comes back **200, with the index.html body**
# (measured 11/09/2026: 5 917 bytes of HTML). A check written as `curl -f` —
# or any check that reads the STATUS — passes over the void. That is why this
# compares the BODY, byte for byte, against the sha it expects.
#
# The marker is the commit sha and not the app version on purpose. `version.json`
# only changes when the pubspec does, and a delivery that does not bump it
# (T-69 was a pure rename) would publish nothing and still match — green about
# nothing, one more time.
set -euo pipefail

host="${1:?usage: smoke_web.sh <https://host> <expected-sha>}"
expected="${2:?usage: smoke_web.sh <https://host> <expected-sha>}"

# Cloudflare Pages promotes a deployment within seconds of wrangler returning,
# but "within seconds" is not a contract. Eighteen tries, ten seconds apart, is
# three minutes of patience before calling a publish broken — long enough that a
# slow promotion is not reported as an incident, short enough that a real one
# does not wait for somebody to notice.
attempts="${SMOKE_ATTEMPTS:-18}"
pause="${SMOKE_SLEEP:-10}"

url="$host/build-id.txt"
served=""

for attempt in $(seq 1 "$attempts"); do
  # Cache-busting on both ends: a query the origin ignores, and the request
  # headers, so neither the edge nor any proxy in between can answer with the
  # build we are trying to prove is gone.
  served=$(curl -sS --max-time 20 \
    -H 'Cache-Control: no-cache' -H 'Pragma: no-cache' \
    "$url?cb=$(date +%s%N)" 2>/dev/null | tr -d '\r\n' || true)

  if [ "$served" = "$expected" ]; then
    echo "Canal web serve $expected (tentativa $attempt/$attempts)."
    if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
      echo "### Canal web: publicação PROVADA" >> "$GITHUB_STEP_SUMMARY"
      echo "\`$host\` está servindo o commit \`$expected\` (tentativa $attempt de $attempts)." >> "$GITHUB_STEP_SUMMARY"
    fi
    exit 0
  fi

  echo "tentativa $attempt/$attempts: ainda não é $expected"
  [ "$attempt" -lt "$attempts" ] && sleep "$pause"
done

# What came back matters as much as the failure itself: the SPA fallback answering
# means the file is not published at all, which is a different bug from an old
# build still being served.
if printf '%s' "$served" | grep -qi '<!doctype html'; then
  got="o FALLBACK SPA (index.html) — /build-id.txt não está publicado"
elif [ -z "$served" ]; then
  got="nada (host inalcançável ou resposta vazia)"
else
  got="\`$(printf '%s' "$served" | head -c 120)\`"
fi

{
  echo "### Canal web: publicação NÃO PROVADA"
  echo "\`$url\` deveria servir \`$expected\` e serviu $got, depois de $attempts tentativas."
  echo "O deploy pode ter terminado sem publicar nada. NÃO tratar o verde do \`wrangler\` como prova."
} >> "${GITHUB_STEP_SUMMARY:-/dev/stdout}"

echo "::error title=Publicação não provada::$url serviu $got em vez de $expected"
exit 1

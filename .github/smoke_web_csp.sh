#!/usr/bin/env bash
# T-73 — the page the browser receives must not name a script its own CSP
# refuses.
#
# `web_channel_test` proves the CSP against every reference the SOURCE makes
# (T-66 put the Sentry host in `connect-src`, T-72 the manifest images in
# `img-src`). It cannot see a reference added AFTER the build. Measured
# 14/09/2026: Cloudflare's Web Analytics, switched on for the zone, appended
# `<script src="https://static.cloudflareinsights.com/beacon.min.js/…">` to
# every HTML response of `web.entrelares.app` — a script `script-src` blocks on
# every load, from a second analytics product no document named.
#
# TWO TRAPS THIS SCRIPT IS SHAPED AROUND:
#   * The edge injects ONLY when the request says it wants HTML. A plain curl
#     (`Accept: */*`) came back clean over the same URL, the same minute. So
#     this asks the way a browser navigation asks.
#   * It reads the CSP the edge SERVED, not `_headers`: the header the browser
#     enforces is the one on the wire, and a check against the source file
#     would agree with itself.
#
# And, per T-58, it has to prove it looked: a page in which it finds not even
# our own `flutter_bootstrap.js` is not a page it checked, and it goes RED.
set -euo pipefail
# `*.example.com` is a CSP source here, never a glob against the runner's disk.
set -f

host="${1:?usage: smoke_web_csp.sh <https://host>}"
# The root and one SPA route: the edge rewrites both, and a deep link is how an
# e-mail brings people in.
paths="${SMOKE_CSP_PATHS:-/ /calendar}"

served_host="${host#*://}"
served_host="${served_host%%/*}"
served_host="${served_host%%:*}"

work=$(mktemp -d)
checked=()
violations=()

for path in $paths; do
  curl -sS --compressed --max-time 20 --retry 3 \
    -D "$work/head" -o "$work/body" \
    -H 'Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8' \
    -H 'Cache-Control: no-cache' -H 'Pragma: no-cache' \
    -A 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0 Mobile Safari/537.36' \
    "$host$path"

  csp=$(grep -i '^content-security-policy:' "$work/head" | tail -n 1 \
    | cut -d: -f2- | tr -d '\r' || true)
  if [ -z "$csp" ]; then
    violations+=("\`$path\` foi servido SEM Content-Security-Policy")
    continue
  fi

  # `script-src`, or `default-src` when the policy does not name it.
  directive() {
    printf '%s' "$csp" | tr ';' '\n' \
      | sed -nE "s/^[[:space:]]*$1[[:space:]]+(.*)$/\1/p" | head -n 1
  }
  allowed=$(directive script-src)
  [ -z "$allowed" ] && allowed=$(directive default-src)

  srcs=$(grep -oiE '<script[^>]*[[:space:]]src=("[^"]*"|'"'"'[^'"'"']*'"'"')' "$work/body" \
    | sed -E 's/.*[[:space:]][sS][rR][cC]=["'"'"']?//; s/["'"'"']$//' || true)

  if ! grep -q 'flutter_bootstrap\.js' <<<"$srcs"; then
    violations+=("\`$path\` não trouxe o \`flutter_bootstrap.js\` — a página lida NÃO é o app, e nada foi verificado")
    continue
  fi

  for src in $srcs; do
    case "$src" in
      //*) scheme=https; rest="${src#//}" ;;
      http://* | https://*) scheme="${src%%://*}"; rest="${src#*://}" ;;
      *) checked+=("$path $src"); continue ;; # relative: our own origin, `'self'`
    esac
    h="${rest%%/*}"
    h="${h%%:*}"

    covered=false
    for source in $allowed; do
      case "$source" in
        "'self'") [ "$h" = "$served_host" ] && covered=true ;;
        "$scheme:") covered=true ;;
        "$scheme://$h" | "$scheme://$h/"*) covered=true ;;
        "$scheme://*."*)
          suffix="${source#"$scheme://*."}"
          suffix="${suffix%%/*}"
          case "$h" in *."$suffix") covered=true ;; esac
          ;;
      esac
    done

    if $covered; then
      checked+=("$path $src")
    else
      violations+=("\`$path\` carrega \`$src\`, e o \`script-src\` servido (\`$allowed\`) recusa \`$h\`")
    fi
  done
done

rm -rf "$work"

if [ "${#violations[@]}" -eq 0 ]; then
  echo "Nenhum script fora da CSP em $host ($paths): ${#checked[@]} verificados."
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    {
      echo "### Canal web: todo script servido cabe na CSP"
      echo "\`${#checked[@]}\` scripts lidos em \`$paths\`, pedindo HTML como um navegador pede."
    } >> "$GITHUB_STEP_SUMMARY"
  fi
  exit 0
fi

{
  echo "### Canal web: a página servida carrega script que a própria CSP RECUSA"
  echo "O build publicou (o passo anterior provou), mas o que chega ao navegador não é só o que o build tem:"
  for v in "${violations[@]}"; do echo "- $v"; done
  echo ""
  echo "Host que ninguém do repo cita costuma ser injeção de BORDA (T-73: Web Analytics do Cloudflare). O remédio é desligar na borda, não alargar a CSP."
} >> "${GITHUB_STEP_SUMMARY:-/dev/stdout}"

for v in "${violations[@]}"; do
  echo "::error title=Script fora da CSP::$v"
done
exit 1

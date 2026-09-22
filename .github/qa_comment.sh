#!/usr/bin/env bash
# T-79 — ONE comment per PR saying where to test it, edited on every push so
# the link on the owner's phone is always the latest. It also says what was
# NOT built, and why: "nothing arrived" and "nothing was meant to arrive" must
# not look the same.
#
# Reads the `qa-preview` job's env: PR_NUMBER, APK_CHANGED, WEB_CHANGED,
# APK_SENT (the version sent, empty if none), WEB_URL (empty if none), GH_TOKEN.
set -euo pipefail

marker='<!-- t79-qa-preview -->'

if [ -n "${APK_SENT:-}" ]; then
  apk="📱 **App dev \`$APK_SENT\`** enviado pelo Firebase App Distribution (grupo \`qa\`) — abra o e-mail ou o app *App Tester* no celular."
elif [ "${APK_CHANGED:-}" = "true" ]; then
  apk="📱 App dev: **não enviado** — faltam secrets ou o build falhou; veja o run."
else
  apk="📱 App dev: nenhum arquivo que entra no APK mudou (\`.github/qa_inputs/apk.txt\`) — nada a instalar."
fi

if [ -n "${WEB_URL:-}" ]; then
  web="🌐 **Web de QA:** $WEB_URL — banco de QA; é aqui que entra a segunda conta."
elif [ "${WEB_CHANGED:-}" = "true" ]; then
  web="🌐 Web de QA: **não publicado** — falta o secret do Cloudflare ou o deploy falhou; veja o run."
else
  web="🌐 Web de QA: nada que entra no bundle web mudou — use https://qa.entrelares.app (o \`main\` no banco de QA)."
fi

run="$GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID"
body=$(printf '%s\n%s\n\n%s\n\n%s\n\n%s' \
  "$marker" "### QA deste PR (commit \`${GITHUB_SHA:0:7}\`)" "$apk" "$web" "[run]($run)")

existing=$(gh api "repos/$GITHUB_REPOSITORY/issues/$PR_NUMBER/comments" --paginate \
  --jq "map(select(.body | startswith(\"$marker\"))) | .[0].id // empty")
if [ -n "$existing" ]; then
  gh api -X PATCH "repos/$GITHUB_REPOSITORY/issues/comments/$existing" -f body="$body" >/dev/null
else
  gh api "repos/$GITHUB_REPOSITORY/issues/$PR_NUMBER/comments" -f body="$body" >/dev/null
fi
echo "Comentário de QA atualizado no PR #$PR_NUMBER."

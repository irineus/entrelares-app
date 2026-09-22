#!/usr/bin/env bash
# T-79 — the QA web's Pages project, created on first use.
#
# `entrelares-web-qa`, NEVER `entrelares-web` (production). Pages project names
# are IMMUTABLE (the F-54 rebrand paid for that), so the name is pinned here and
# in the two deploy lines of `verify.yml`, and `play_release_test` checks all
# three agree. Idempotent: an existing project is left exactly as it is.
set -euo pipefail

project="entrelares-web-qa"
if wrangler pages project list 2>/dev/null | grep -qw -- "$project"; then
  echo "Projeto Pages $project já existe."
else
  wrangler pages project create "$project" --production-branch=main
  echo "Projeto Pages \`$project\` CRIADO — anexe \`qa.entrelares.app\` a ele (T-79)." >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
fi

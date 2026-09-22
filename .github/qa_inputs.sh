#!/usr/bin/env bash
# T-79 — does this PR change something that goes inside the build?
#
#   qa_inputs.sh <list> <base-sha>   → prints `true` or `false`
#
# The list is one of `.github/qa_inputs/*.txt`: a line ending in `/` is a
# prefix, any other line one exact file, `#` starts a comment. The first path
# that matched goes to stderr, so the run log says WHY a build happened.
set -euo pipefail

list="${1:?usage: qa_inputs.sh <list> <base-sha>}"
base="${2:?usage: qa_inputs.sh <list> <base-sha>}"

mapfile -t inputs < <(grep -vE '^[[:space:]]*(#|$)' "$list")

while IFS= read -r path; do
  for input in "${inputs[@]}"; do
    if [[ "$input" == */ ]]; then
      [[ "$path" == "$input"* ]] || continue
    else
      [[ "$path" == "$input" ]] || continue
    fi
    echo "$(basename "$list" .txt): $path ($input)" >&2
    echo true
    exit 0
  done
done < <(git diff --name-only "$base"...HEAD)

echo "$(basename "$list" .txt): nenhum arquivo desta lista mudou" >&2
echo false

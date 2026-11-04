#!/usr/bin/env bash
# gate-proof (04/11/2026) — was the tree `main` just received already proven,
# byte for byte, by a green PR run of `verify`?
#
# Writes `proven=true` to $GITHUB_OUTPUT only when ALL of these hold:
#   1. the pushed commit belongs to a PR of THIS repository, merged into `main`;
#   2. a `pull_request` run of `verify` on that PR's final head concluded
#      `success`, and in it `db-gate` and every `web-e2e` leg concluded
#      `success` (a run green with a gate SKIPPED proves nothing);
#   3. the `tested-tree` artifact of that run names the same tree as HEAD.
#
# Anything else — no PR, an API error, an expired artifact, `main` having moved
# between that run and the merge — writes `proven=false`, and `db-gate` and
# `web-e2e` run on the push as they always did. This script must only ever be
# able to ADD work to the push run, never to wave a gate through on doubt, so
# every failure path below ends in `false` and exit 0.
set -uo pipefail

repo="$GITHUB_REPOSITORY"
summary="${GITHUB_STEP_SUMMARY:-/dev/null}"

answer() {
  echo "proven=$1" >> "$GITHUB_OUTPUT"
  echo "### Gates no push: $2" >> "$summary"
  echo "$2"
  exit 0
}

tree=$(git rev-parse 'HEAD^{tree}') || answer false "rodam aqui — não consegui ler a árvore de HEAD."

pulls=$(gh api "repos/$repo/commits/$GITHUB_SHA/pulls") \
  || answer false "rodam aqui — a API não disse de que PR veio \`${GITHUB_SHA:0:7}\`."
pr=$(jq -r --arg repo "$repo" '
  [.[] | select(.merged_at != null and .base.ref == "main"
                and .head.repo.full_name == $repo)]
  | first | if . then "\(.number) \(.head.sha)" else "" end' <<<"$pulls")
[ -n "$pr" ] || answer false "rodam aqui — \`${GITHUB_SHA:0:7}\` não veio de um PR deste repositório mergeado em \`main\`."
read -r number head <<<"$pr"

runs=$(gh api "repos/$repo/actions/workflows/verify.yml/runs?event=pull_request&head_sha=$head&status=success&per_page=20") \
  || answer false "rodam aqui — a API não listou os runs do PR #$number."
ids=$(jq -r --arg repo "$repo" '
  .workflow_runs[] | select(.head_repository.full_name == $repo) | .id' <<<"$runs")
[ -n "$ids" ] || answer false "rodam aqui — o PR #$number não tem run verde do \`verify\` no head \`${head:0:7}\`."

for id in $ids; do
  jobs=$(gh api "repos/$repo/actions/runs/$id/jobs?per_page=100") || continue
  gates_green=$(jq -r '
    [.jobs[] | select(.name == "db-gate" or (.name | startswith("web-e2e (")))] as $g
    | ($g | map(select(.name == "db-gate")) | length) == 1
      and ($g | map(select(.name | startswith("web-e2e ("))) | length) >= 1
      and ($g | all(.conclusion == "success"))' <<<"$jobs")
  [ "$gates_green" = "true" ] || continue

  dir="$RUNNER_TEMP/tested-tree-$id"
  gh run download "$id" --repo "$repo" --name tested-tree --dir "$dir" >/dev/null 2>&1 || continue
  tested=$(tr -d '[:space:]' < "$dir/tested-tree.txt" 2>/dev/null) || continue

  if [ "$tested" = "$tree" ]; then
    url="$GITHUB_SERVER_URL/$repo/actions/runs/$id"
    answer true "PULADOS — a árvore \`${tree:0:12}\` é exatamente a que o run do PR #$number provou ($url): \`db-gate\` e \`web-e2e\` verdes sobre os mesmos bytes."
  fi
done

answer false "rodam aqui — nenhum run verde do PR #$number testou esta árvore (\`main\` andou entre o run e o merge, ou o registro expirou)."

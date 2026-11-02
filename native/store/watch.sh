#!/usr/bin/env bash
# The app store's watcher (.github/workflows/store-watch.yml): when a branch in
# apps.json has a commit the published store (store-latest) wasn't built from,
# or an app isn't in the store yet, starts a build of main, which publishes it.
# Needs gh with GH_TOKEN and GH_REPO, git and jq.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"

catalog="$(gh release download store-latest -p index.json -O - 2>/dev/null || echo '{"apps":[]}')"
stale=()
while IFS=$'\t' read -r id repo branch; do
  upstream="$(git ls-remote "$repo" "refs/heads/$branch" | cut -f1)"
  published="$(jq -r --arg id "$id" '.apps[] | select(.id == $id) | .commit // empty' <<<"$catalog")"
  echo "$id: $repo $branch is at ${upstream:-?}, the store has ${published:-nothing}"
  if [ -z "$upstream" ]; then echo "::warning::$id: no branch $branch in $repo"; continue; fi
  [ "$upstream" = "$published" ] || stale+=("$id")
done < <(jq -r '.apps[] | [.id, .repo, (.branch // "main")] | @tsv' "$HERE/apps.json")

if [ ${#stale[@]} -eq 0 ]; then echo "The store is up to date"; exit 0; fi
echo "Out of date: ${stale[*]}"
# A build of main that is already queued or running will pick the new commits up.
busy="$(gh run list --workflow android.yml --branch main --limit 10 --json status \
  -q '[.[] | select(.status != "completed")] | length')"
if [ "$busy" != 0 ]; then echo "A build of main is already running; it builds the newest commits"; exit 0; fi
gh workflow run android.yml --ref main
echo "Started a build of main to publish ${stale[*]}"

#!/usr/bin/env bash
# The app store's watcher (.github/workflows/store-watch.yml). The store ships
# fixed releases: apps.json pins each app to a commit, and only a change to
# apps.json (a new release) changes the store. This lists the apps whose
# branch has moved past their pin, for the next release, in the run's summary.
# Needs git and jq.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
summary="${GITHUB_STEP_SUMMARY:-/dev/stdout}"
release="$(jq -r '.release // "unnamed"' "$HERE/apps.json")"

newer=()
while IFS=$'\t' read -r id repo branch pin; do
  upstream="$(git ls-remote "$repo" "refs/heads/$branch" | cut -f1)"
  if [ -z "$upstream" ]; then echo "::warning::$id: no branch $branch in $repo"; continue; fi
  echo "$id: pinned to ${pin:-nothing}, $branch is at $upstream"
  if [ "$upstream" != "$pin" ]; then newer+=("| $id | ${pin:0:7} | ${upstream:0:7} | $repo/compare/${pin:-$branch}...$upstream |"); fi
done < <(jq -r '.apps[] | [.id, .repo, (.branch // "main"), (.commit // "")] | @tsv' "$HERE/apps.json")

{
  echo "## App store release $release"
  if [ ${#newer[@]} -eq 0 ]; then
    echo "Every app is pinned to the newest commit of its branch."
  else
    echo "Apps with newer commits than this release, for the next one (update their \`commit\` in native/store/apps.json):"
    echo
    echo "| App | Pinned | Newest | Changes |"
    echo "|---|---|---|---|"
    printf '%s\n' "${newer[@]}"
  fi
} >> "$summary"

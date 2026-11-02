#!/usr/bin/env bash
# Builds the app store's apps from other repositories (apps.json) into
# DeskDroid's Qt prefix for Android, each from the newest commit of its branch.
# native/nativedesk/build.sh packages them for the store afterwards.
#
#   native/store/build-apps.sh <prefix> <ndk-dir> [id...]
#
# Needs QT_HOST_PATH (desktop Qt 6, for moc), git, jq, cmake and ninja.
# The commit each app was built from goes to <prefix>/share/deskdroid-store/<id>.source,
# which build.sh puts in the store's catalog. An app that fails to build is
# reported and left out; the others still build.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
PREFIX="$(cd "$1" && pwd)"
NDK="$2"
shift 2
: "${QT_HOST_PATH:?QT_HOST_PATH must point to a desktop Qt 6}"
API=29
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$PREFIX/share/deskdroid-store" "$PREFIX/logs"

ids=("$@")
[ ${#ids[@]} -gt 0 ] || mapfile -t ids < <(jq -r '.apps[].id' "$HERE/apps.json")
failed=()
for id in "${ids[@]}"; do
  entry="$(jq -c --arg id "$id" '.apps[] | select(.id == $id)' "$HERE/apps.json")"
  [ -n "$entry" ] || { echo "== $id: not in apps.json"; failed+=("$id"); continue; }
  repo="$(jq -r .repo <<<"$entry")"; branch="$(jq -r '.branch // "main"' <<<"$entry")"; recipe="$(jq -r .recipe <<<"$entry")"
  sha="$(git ls-remote "$repo" "refs/heads/$branch" | cut -f1)"
  if [ -z "$sha" ]; then echo "== $id: no branch $branch in $repo"; failed+=("$id"); continue; fi
  echo "== $id: $repo $branch at $sha"
  src="$WORK/$id/src"; mkdir -p "$src" "$WORK/$id/work"
  log="$PREFIX/logs/store-$id.log"
  rm -f "$PREFIX/share/deskdroid-store/$id.source" "$PREFIX/lib/lib$id.so"
  set +e
  (
    set -euo pipefail
    git -C "$src" init -q
    git -C "$src" fetch -q --depth 1 "$repo" "$sha"
    git -C "$src" checkout -q FETCH_HEAD
    STORE_ID="$id" STORE_SRC="$src" STORE_SHA="$sha" STORE_WORK="$WORK/$id/work" \
      PREFIX="$PREFIX" NDK="$NDK" API="$API" QT_HOST_PATH="$QT_HOST_PATH" \
      bash -euo pipefail "$HERE/recipes/$recipe.sh"
    test -e "$PREFIX/lib/lib$id.so"
    test -e "$PREFIX/share/applications/$id.desktop"
  ) > "$log" 2>&1
  rc=$?
  set -e
  if [ $rc -eq 0 ]; then
    printf '%s %s\n' "$repo" "$sha" > "$PREFIX/share/deskdroid-store/$id.source"
    echo "   built: $(du -h "$PREFIX/lib/lib$id.so" | cut -f1)"
  else
    echo "== $id FAILED"
    grep -E "error:|Error|undefined|not found" "$log" | head -40 || true
    echo "-- last lines:"; tail -40 "$log"
    failed+=("$id")
  fi
done
if [ ${#failed[@]} -gt 0 ]; then
  echo "::error::App store apps that failed to build: ${failed[*]}"
  exit 1
fi

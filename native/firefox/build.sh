#!/usr/bin/env bash
# Builds Firefox (vanilla, from mozilla-firefox/firefox at source.txt) for
# the native desktop: desktop Firefox on GTK 3/Wayland, for Android's libc,
# against the GTK stack native/plasma/build-deps.sh builds.
#
#   native/firefox/build.sh <deps prefix> <ndk dir> <source dir> <out dir>
#
# Any Firefox-based source works (Floorp's runtime too): the source tree is an
# argument, the branding is BRANDING (default: Etherium, etherium/: Firefox
# under DeskDroid's own name and icon, with nothing phoning home and uBlock
# Origin installed).
#
# Like Termux's Firefox, the build treats Android as Linux (termux-patches/):
# desktop Gecko with Bionic, without GeckoView's Java-backed Android parts.
#
# Leaves the packaged browser (a tarball) in <out dir>. Logs go there too.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
PREFIX="$(cd "$1" && pwd)"; NDK="$2"; SRC="$(cd "$3" && pwd)"; OUT="$(mkdir -p "$4" && cd "$4" && pwd)"
BRANDING="${BRANDING:-browser/branding/etherium}"
# Where the browser's own folder is on the phone (NativeDesk.kt: files/kwin/firefox).
DESKDROID_FIREFOX_DIR=/data/data/io.deskdroid.app/files/kwin/firefox
UBLOCK_URL="${UBLOCK_URL:-https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi}"
# Where the browser finds its files on the phone (Termux's @TERMUX_PREFIX@).
DESKDROID_PREFIX=/data/data/io.deskdroid.app/files/usr

# Termux's patches. One that doesn't apply (another Firefox-based source
# may differ in places) is reported, not fatal: the build shows if it mattered.
cd "$SRC"
failed=()
for p in "$HERE"/termux-patches/*.patch; do
  if sed "s|@TERMUX_PREFIX@|$DESKDROID_PREFIX|g" "$p" | patch -p1 --forward --fuzz=2 -s --no-backup-if-mismatch -r - >/dev/null 2>&1; then
    echo "   patch: $(basename "$p")"
  else
    failed+=("$(basename "$p")")
    sed "s|@TERMUX_PREFIX@|$DESKDROID_PREFIX|g" "$p" | patch -p1 --forward --fuzz=2 --dry-run 2>&1 | sed 's/^/     /' | head -10 || true
  fi
done
[ ${#failed[@]} -eq 0 ] || echo "== patches that didn't apply: ${failed[*]}"
python3 "$HERE/deskdroid.py" "$SRC"
[ "$BRANDING" != browser/branding/etherium ] || python3 "$HERE/etherium/branding.py" "$SRC"

# glibc's libpthread and librt are part of Bionic's libc: empty stand-ins
# for the build files that still ask for them (Termux ships the same).
STUBLIBS="$HOME/firefox-stublibs"; mkdir -p "$STUBLIBS"
for l in pthread rt; do "$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-ar" rc "$STUBLIBS/lib$l.a"; done

LIBCLANG="$(dirname "$(ls /usr/lib/llvm-*/lib/libclang.so* | sort -V | tail -1)")"
sed -e "s|@NDK@|$NDK|g" -e "s|@PREFIX@|$PREFIX|g" -e "s|@LIBCLANG@|$LIBCLANG|g" -e "s|@BRANDING@|$BRANDING|g" -e "s|@STUBLIBS@|$STUBLIBS|g" \
  "$HERE/mozconfig" > "$SRC/mozconfig"
cat "$SRC/mozconfig"

export MOZBUILD_STATE_PATH="$HOME/.mozbuild" MACH_BUILD_PYTHON_NATIVE_PACKAGE_SOURCE=pip
# Options this configuration doesn't offer come out of the mozconfig (and
# out of the log) instead of costing a whole run each.
for try in 1 2 3 4 5 6 7 8; do
  set +e
  ./mach --no-interactive configure > "$OUT/configure.log" 2>&1
  rc=$?
  set -e
  bad="$(sed -n 's/.*InvalidOptionError: \(--[a-z0-9-]*\) is not available in this configuration.*/\1/p' "$OUT/configure.log" | head -1)"
  [ $rc -ne 0 ] && [ -n "$bad" ] || break
  echo "== dropping $bad (not available here)"
  sed -i "/ac_add_options $bad\$/d" mozconfig
done
tail -60 "$OUT/configure.log"
[ $rc -eq 0 ] || { echo "== configure FAILED"; exit 1; }

set +e
./mach --no-interactive build --keep-going > "$OUT/build.log" 2>&1
rc=$?
set -e
if [ $rc -ne 0 ]; then
  echo "-- distinct errors:"
  grep -E "(error|Error)(\[E[0-9]+\])?:" "$OUT/build.log" | grep -v "version script assignment" \
    | sed 's|^.*/obj-deskdroid/||; s|^.*'"$SRC"'/||; s|^ *[0-9:.]* E ||' | sort -u | head -200 || true
  echo "-- last lines:"
  tail -40 "$OUT/build.log"
  echo "== build FAILED"
  exit 1
fi
./mach package > "$OUT/package.log" 2>&1 || { tail -60 "$OUT/package.log"; exit 1; }
pkg="$(ls obj-deskdroid/dist/*.tar.* | head -1)"
if [ "$BRANDING" = browser/branding/etherium ]; then
  # Etherium's policies (etherium/policies.json) and uBlock Origin, in the
  # browser's distribution folder, where Firefox looks for both.
  rm -rf "$OUT/pkg" && mkdir -p "$OUT/pkg" && tar xf "$pkg" -C "$OUT/pkg"
  dist="$OUT/pkg/$(ls "$OUT/pkg" | head -1)/distribution"
  mkdir -p "$dist/extensions"
  sed "s|@DISTRIBUTION@|$DESKDROID_FIREFOX_DIR/distribution|g" "$HERE/etherium/policies.json" > "$dist/policies.json"
  curl -sSfL --retry 4 -o "$dist/extensions/uBlock0@raymondhill.net.xpi" "$UBLOCK_URL"
  unzip -l "$dist/extensions/uBlock0@raymondhill.net.xpi" | grep -q "manifest.json"
  name="$(basename "$pkg")"
  (cd "$OUT/pkg" && tar cJf "$OUT/${name%%.tar.*}.tar.xz" *)
  rm -rf "$OUT/pkg"
else
  cp "$pkg" "$OUT/"
fi
ls -la "$OUT"

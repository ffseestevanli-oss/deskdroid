#!/usr/bin/env bash
# Builds Floorp's runtime (Firefox, from Floorp-Projects/Floorp-Runtime) for
# the native desktop: desktop Firefox on GTK 3/Wayland, for Android's libc,
# against the GTK stack native/plasma/build-deps.sh builds.
#
#   native/floorp/build.sh <deps prefix> <ndk dir> <source dir> <out dir>
#
# Leaves the packaged browser (a tarball) in <out dir>. Logs go there too.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
PREFIX="$(cd "$1" && pwd)"; NDK="$2"; SRC="$(cd "$3" && pwd)"; OUT="$(mkdir -p "$4" && cd "$4" && pwd)"

python3 "$HERE/port.py" "$SRC"

LIBCLANG="$(dirname "$(ls /usr/lib/llvm-*/lib/libclang.so* | sort -V | tail -1)")"
sed -e "s|@NDK@|$NDK|g" -e "s|@PREFIX@|$PREFIX|g" -e "s|@LIBCLANG@|$LIBCLANG|g" "$HERE/mozconfig" > "$SRC/mozconfig"
cat "$SRC/mozconfig"

cd "$SRC"
export MOZBUILD_STATE_PATH="$HOME/.mozbuild" MACH_BUILD_PYTHON_NATIVE_PACKAGE_SOURCE=pip
set +e
./mach --no-interactive configure > "$OUT/configure.log" 2>&1
rc=$?
set -e
tail -60 "$OUT/configure.log"
[ $rc -eq 0 ] || { echo "== configure FAILED"; exit 1; }

set +e
./mach --no-interactive build --keep-going > "$OUT/build.log" 2>&1
rc=$?
set -e
if [ $rc -ne 0 ]; then
  echo "-- distinct errors:"
  grep -E "(error|Error)(\[E[0-9]+\])?:" "$OUT/build.log" | sed 's|^.*/obj-deskdroid/||; s|^.*'"$SRC"'/||' | sort -u | head -150 || true
  echo "-- last lines:"
  tail -60 "$OUT/build.log"
  echo "== build FAILED"
  exit 1
fi
./mach package > "$OUT/package.log" 2>&1 || { tail -60 "$OUT/package.log"; exit 1; }
cp obj-deskdroid/dist/*.tar.* "$OUT/"
ls -la "$OUT"

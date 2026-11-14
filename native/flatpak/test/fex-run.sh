#!/bin/bash
# Tests fex-run.sh (libdd_flatpak_fex.so) on a desktop machine: the RootFS of
# links it gives an x86-64 Flatpak app, and how it starts FEX-Emu, with a
# stand-in FEX that prints what it was given. Also the two ways in: `flatpak
# run` (flatpak.sh) for an app installed for x86_64, and adpk-run.sh for a
# store package with an x86_64 runtime.
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
T="$(mktemp -d)"; trap 'pkill -f "$T/" 2>/dev/null || true; rm -rf "$T"' EXIT
fails=0
expect() { # name text regex...
  local name="$1" text="$2"; shift 2
  for re in "$@"; do
    grep -Eq -- "$re" <<<"$text" || { echo "FAIL $name: no /$re/ in:"; sed 's/^/     /' <<<"$text"; fails=$((fails+1)); return; }
  done
  echo "ok   $name"
}
F="$T/files" L="$T/libs"
mkdir -p "$F/glibc/lib" "$L" "$F/x86/fex/bin" "$F/x86/rootfs/etc"
cp "$HERE/../fex-run.sh" "$L/libdd_flatpak_fex.so"; chmod +x "$L/libdd_flatpak_fex.so"
: > "$L/libddmask_glibc.so"
echo "deskdroid:x:1000:1000::/home:/bin/bash" > "$F/x86/rootfs/etc/passwd"
echo "nameserver 9.9.9.9" > "$F/x86/rootfs/etc/resolv.conf"
cat > "$F/x86/fex/bin/FEXInterpreter" <<'X'
#!/bin/sh
echo "fex: $*"
echo "FEX_ROOTFS=$FEX_ROOTFS"
echo "LD_LIBRARY_PATH=$LD_LIBRARY_PATH"
echo "PATH=$PATH"
echo "DDMASK_GLIBC_LD_PRELOAD=$DDMASK_GLIBC_LD_PRELOAD"
echo "DDFLATPAK_APP=${DDFLATPAK_APP:-unset}"
X
chmod +x "$F/x86/fex/bin/FEXInterpreter"
# An x86-64 runtime, app and GL extension, as Flatpak installs them.
rt() { # <folder>
  mkdir -p "$1/lib/x86_64-linux-gnu/GL" "$1/bin" "$1/etc" "$1/share"
  echo x86-loader > "$1/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2"
  echo x86-libc > "$1/lib/x86_64-linux-gnu/libc.so.6"
  echo "ID=org.freedesktop.platform" > "$1/etc/os-release"
}
RT="$F/flatpak/runtime/org.freedesktop.Platform/x86_64/24.08/active/files"
GLX="$F/flatpak/runtime/org.freedesktop.Platform.GL.default/x86_64/24.08/active/files"
APPD="$F/flatpak/app/org.example.Tool/x86_64/stable/active"
rt "$RT"; mkdir -p "$GLX/lib" "$APPD/files/bin"; echo x86-mesa > "$GLX/lib/libGL.so.1"
echo app-program > "$APPD/files/bin/tool"
printf '[Application]\nname=org.example.Tool\nruntime=org.freedesktop.Platform/x86_64/24.08\ncommand=tool\n\n[Environment]\nLD_LIBRARY_PATH=/app/lib/tool\n' > "$APPD/metadata"

env_run() {
  env -i HOME="$T/home" PATH=/usr/bin:/bin DESKDROID_FILES="$F" DESKDROID_LIBS="$L" DESKDROID_GLIBC_RUN=" " DESKDROID_SH=/bin/sh "$@"
}
out="$(env_run FEXRUN_ID=org.example.Tool FEXRUN_APP="$APPD/files" FEXRUN_RT="$RT" FEXRUN_GL="$GLX" FEXRUN_LIBPATH=/app/lib/tool \
  DDFLATPAK_APP=/nope sh "$L/libdd_flatpak_fex.so" tool a b 2>&1)"
R="$F/flatpak-tmp/fexroot/org.example.Tool"
expect "starts the command with the runtime's sh, through FEX" "$out" "^fex: /bin/sh -c exec \"\\\$0\" \"\\\$@\" /app/bin/tool a b$"
expect "...with the app's own RootFS" "$out" "^FEX_ROOTFS=$R$"
expect "...the x86 library path, the app's own first and the GL driver last" "$out" \
  "^LD_LIBRARY_PATH=/app/lib/tool:/app/lib:/usr/lib/x86_64-linux-gnu:/usr/lib:/usr/lib/x86_64-linux-gnu/GL/default/lib$"
expect "...the app's PATH, and FEX without ddflatpak" "$out" "^PATH=/app/bin:/usr/bin$" "^DDMASK_GLIBC_LD_PRELOAD=$L/libddmask_glibc.so$" "^DDFLATPAK_APP=unset$"
expect "RootFS: /app, /usr, /etc and the loader reach the right files" \
  "$(cat "$R/app/bin/tool" "$R/usr/lib/x86_64-linux-gnu/libc.so.6" "$R/lib/x86_64-linux-gnu/libc.so.6" "$R/lib64/ld-linux-x86-64.so.2" "$R/etc/os-release")" \
  "^app-program$" "^x86-libc$" "^x86-loader$" "^ID=org.freedesktop.platform$"
expect "...the GL driver at usr/lib/x86_64-linux-gnu/GL/default" "$(cat "$R/usr/lib/x86_64-linux-gnu/GL/default/lib/libGL.so.1")" "^x86-mesa$"
expect "...the x86 system's passwd and DNS in /etc" "$(cat "$R/etc/passwd" "$R/etc/resolv.conf")" "^deskdroid:" "^nameserver 9.9.9.9$"
abs="$(find "$R" -type l -lname '/*' | head -3)"
expect "...with relative links only (FEX re-roots absolute ones)" "abs:[$abs]" '^abs:\[\]$'
mkdir -p "$F/flatpak-tmp/x"; echo t > "$F/flatpak-tmp/x/f"
expect "...and /tmp is a real folder" "$(cat "$R/tmp/x/f")" "^t$"

out="$(env -i HOME="$T/home" PATH=/usr/bin:/bin DESKDROID_FILES="$F" DESKDROID_LIBS="$L" FEXRUN_ID=x FEXRUN_APP=/a FEXRUN_RT=/r \
  DESKDROID_FEX="$T/nofex" sh "$L/libdd_flatpak_fex.so" tool 2>&1 || true)"
expect "without FEX it says where to set it up" "$out" "Steam Installation Assistant"

# flatpak run: an app installed only for x86_64 goes to FEX.
cp "$HERE/../flatpak.sh" "$L/libdd_flatpak.so"
: > "$L/libddflatpak.so"
out="$(env_run sh "$L/libdd_flatpak.so" run org.example.Tool c d 2>&1)"
expect "flatpak run: an x86_64-only app runs through FEX" "$out" "^fex: /bin/sh -c .* /app/bin/tool c d$" "^FEX_ROOTFS=$R$" \
  "^LD_LIBRARY_PATH=/app/lib/tool:/app/lib:.*/GL/default/lib$"

# adpk-run.sh: a store package whose runtime is an x86_64 one.
S="$F/store/apps"
mkdir -p "$S/tool/program/files/bin" "$S/runtime-freedesktop-24.08-x86_64/program/files"
: > "$S/tool/app.txt"; : > "$S/tool/program/.ddsetup-done"
: > "$S/runtime-freedesktop-24.08-x86_64/app.txt"; : > "$S/runtime-freedesktop-24.08-x86_64/program/.ddsetup-done"
rt "$S/runtime-freedesktop-24.08-x86_64/program/files"
printf '[Runtime]\nname=org.freedesktop.Platform\nruntime=org.freedesktop.Platform/x86_64/24.08\n' > "$S/runtime-freedesktop-24.08-x86_64/program/metadata"
printf '[Application]\nname=org.example.Tool\nruntime=org.freedesktop.Platform/x86_64/24.08\ncommand=tool\n' > "$S/tool/program/metadata"
: > "$L/libdd_ld-glibc.so"; : > "$F/glibc/lib/libc.so.6"
out="$(env -i HOME="$T/home" PATH=/usr/bin:/bin XDG_RUNTIME_DIR="$T/run" DDAPP_PROGRAM="$S/tool/program" DESKDROID_FILES="$F" \
  DESKDROID_LIBS="$L" DESKDROID_GLIBC_RUN=" " DESKDROID_SH=/bin/sh DESKDROID_CRASH_DIALOG=0 sh "$HERE/../adpk-run.sh" e 2>&1; cat "$S/tool/run.log")"
expect "a store package with an x86_64 runtime runs through FEX, without ARM64 Mesa" "$out" \
  "^fex: /bin/sh -c .* /app/bin/tool e$" "^FEX_ROOTFS=$F/flatpak-tmp/fexroot/tool$" "starting /app/bin/tool e through FEX-Emu"
rm -rf "$S/runtime-freedesktop-24.08-x86_64" "$F/open-requests"
env -i HOME="$T/home" PATH=/usr/bin:/bin DDAPP_PROGRAM="$S/tool/program" DESKDROID_FILES="$F" DESKDROID_LIBS="$L" \
  DESKDROID_GLIBC_RUN=" " DESKDROID_CRASH_DIALOG=0 sh "$HERE/../adpk-run.sh" >/dev/null 2>&1 || true
expect "...and a missing x86_64 runtime gets its own package name" "$(cat "$F"/open-requests/*.req)" "^deskdroid:software:install:runtime-freedesktop-24.08-x86_64$"

[ "$fails" -eq 0 ] && echo "all fex-run tests passed" || { echo "$fails failed"; exit 1; }

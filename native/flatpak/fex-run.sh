#!/system/bin/sh
# DeskDroid: starts an x86-64 Flatpak app through FEX-Emu. Shipped in the APK
# as libdd_flatpak_fex.so; flatpak.sh (`flatpak run`) and adpk-run.sh (store
# packages) hand an app here when its runtime is an x86_64 one.
#
#   FEXRUN_ID=<app id> FEXRUN_APP=<app files> FEXRUN_RT=<runtime files> \
#   [FEXRUN_GL=<GL extension files>] [FEXRUN_LIBPATH=<extra guest lib dirs>] \
#     libdd_flatpak_fex.so <command in /app/bin> [args]
#
# Flatpak would mount the app at /app and the runtime at /usr inside a
# sandbox. FEX-Emu has its own way to give x86 programs another /: its RootFS
# (FEX_ROOTFS), where it looks for every absolute path first and falls back to
# Android's own. So each app gets a small RootFS of links,
# files/flatpak-tmp/fexroot/<app>:
#
#   app    -> the app's files            usr  -> the runtime's files (a folder
#   etc    -> the runtime's /etc, plus           of links, so the GL driver
#             the x86 system's passwd,           extension can sit at
#             resolv.conf, hosts...              usr/lib/x86_64-linux-gnu/GL/default)
#   lib, bin, sbin -> usr/...            lib64 -> the runtime's x86-64 loader
#   tmp, var/tmp -> files/flatpak-tmp
#
# The links are relative: FEX treats an absolute link inside its RootFS as a
# path inside the RootFS, while a relative one is followed as usual.
#
# FEX itself (an ARM64 glibc program) comes from the Steam Installation
# Assistant's x86 setup (X86.kt: files/x86/fex), and its server gets a socket
# for this app. Tests set DESKDROID_FILES, DESKDROID_LIBS and
# DESKDROID_FEX (a stand-in) as for adpk-run.sh.
# Android's tools for this script (the caller may have set the app's PATH).
export PATH="/system/bin:/usr/bin:/bin:$PATH"
F="${DESKDROID_FILES:-/data/data/io.deskdroid.app/files}"
self="$(readlink -f "$0" 2>/dev/null || echo "$0")"
L="${DESKDROID_LIBS:-${self%/*}}"
ID="${FEXRUN_ID:?FEXRUN_ID is the app id}"
APP="${FEXRUN_APP:?FEXRUN_APP is the app's files}"
RT="${FEXRUN_RT:?FEXRUN_RT is the runtime's files}"
GL="${FEXRUN_GL:-}"
X86="${DESKDROID_X86:-$F/x86}"
FEX="${DESKDROID_FEX:-$X86/fex/bin/FEXInterpreter}"
TRIPLE=x86_64-linux-gnu
[ $# -gt 0 ] || { echo "$ID: which command?" >&2; exit 1; }
cmd="$1"; shift

if [ ! -e "$FEX" ]; then
  echo "$ID is an x86-64 app, and x86-64 apps run through FEX-Emu, which isn't installed yet: open the Steam Installation Assistant and set it up there, then open $ID again" >&2
  exit 1
fi

# A path relative to the folder $2, for a link there to $1 (both under files/).
FR="$(readlink -f "$F")"
rel() {
  t="$(readlink -f "$1" 2>/dev/null || echo "$1")"; from="$(readlink -f "$2")"
  case "$t" in "$FR"/*) ;; *) echo "$t"; return ;; esac
  up=""; d="$from"
  while [ "$d" != "$FR" ] && [ -n "$d" ] && [ "$d" != / ]; do up="../$up"; d="${d%/*}"; done
  echo "$up${t#$FR/}"
}
link() { ln -sfn "$(rel "$1" "${2%/*}")" "$2"; }
# A folder of links to each thing in $1, at $2.
mirror() {
  mkdir -p "$2"
  for e in "$1"/* "$1"/.[!.]*; do
    [ -e "$e" ] || [ -L "$e" ] || continue
    link "$e" "$2/${e##*/}"
  done
}

ROOT="$F/flatpak-tmp/fexroot/$ID"
stamp="$APP|$RT|$GL|2"
if [ "$(cat "$ROOT/.deskdroid-stamp" 2>/dev/null)" != "$stamp" ]; then
  rm -rf "$ROOT"
  mkdir -p "$ROOT/var" "$F/flatpak-tmp"
  link "$APP" "$ROOT/app"
  # usr: the runtime, with usr/lib/x86_64-linux-gnu/GL/default the extension.
  mirror "$RT" "$ROOT/usr"
  if [ -n "$GL" ] && [ -d "$GL" ]; then
    rm -f "$ROOT/usr/lib"; mirror "$RT/lib" "$ROOT/usr/lib"
    rm -f "$ROOT/usr/lib/$TRIPLE"; mirror "$RT/lib/$TRIPLE" "$ROOT/usr/lib/$TRIPLE"
    rm -f "$ROOT/usr/lib/$TRIPLE/GL"; mirror "$RT/lib/$TRIPLE/GL" "$ROOT/usr/lib/$TRIPLE/GL"
    rm -rf "$ROOT/usr/lib/$TRIPLE/GL/default"; link "$GL" "$ROOT/usr/lib/$TRIPLE/GL/default"
  fi
  # etc: the runtime's, with the files Flatpak takes from the host from the
  # x86 system (X86.kt writes them for this phone: user, DNS servers).
  mirror "$RT/etc" "$ROOT/etc"
  for f in passwd group resolv.conf hosts hostname machine-id localtime; do
    [ -e "$X86/rootfs/etc/$f" ] && { rm -f "$ROOT/etc/$f"; link "$X86/rootfs/etc/$f" "$ROOT/etc/$f"; }
  done
  ln -sfn usr/lib "$ROOT/lib"; ln -sfn usr/bin "$ROOT/bin"; ln -sfn usr/bin "$ROOT/sbin"
  # The loader x86-64 programs name (/lib64/ld-linux-x86-64.so.2).
  if [ -d "$RT/lib64" ]; then ln -sfn usr/lib64 "$ROOT/lib64"
  else
    mkdir -p "$ROOT/lib64"
    for ld in "$RT/lib/$TRIPLE/ld-linux-x86-64.so.2" "$RT/lib/ld-linux-x86-64.so.2"; do
      [ -e "$ld" ] && { link "$ld" "$ROOT/lib64/ld-linux-x86-64.so.2"; break; }
    done
  fi
  link "$F/flatpak-tmp" "$ROOT/tmp"; link "$F/flatpak-tmp" "$ROOT/var/tmp"
  echo "$stamp" > "$ROOT/.deskdroid-stamp"
fi

# The x86 program's library path (its loader reads LD_LIBRARY_PATH; DeskDroid's
# ARM64 glibc, which runs FEX, reads DDMASK_GLIBC_LD_* instead).
lp="/app/lib:/usr/lib/$TRIPLE:/usr/lib"
[ -n "$GL" ] && lp="$lp:/usr/lib/$TRIPLE/GL/default/lib"
export LD_LIBRARY_PATH="${FEXRUN_LIBPATH:+$FEXRUN_LIBPATH:}$lp"
# FEX's own process: DeskDroid's glibc and ddmask, without ddflatpak (FEX's
# guest makes its own system calls; FEX maps its paths itself).
export DDMASK_GLIBC_LD_PRELOAD="$L/libddmask_glibc.so"
export DDMASK_GLIBC_LD_LIBRARY_PATH="$F/glibc/lib"
unset DDMASK_GLIBC_LD_AUDIT DDFLATPAK_APP DDFLATPAK_RUNTIME DDFLATPAK_MOUNTS DDFLATPAK_LIBPATH DDFLATPAK_LOADER
# ddmask starts glibc programs, but only in processes it's preloaded into;
# otherwise (and in tests) FEX starts through glibc's loader.
G="${DESKDROID_GLIBC_RUN:-}"
if [ -z "$G" ]; then
  case ":${LD_PRELOAD:-}:" in *libddmask.so*) ;; *) G="$L/libdd_ld-glibc.so" ;; esac
fi
export FEX_ROOTFS="$ROOT" DDMASK_X86_64="$FEX" DDMASK_I386="$FEX"
# FEX's server: one per app (its RootFS), stopping a minute after the app.
RUN="$X86/run"; mkdir -p "$RUN"
export FEX_SERVERSOCKETPATH="$RUN/fex-$ID.sock"
server="$(dirname "$FEX")/FEXServer"
# A socket left by a server that has stopped would only make FEX wait.
[ -S "$FEX_SERVERSOCKETPATH" ] && ! pgrep -f "$server" >/dev/null 2>&1 && rm -f "$FEX_SERVERSOCKETPATH"
if [ -e "$server" ] && [ ! -S "$FEX_SERVERSOCKETPATH" ]; then
  setsid $G "$server" -f -p 60 </dev/null >>"$RUN/fexserver-$ID.log" 2>&1 &
  i=0; while [ $i -lt 20 ] && [ ! -S "$FEX_SERVERSOCKETPATH" ]; do sleep 0.5; i=$((i + 1)); done
fi
echo "$ID: starting /app/bin/$cmd $* through FEX-Emu (x86-64, RootFS $ROOT)" >&2
export PATH=/app/bin:/usr/bin
# The runtime's x86 sh starts the command (a script, zypak, an ELF program).
exec $G "$FEX" /bin/sh -c 'exec "$0" "$@"' "/app/bin/$cmd" "$@"

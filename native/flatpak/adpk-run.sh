#!/system/bin/sh
# DeskDroid: starts an app packaged from Flathub's ARM64 build (an .adpk made
# by tools/flathub-adpk) the way `flatpak run` would, without the flatpak
# command, with the app, its runtime and Mesa in store packages. Shipped in
# the APK as libdd_adpk_run.so: store-program.sh points the package's ddapp
# here (DDAPP_RUN), so a fix to how apps start reaches every installed app
# without rebuilding packages. The package's own program/run.sh is the
# fallback for builds without this file.
#
#   DDAPP_PROGRAM=<store/apps/<app>/program> libdd_adpk_run.so [--dd-command=<program in /app/bin>] [args]
#
# Everything about the app comes from the package's program/metadata
# (Flatpak's: name, command, runtime, [Environment]).
# Only Android's own tools (/system/bin) are used before the app starts:
# PATH changes to the app's at the very end.
#
# Tests on a desktop machine set DESKDROID_FILES, DESKDROID_LIBS and
# DESKDROID_GLIBC_RUN as for flatpak.sh.
TRIPLE=aarch64-linux-gnu
P="${DDAPP_PROGRAM:?DDAPP_PROGRAM is the package's program folder}"
P="${P%/}"
SID="${P%/program}"; SID="${SID##*/}"
meta="$P/metadata"
# [Application] name= and command= (Flatpak's metadata, "key=value").
FPID="$(sed -n '/^\[Application\]/,/^\[/{s/^name *= *//p}' "$meta" | head -n 1)"
CMD="$(sed -n '/^\[Application\]/,/^\[/{s/^command *= *//p}' "$meta" | head -n 1)"
F="${DESKDROID_FILES:-${P%/store/apps/*}}"
S="$F/store/apps"
# Its runtime: the installed package whose metadata names the same
# runtime=<name>/<arch>/<branch> (Software keeps program/ but not app.json),
# else the name it would have (org.kde.Platform/aarch64/6.11 -> runtime-kde-6.11).
want="$(sed -n '/^\[Application\]/,/^\[/{s/^runtime *= *//p}' "$meta" | head -n 1)"
RTPKG=""
for m in "$S"/runtime-*/program/metadata; do
  [ -e "$m" ] || continue
  [ "$(sed -n '/^\[Runtime\]/,/^\[/{s/^runtime *= *//p}' "$m" | head -n 1)" = "$want" ] || continue
  RTPKG="${m%/program/metadata}"; RTPKG="${RTPKG##*/}"; break
done
if [ -z "$RTPKG" ]; then
  n="${want%%/*}"; n="${n%.Platform}"; n="${n##*.}"
  RTPKG="runtime-$(echo "$n" | tr 'A-Z' 'a-z')-${want##*/}"
fi
# Mesa and the codecs: whichever runtime-mesa-* is installed (the newest).
MESAPKG=""
for d in "$S"/runtime-mesa-*; do [ -e "$d/app.txt" ] && MESAPKG="${d##*/}"; done
[ -n "$MESAPKG" ] || MESAPKG=runtime-mesa-25.08
LOG="$S/$SID/run.log"
exec 2>"$LOG"

die() {
  echo "$SID: $*" >&2
  # Something to see on the desktop too, where there's no terminal.
  [ -n "$WAYLAND_DISPLAY" ] && command -v notify-send >/dev/null 2>&1 && notify-send "$SID" "$*"
  exit 1
}

# The APK's library folder: where the app's command links (Store.linkCommand),
# else the folder of ddmask in LD_PRELOAD.
L="${DESKDROID_LIBS:-}"
if [ -z "$L" ]; then
  l="$(readlink -f "$F/kwin/bin/$SID" 2>/dev/null)"
  L="${l%/*}"
fi
if [ ! -e "$L/libdd_ld-glibc.so" ]; then
  for p in $(echo "${LD_PRELOAD:-}" | tr ':' ' '); do
    case "$p" in */libddmask.so) L="${p%/*}" ;; esac
  done
fi
[ -e "$L/libdd_ld-glibc.so" ] || die "this DeskDroid build has no glibc loader (libdd_ld-glibc.so)"
[ -e "$F/glibc/lib/libc.so.6" ] || die "glibc isn't unpacked yet (start the desktop once)"

# The runtime and Mesa are packages of their own.
missing=""
for need in "$RTPKG" "$MESAPKG"; do
  [ -e "$S/$need/app.txt" ] || missing="$missing $need"
done
if [ -n "$missing" ]; then
  # Software installs them (SoftwareBridge.kt's install:<id>, from the
  # catalog) and opens to show it; then the app starts from its menu entry.
  req() { # <request>
    mkdir -p "$F/open-requests" && echo "$1" > "$F/open-requests/.$SID-$$-$2" &&
      mv "$F/open-requests/.$SID-$$-$2" "$F/open-requests/$SID-$$-$2.req"
  }
  i=0
  for need in $missing; do i=$((i+1)); req "deskdroid:software:install:$need" "$i"; done
  if [ -x "$F/kwin/bin/software" ]; then
    "$F/kwin/bin/software" </dev/null >/dev/null 2>&1 &
  else
    req deskdroid:store open
  fi
  die "needs$missing first: Software is installing it, then open $SID again"
fi

# Links, script execute bits and empty folders, once per package (ddapp.c).
setup() {
  [ -e "$1/.ddsetup-done" ] && return 0
  echo "$SID: setting up ${1%/program}" >&2
  DDAPP_SETUP="$1/layout.txt" DDAPP_ROOT="$1" /system/bin/linker64 "$P/bin/ddapp" ||
    die "couldn't lay out ${1%/program}"
  : > "$1/.ddsetup-done"
}
[ -n "${DDAPP_SETUP_CMD:-}" ] && setup() {
  [ -e "$1/.ddsetup-done" ] && return 0
  DDAPP_SETUP="$1/layout.txt" DDAPP_ROOT="$1" $DDAPP_SETUP_CMD || die "couldn't lay out $1"
  : > "$1/.ddsetup-done"
}
setup "$P"
setup "$S/$RTPKG/program"
setup "$S/$MESAPKG/program"

cmd="$CMD"
case "$1" in --dd-command=*) cmd="${1#--dd-command=}"; shift ;; esac

APP="$P/files"
RT="$S/$RTPKG/program/files"
GL="$S/$MESAPKG/program/gl"
CX="$S/$MESAPKG/program/codecs-extra"

G="${DESKDROID_GLIBC_RUN:-}"
# Started without ddmask (not from the desktop), run glibc's loader ourselves.
if [ -z "$G" ]; then
  case ":${LD_PRELOAD:-}:" in
    *libddmask.so*) ;;
    *) G="$L/libdd_ld-glibc.so" ;;
  esac
fi

mkdir -p "$F/flatpak-tmp"
export DDMASK_GLIBC_LD_PRELOAD="$L/libddflatpak.so:$L/libddmask_glibc.so"
export DDFLATPAK_TMP="$F/flatpak-tmp" TMPDIR="$F/flatpak-tmp"
export DDFLATPAK_APP="$APP" DDFLATPAK_RUNTIME="$RT"
mounts="/usr/lib/$TRIPLE/GL/default=$GL;/usr/lib/$TRIPLE/GL=$GL;/usr/lib/$TRIPLE/codecs-extra=$CX;/dev/shm=$F/flatpak-tmp"
# Android hides some of /proc from apps; programs that check them before
# starting (LibreOffice: "/proc not mounted" without /proc/version) see
# stand-ins instead.
fake() { # <path under /proc> <contents>
  [ -r "$1" ] && return 0
  f="$F/flatpak-tmp/proc${1#/proc}"
  mkdir -p "${f%/*}" && printf '%s\n' "$2" > "$f" && mounts="$mounts;$1=$f"
}
fake /proc/version "Linux version $(uname -r) (deskdroid) $(uname -v)"
fake /proc/sys/fs/inotify/max_user_watches 8192
export DDFLATPAK_MOUNTS="$mounts"
# glibc's loader asks ddflatpak's audit library for /app and /usr in RUNPATHs.
[ -e "$L/libddflatpak_audit.so" ] && export DDMASK_GLIBC_LD_AUDIT="$L/libddflatpak_audit.so"
# Folders the app's and runtime's programs name in their RUNPATH (/app/lib/<x>,
# /usr/lib/<x>): glibc's loader opens those itself, unmapped.
rpaths=""
for f in "$P/libdirs.txt" "$S/$RTPKG/program/libdirs.txt"; do
  [ -f "$f" ] || continue
  while IFS= read -r d; do
    case "$d" in APP:*) rpaths="$rpaths:$APP/${d#APP:}" ;; RT:*) rpaths="$rpaths:$RT/${d#RT:}" ;; esac
  done < "$f"
done
# LD_LIBRARY_PATH from the app's [Environment] (Audacity's /app/lib/audacity).
for d in $(sed -n '/^\[Environment\]/,/^\[/{s/^LD_LIBRARY_PATH *= *//p}' "$P/metadata" | tr ':' ' '); do
  case "$d" in /app/*) rpaths="$rpaths:$APP/${d#/app/}" ;; /usr/*) rpaths="$rpaths:$RT/${d#/usr/}" ;; esac
done
export DDMASK_GLIBC_LD_LIBRARY_PATH="$F/glibc/lib:$APP/lib$rpaths:$RT/lib/$TRIPLE:$RT/lib:$GL/lib:$CX/lib"
export DDFLATPAK_LIBPATH="$DDMASK_GLIBC_LD_LIBRARY_PATH"
# The desktop's own (bionic) Qt and KDE settings would point the app's Qt at
# the wrong plugins.
unset QT_PLUGIN_PATH QML2_IMPORT_PATH QML_IMPORT_PATH QT_QPA_PLATFORMTHEME QT_STYLE_OVERRIDE \
  QT_QUICK_CONTROLS_STYLE KDEDIRS QTWEBENGINEPROCESS_PATH LD_LIBRARY_PATH
# What flatpak run sets inside the sandbox; ddflatpak makes these paths real.
# (PATH too, but only at the end: /usr/bin is real only to the app's programs,
# not to this script, which needs Android's mkdir and sed until then.)
export XDG_DATA_DIRS=/app/share:/usr/share:/usr/share/runtime/share
export XDG_CONFIG_DIRS=/app/etc/xdg:/etc/xdg
h="${HOME:-$F}/.var/app/$FPID"
export XDG_DATA_HOME="$h/data" XDG_CONFIG_HOME="$h/config" XDG_CACHE_HOME="$h/cache" XDG_STATE_HOME="$h/.local/state"
mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_STATE_HOME"
export FLATPAK_ID="$FPID" LOCPATH="$RT/lib/locale" LANG="${LANG:-C.UTF-8}"
export GST_PLUGIN_SYSTEM_PATH=/app/lib/gstreamer-1.0:/usr/lib/extensions/gstreamer-1.0:/usr/lib/$TRIPLE/gstreamer-1.0
# [Environment] from the runtime's metadata (QT_PLUGIN_PATH=/app/lib/plugins...),
# then the app's ("KEY = value" or "KEY=value").
for m in "$S/$RTPKG/program/metadata" "$meta"; do
  envs="$(sed -n '/^\[Environment\]/,/^\[/{s/^\([A-Za-z_][A-Za-z0-9_]*\) *= */\1=/p}' "$m")"
  [ -n "$envs" ] || continue
  while IFS= read -r kv; do
    case "${kv%%=*}" in LD_LIBRARY_PATH|LD_PRELOAD|PATH) ;; *) export "$kv" ;; esac
  done <<ENVS
$envs
ENVS
done
# Electron and Chromium apps: Wayland, since there's no X server (Flathub
# builds often ask for X11 only). Newer Electron ignores the hint variable, so
# apps started through zypak (Flathub's Electron base) or shipping
# chrome-sandbox get the flags too; Chromium's own sandbox needs Flatpak's,
# which isn't here.
export ELECTRON_OZONE_PLATFORM_HINT="${ELECTRON_OZONE_PLATFORM_HINT:-wayland}" XDG_SESSION_TYPE=wayland
electron=""
grep -qs zypak "$APP/bin/$cmd" && electron=1
for d in "$APP" "$APP"/*; do [ -e "$d/chrome-sandbox" ] && electron=1; done
[ -n "$electron" ] && set -- --ozone-platform=wayland --enable-features=UseOzonePlatform,WaylandWindowDecorations --no-sandbox "$@"
export PATH=/app/bin:/usr/bin
echo "$SID: starting /app/bin/$cmd $* (${FPID:-?}, ${RTPKG:-no runtime})" >&2
# The runtime's sh starts the command, so ddflatpak handles it like any
# program the app starts (a script, zypak, an ELF program).
exec $G "$RT/bin/sh" -c 'exec "$0" "$@"' "/app/bin/$cmd" "$@"

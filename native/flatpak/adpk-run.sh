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
#
# `flatpak run` (flatpak.sh) starts apps the flatpak command installed this
# way too, so they get everything below (the desktop's look, fonts, GPU, the
# crash dialog): DDAPP_PROGRAM is then the app's active/ folder (files/,
# metadata), and the runtime and extensions are given rather than looked up
# among store packages:
#   DDAPP_ID=<app id> DDAPP_RUNTIME=<runtime files> DDAPP_RUNTIME_META=<its metadata>
#   [DDAPP_GL=<GL driver files>] [DDAPP_CODECS=<codecs-extra files>] DDAPP_STATE=<run.log's folder>
# Only Android's own tools (/system/bin) are used before the app starts:
# PATH changes to the app's at the very end.
#
# Tests on a desktop machine set DESKDROID_FILES, DESKDROID_LIBS and
# DESKDROID_GLIBC_RUN as for flatpak.sh.
# The ddmask module (native/ddmask/module.sh), when it's installed: its copy
# of this script runs instead, and its builds of ddmask's libraries are used
# (ddlib). DDMASK_MODULE is where it would be (NativeDesk.kt); api-1 says it
# fits this APK.
DM="${DDMASK_MODULE:-}"
[ -n "$DM" ] && [ -e "$DM/api-1" ] || DM=""
if [ -n "$DM" ] && [ -e "$DM/scripts/adpk-run.sh" ]; then
  case "$0" in "$DM"/*) ;; *) exec "${DESKDROID_SH:-/system/bin/sh}" "$DM/scripts/adpk-run.sh" "$@" ;; esac
fi
ddlib() { if [ -n "$DM" ] && [ -e "$DM/lib/$1" ]; then echo "$DM/lib/$1"; else echo "$L/$1"; fi; }
TRIPLE=aarch64-linux-gnu
P="${DDAPP_PROGRAM:?DDAPP_PROGRAM is the package's program folder}"
P="${P%/}"
SID="${P%/program}"; SID="${SID##*/}"
[ -n "${DDAPP_ID:-}" ] && SID="$DDAPP_ID"
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
# x86-64 apps (a runtime for x86_64) run through FEX-Emu (fex-run.sh).
ARCH="$(echo "$want" | cut -d/ -f2)"
RTPKG=""
for m in "$S"/runtime-*/program/metadata; do
  [ -e "$m" ] || continue
  [ "$(sed -n '/^\[Runtime\]/,/^\[/{s/^runtime *= *//p}' "$m" | head -n 1)" = "$want" ] || continue
  RTPKG="${m%/program/metadata}"; RTPKG="${RTPKG##*/}"; break
done
if [ -z "$RTPKG" ]; then
  n="${want%%/*}"; n="${n%.Platform}"; n="${n##*.}"
  RTPKG="runtime-$(echo "$n" | tr 'A-Z' 'a-z')-${want##*/}"
  [ "$ARCH" = x86_64 ] && RTPKG="$RTPKG-x86_64"
fi
# Mesa and the codecs: whichever runtime-mesa-* is installed (the newest).
MESAPKG=""
if [ -n "${DDAPP_RUNTIME:-}" ]; then
  RTPKG=""
elif [ "$ARCH" = x86_64 ]; then
  # An x86-64 Mesa package if there is one (runtime-mesa-*-x86_64); the
  # ARM64 one is no use to an x86 program.
  for d in "$S"/runtime-mesa-*x86_64*; do [ -e "$d/app.txt" ] && MESAPKG="${d##*/}"; done
else
  for d in "$S"/runtime-mesa-*; do case "$d" in *x86_64*) continue ;; esac; [ -e "$d/app.txt" ] && MESAPKG="${d##*/}"; done
  [ -n "$MESAPKG" ] || MESAPKG=runtime-mesa-25.08
fi
D="${DDAPP_STATE:-$S/$SID}"
mkdir -p "$D"
LOG="$D/run.log"
exec 2>"$LOG"

# When the app fails: crash.log (this launcher's log, with the end of ddmask's
# journal), and Software's crash dialog ("Uh oh! Something's not right!"),
# which saves it where the person chooses. DESKDROID_CRASH_DIALOG=0: no dialog.
crashed() { # <exit status> <what happened>
  c="$D/crash.log"
  {
    echo "== $SID failed: $2"
    echo "== $(date) · $(uname -sr) $(uname -m)"
    echo
    echo "== run.log"
    cat "$LOG" 2>/dev/null
    j="${DDMASK_JOURNAL:-$F/ddmask.log}"
    [ -s "$j" ] && { echo; echo "== ddmask.log (end)"; tail -n 150 "$j"; }
    [ -s "$F/glibc/sigsys.log" ] && { echo; echo "== system calls Android blocked"; sort "$F/glibc/sigsys.log" | uniq -c | tail -n 40; }
  } > "$c" 2>/dev/null
  [ "${DESKDROID_CRASH_DIALOG:-1}" = 0 ] && return 0
  [ -n "$WAYLAND_DISPLAY" ] || return 0
  name="$(sed -n 's/^Name=//p' "$P/files/share/applications/$FPID.desktop" 2>/dev/null | head -n 1)"
  if [ -x "$F/kwin/bin/software" ] || [ -L "$F/kwin/bin/software" ]; then
    "$F/kwin/bin/software" --crashed "$SID" "${name:-$SID}" "$c" </dev/null >/dev/null 2>&1 &
  elif command -v notify-send >/dev/null 2>&1; then
    notify-send "$SID" "$2"
  fi
}

die() {
  echo "$SID: $*" >&2
  crashed 1 "$*"
  exit 1
}

# The APK's library folder: where the app's command links (Store.linkCommand),
# else the folder of ddmask in LD_PRELOAD.
L="${DESKDROID_LIBS:-${DDMASK_LIBS:-}}"
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
for need in $RTPKG $MESAPKG; do
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
  echo "$SID: needs$missing first: Software is installing it, then open $SID again" >&2
  exit 1
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
if [ -z "${DDAPP_RUNTIME:-}" ]; then
  setup "$P"
  setup "$S/$RTPKG/program"
  [ -n "$MESAPKG" ] && setup "$S/$MESAPKG/program"
fi

cmd="$CMD"
case "$1" in --dd-command=*) cmd="${1#--dd-command=}"; shift ;; esac
# A command is a name in /app/bin or a path (Flathub's VLC: command=/app/bin/vlc).
case "$cmd" in /*) prog="$cmd" ;; *) prog="/app/bin/$cmd" ;; esac

APP="$P/files"
if [ -n "${DDAPP_RUNTIME:-}" ]; then
  RT="$DDAPP_RUNTIME" RTMETA="${DDAPP_RUNTIME_META:-}" GL="${DDAPP_GL:-}" CX="${DDAPP_CODECS:-}"
else
  RT="$S/$RTPKG/program/files" RTMETA="$S/$RTPKG/program/metadata"
  GL="${MESAPKG:+$S/$MESAPKG/program/gl}"
  CX="$S/$MESAPKG/program/codecs-extra"
fi

G="${DESKDROID_GLIBC_RUN:-}"
# Started without ddmask (not from the desktop), run glibc's loader ourselves.
if [ -z "$G" ]; then
  case ":${LD_PRELOAD:-}:" in
    *libddmask.so*) ;;
    *) G="$L/libdd_ld-glibc.so" ;;
  esac
fi

mkdir -p "$F/flatpak-tmp"
export DDMASK_GLIBC_LD_PRELOAD="$(ddlib libddflatpak.so):$(ddlib libddmask_glibc.so)"
export DDFLATPAK_TMP="$F/flatpak-tmp" TMPDIR="$F/flatpak-tmp"
export DDFLATPAK_APP="$APP" DDFLATPAK_RUNTIME="$RT"
mounts="/dev/shm=$F/flatpak-tmp"
[ -n "$GL" ] && mounts="/usr/lib/$TRIPLE/GL/default=$GL;/usr/lib/$TRIPLE/GL=$GL;$mounts"
[ -n "$CX" ] && mounts="/usr/lib/$TRIPLE/codecs-extra=$CX;$mounts"
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
# The runtime's fonts.conf includes the host's font folders from here.
printf '<?xml version="1.0"?>\n<fontconfig>\n  <dir>/system/fonts</dir>\n</fontconfig>\n' > "$F/flatpak-tmp/font-dirs.xml"
mounts="$mounts;/run/host/font-dirs.xml=$F/flatpak-tmp/font-dirs.xml"
# bubblewrap, which apps run to sandbox their helpers (glycin, GNOME's image
# loading), needs user namespaces Android doesn't give apps: bwrap.sh stands
# in for it and runs them unsandboxed. From the module's scripts or the APK.
bw="$L/libdd_bwrap.so"
[ -n "$DM" ] && [ -e "$DM/scripts/bwrap.sh" ] && bw="$DM/scripts/bwrap.sh"
[ -e "$bw" ] && mounts="$mounts;/usr/bin/bwrap=$bw"
# Firefox (and browsers built from it, which keep its application ID): the
# settings DeskDroid gives its own Firefox, Etherium (native/firefox/etherium:
# DD Party's look, no telemetry, Startpage, Wayland scrolling without frame
# callbacks), laid over the browser's folder the way Etherium.kt copies them
# into Etherium's. Folders both have are merged (links to the browser's own
# files plus these); the rest replaces or adds a path. Both the /app path and
# the real one, since Firefox finds its folder from /proc/self/exe.
# DESKDROID_ETHERIUM_SETTINGS=0: the browser as Flathub ships it.
merge() { # <settings folder> <browser's folder> <merged folder to make>
  rm -rf "$3"; mkdir -p "$3"
  for o in "$2"/* "$2"/.[!.]*; do [ -e "$o" ] || [ -L "$o" ] || continue; ln -s "$o" "$3/${o##*/}"; done
  for e in "$1"/*; do
    [ -e "$e" ] || continue
    n="${e##*/}"
    if [ -d "$e" ] && [ -d "$2/$n" ]; then rm -f "$3/$n"; merge "$e" "$2/$n" "$3/$n"
    else rm -rf "$3/$n"; ln -s "$e" "$3/$n"; fi
  done
}
ES="$F/kwin/share/deskdroid/etherium"
if [ -d "$ES" ] && [ "${DESKDROID_ETHERIUM_SETTINGS:-1}" != 0 ]; then
  for ini in "$APP"/lib/*/application.ini; do
    grep -qs '^ID={ec8030f7-c20a-464f-9b0e-13a3a9e97384}' "$ini" || continue
    gre="${ini%/application.ini}" virt="/app${ini#$APP}"; virt="${virt%/application.ini}"
    for e in "$ES"/*; do
      [ -e "$e" ] || continue
      n="${e##*/}" to="$e"
      if [ -d "$e" ] && [ -d "$gre/$n" ]; then
        to="$F/flatpak-tmp/etherium/$SID/$n"
        merge "$e" "$gre/$n" "$to"
      fi
      mounts="$mounts;$virt/$n=$to;$gre/$n=$to"
    done
    echo "$SID: Etherium's settings for ${gre##*/} (DD Party look, privacy)" >&2
  done
fi
export DDFLATPAK_MOUNTS="$mounts"
# glibc's loader asks ddflatpak's audit library for /app and /usr in RUNPATHs.
[ -e "$(ddlib libddflatpak_audit.so)" ] && export DDMASK_GLIBC_LD_AUDIT="$(ddlib libddflatpak_audit.so)"
# Folders the app's and runtime's programs name in their RUNPATH (/app/lib/<x>,
# /usr/lib/<x>): glibc's loader opens those itself, unmapped.
rpaths=""
if [ -n "${DDAPP_RUNTIME:-}" ]; then
  # (No libdirs.txt from the packager: folders under lib/ that hold libraries.)
  has_libs() { for x in "$1"*.so "$1"*.so.*; do [ -e "$x" ] && return 0; done; return 1; }
  for d in "$APP"/lib/*/ "$RT"/lib/"$TRIPLE"/*/; do
    has_libs "$d" && rpaths="$rpaths:${d%/}"
  done
fi
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
# FFmpeg with every codec (Mesa's package's codecs-extra, Flathub's
# org.freedesktop.Platform.codecs-extra) ahead of the runtime's, which leaves
# H.264, HEVC and others out: Flatpak puts it first the same way (ld.so.conf).
export DDMASK_GLIBC_LD_LIBRARY_PATH="$F/glibc/lib:$APP/lib${CX:+:$CX/lib}$rpaths:$RT/lib/$TRIPLE:$RT/lib${GL:+:$GL/lib}"
export DDFLATPAK_LIBPATH="$DDMASK_GLIBC_LD_LIBRARY_PATH"
# The desktop's own (bionic) Qt and KDE settings would point the app's Qt at
# the wrong plugins.
# The desktop's own folders for themes, icons and settings, kept to add after
# the app's (below).
desk_data="${XDG_DATA_DIRS:-}" desk_config="${XDG_CONFIG_DIRS:-}"
unset QT_PLUGIN_PATH QML2_IMPORT_PATH QML_IMPORT_PATH QT_QPA_PLATFORMTHEME QT_STYLE_OVERRIDE \
  QT_QUICK_CONTROLS_STYLE KDEDIRS QTWEBENGINEPROCESS_PATH LD_LIBRARY_PATH
# What flatpak run sets inside the sandbox; ddflatpak makes these paths real.
# (PATH too, but only at the end: /usr/bin is real only to the app's programs,
# not to this script, which needs Android's mkdir and sed until then.)
export XDG_DATA_DIRS=/app/share:/usr/share:/usr/share/runtime/share
export XDG_CONFIG_DIRS=/app/etc/xdg:/etc/xdg
# The home folder like an app installed on Linux, not Flatpak's
# ~/.var/app/<id>: the desktop's settings folder (XDG_CONFIG_HOME, kept), so
# apps follow its colours, icons, fonts and GTK theme (DD Party), its user
# folders (user-dirs.dirs: Documents, Downloads... on the phone's storage),
# Dolphin's places and recent files; ~/.local/share and ~/.cache for the rest.
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-${HOME:-$F}/.config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-${HOME:-$F}/.local/share}" XDG_CACHE_HOME="${XDG_CACHE_HOME:-${HOME:-$F}/.cache}" \
  XDG_STATE_HOME="${XDG_STATE_HOME:-${HOME:-$F}/.local/state}"
mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_STATE_HOME"
# KDE's look (kdeglobals: Breeze style, DD Party colours and icons) through
# the runtime's Plasma integration.
export QT_QPA_PLATFORMTHEME=kde
# GTK's look: on Wayland GTK takes its theme from GSettings, not the
# desktop's gtk-3.0/settings.ini (which NativeDesk writes: DD-Party, its icons,
# dark). So the settings file's choices go to GTK_THEME and to GSettings'
# keyfile backend (~/.config/glib-2.0/settings/keyfile), only those keys.
ini="$XDG_CONFIG_HOME/gtk-3.0/settings.ini"
if [ -f "$ini" ]; then
  gval() { sed -n "s/^$1 *= *//p" "$ini" | head -n 1; }
  gtheme="$(gval gtk-theme-name)" gicons="$(gval gtk-icon-theme-name)" gcursor="$(gval gtk-cursor-theme-name)"
  gdark="$(gval gtk-application-prefer-dark-theme)"
  [ -n "$gtheme" ] && export GTK_THEME="$gtheme"
  kf="$XDG_CONFIG_HOME/glib-2.0/settings/keyfile"
  mkdir -p "${kf%/*}" && touch "$kf"
  sed -i -e '/^gtk-theme=/d' -e '/^icon-theme=/d' -e '/^cursor-theme=/d' -e '/^color-scheme=/d' "$kf"
  grep -q '^\[org/gnome/desktop/interface\]' "$kf" || printf '\n[org/gnome/desktop/interface]\n' >> "$kf"
  scheme=default; [ "$gdark" = true ] && scheme=prefer-dark
  keys="$F/flatpak-tmp/gtk-keys"
  {
    echo "color-scheme='$scheme'"
    [ -n "$gtheme" ] && echo "gtk-theme='$gtheme'"
    [ -n "$gicons" ] && echo "icon-theme='$gicons'"
    [ -n "$gcursor" ] && echo "cursor-theme='$gcursor'"
  } > "$keys"
  sed -i "/^\[org\/gnome\/desktop\/interface\]/r $keys" "$kf"
  export GSETTINGS_BACKEND=keyfile
fi
# Fonts: the runtime's, and Android's (Roboto, which the desktop's settings name).
mkdir -p "$F/flatpak-tmp/fontconfig"
cat > "$F/flatpak-tmp/fonts.conf" <<FONTS
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
<fontconfig>
  <include ignore_missing="yes">/etc/fonts/fonts.conf</include>
  <dir>/system/fonts</dir>
  <dir>${HOME:-$F}/.local/share/fonts</dir>
  <cachedir>$F/flatpak-tmp/fontconfig</cachedir>
</fontconfig>
FONTS
export FONTCONFIG_FILE="$F/flatpak-tmp/fonts.conf"
export FLATPAK_ID="$FPID" LOCPATH="$RT/lib/locale" LANG="${LANG:-C.UTF-8}"
export GST_PLUGIN_SYSTEM_PATH=/app/lib/gstreamer-1.0:/usr/lib/extensions/gstreamer-1.0:/usr/lib/$TRIPLE/gstreamer-1.0
# [Environment] from the runtime's metadata (QT_PLUGIN_PATH=/app/lib/plugins...),
# then the app's ("KEY = value" or "KEY=value").
for m in "$RTMETA" "$meta"; do
  [ -f "$m" ] || continue
  envs="$(sed -n '/^\[Environment\]/,/^\[/{s/^\([A-Za-z_][A-Za-z0-9_]*\) *= */\1=/p}' "$m")"
  [ -n "$envs" ] || continue
  while IFS= read -r kv; do
    case "${kv%%=*}" in LD_LIBRARY_PATH|LD_PRELOAD|PATH) ;; *) export "$kv" ;; esac
  done <<ENVS
$envs
ENVS
done
# The GPU: Android's own GLES driver, the one KWin and plasmashell draw with,
# through the virgl server the desktop starts (NativeDesk.kt's startGpu,
# ../virgl): Mesa's virpipe driver (in every Flathub Mesa) sends the app's
# OpenGL there and reads frames back into Wayland shared memory. Without the
# server (Settings' "GPU for Linux apps" off), Mesa's llvmpipe draws.
# (Venus, Vulkan to Android's Vulkan driver, is used instead when a Venus
# server runs.) DESKDROID_GPU=software in the environment: llvmpipe, one app.
R="${XDG_RUNTIME_DIR:-$F/runtime}"
if [ "${DESKDROID_GPU:-}" = software ]; then
  gpu="software (llvmpipe)"
elif [ -S "$R/virgl.sock" ]; then
  export GALLIUM_DRIVER=virpipe LIBGL_ALWAYS_SOFTWARE=1 VTEST_SOCKET_NAME="$R/virgl.sock"
  gpu="GPU (virgl on Android's GLES)"
elif [ -S "$R/venus.sock" ] && [ -e "$L/libdd_vulkan_virtio.so" ]; then
  icd="$F/flatpak-tmp/venus_icd.json"
  printf '{"file_format_version": "1.0.0", "ICD": {"library_path": "%s", "api_version": "1.3.305"}}\n' \
    "$L/libdd_vulkan_virtio.so" > "$icd"
  export VN_DEBUG=vtest VTEST_SOCKET_NAME="$R/venus.sock" VK_DRIVER_FILES="$icd" VK_ICD_FILENAMES="$icd" \
    MESA_VK_WSI_DEBUG=sw MESA_LOADER_DRIVER_OVERRIDE=zink GALLIUM_DRIVER=zink ZINK_DESCRIPTORS=lazy
  gpu="GPU (Venus)"
else
  gpu="software (llvmpipe)"
fi
# Apps that only speak PipeWire (EasyEffects: xdg-run/pipewire-0 in their
# permissions) abort without its socket; say why instead of vanishing.
if grep -q 'xdg-run/pipewire-0' "$meta" 2>/dev/null && [ ! -S "${PIPEWIRE_RUNTIME_DIR:-$R}/pipewire-0" ]; then
  die "needs DeskDroid's PipeWire sound server, which this DeskDroid build doesn't have yet: update DeskDroid, then open it again"
fi
# The desktop's data and settings folders after the app's and runtime's
# (which the [Environment] above may have set): DD Party's colour scheme,
# icons and GTK theme, KDE's defaults from the desktop's Global Theme.
[ -n "$desk_data" ] && export XDG_DATA_DIRS="$XDG_DATA_DIRS:$desk_data"
[ -n "$desk_config" ] && export XDG_CONFIG_DIRS="$XDG_CONFIG_DIRS:$desk_config"
# KDE apps that pick their colours themselves (KColorSchemeManager: Kirigami
# apps like EasyEffects) take Breeze unless KDE's platform theme answers for
# them, or a scheme is named under [UiSettings]: the desktop's current one
# (kdeglobals' ColorScheme), as a default below everything the person saves
# (an app's own choice in its rc file still wins). Written at every start, so
# it follows System Settings.
look="$F/flatpak-tmp/kde-look"
cs=""
for g in "$XDG_CONFIG_HOME/kdeglobals" $(echo "$desk_config" | tr ':' ' ' | sed 's|$|/kdeglobals|'); do
  [ -f "$g" ] || continue
  cs="$(sed -n 's/^ColorScheme=//p' "$g" | tail -n 1)"
  [ -n "$cs" ] && break
done
if [ -n "$cs" ]; then
  mkdir -p "$look" && printf '[UiSettings]\nColorScheme=%s\n' "$cs" > "$look/kdeglobals"
  export XDG_CONFIG_DIRS="$XDG_CONFIG_DIRS:$look"
fi
# A KDE desktop, as far as Qt and KDE's libraries ask (the platform theme,
# KIconTheme, KStyle), and Qt says in run.log which platform theme it took.
export XDG_CURRENT_DESKTOP="${XDG_CURRENT_DESKTOP:-KDE}"
export QT_LOGGING_RULES="${QT_LOGGING_RULES:+$QT_LOGGING_RULES;}qt.qpa.theme=true"
# Electron and Chromium apps: Wayland, since there's no X server (Flathub
# builds often ask for X11 only). Newer Electron ignores the hint variable, so
# apps started through zypak (Flathub's Electron base) or shipping
# chrome-sandbox get the flags too; Chromium's own sandbox needs Flatpak's,
# which isn't here.
export ELECTRON_OZONE_PLATFORM_HINT="${ELECTRON_OZONE_PLATFORM_HINT:-wayland}" XDG_SESSION_TYPE=wayland
electron=""
grep -qs zypak "$APP/bin/${prog#/app/bin/}" && electron=1
for d in "$APP" "$APP"/*; do [ -e "$d/chrome-sandbox" ] && electron=1; done
[ -n "$electron" ] && set -- --ozone-platform=wayland --enable-features=UseOzonePlatform,WaylandWindowDecorations --no-sandbox "$@"
# Apps that only draw through X11 (Flatpak's sockets=x11 without wayland:
# Flathub's VLC, whose Qt interface needs an X server and otherwise falls
# back to its command line and quits): an X server, Xwayland (Debian's, in
# files/flatpak-cli), as one window on the desktop, shared by those apps and
# stopping 10 s after the last one closes. It runs with ddflatpak over the
# flatpak tools' folders, so /tmp and /bin/sh (dash, for xkbcomp, its
# keyboard maps) are where it looks. DESKDROID_X_GEOMETRY:
# its size (WIDTHxHEIGHT, or fullscreen).
# A live process (not a zombie, whose pid stays until it's reaped).
xalive() {
  [ -n "$1" ] && kill -0 "$1" 2>/dev/null || return 1
  st="$(sed 's/.*) //; s/ .*//' "/proc/$1/stat" 2>/dev/null)"
  [ "$st" != Z ] && [ "$st" != X ]
}
start_x() {
  CLI="${DESKDROID_FLATPAK_CLI:-$F/flatpak-cli}"
  XW="${DESKDROID_XWAYLAND:-$CLI/usr/bin/Xwayland}"
  XN="${DESKDROID_X_DISPLAY:-8}"
  XT="$F/flatpak-tmp"
  # Its pid and, once it is listening, its display number (-displayfd).
  XP="$XT/.X$XN-pid" XR="$XT/.X$XN-ready"
  export DISPLAY=":$XN"
  xpid="$( { tr -cd '0-9' < "$XP"; } 2>/dev/null)"
  if [ -s "$XR" ] && xalive "$xpid"; then
    echo "$SID: X11 only: using the X server on :$XN" >&2
    return 0
  fi
  if [ ! -f "$XW" ]; then
    echo "$SID: X11 only, and this DeskDroid build has no X server (Xwayland)" >&2
    return 1
  fi
  rm -f "$XP" "$XR"
  mkdir -p "$XT/.X11-unix" "$XT/xkb"
  geo="${DESKDROID_X_GEOMETRY:-1280x800}"
  if [ "$geo" = fullscreen ]; then size="-fullscreen"; else size="-geometry $geo"; fi
  decorate=""
  grep -qs -- '-decorate' "$XW" && decorate="-decorate"
  echo "$SID: X11 only: starting an X server (Xwayland :$XN, $geo)" >&2
  ( export DDFLATPAK_RUNTIME="$CLI/usr" DDFLATPAK_APP="$CLI/nothing" DDFLATPAK_TMP="$XT" \
      DDFLATPAK_MOUNTS="/bin/sh=$CLI/usr/bin/dash;/var/lib/xkb=$XT/xkb" \
      DDMASK_GLIBC_LD_LIBRARY_PATH="$F/glibc/lib:$CLI/usr/lib/$TRIPLE:$CLI/usr/lib" \
      DDFLATPAK_LIBPATH="$F/glibc/lib:$CLI/usr/lib/$TRIPLE:$CLI/usr/lib" PATH="/system/bin:$PATH"
    # Drawing on the CPU: no GL for its glamor here (no libEGL in flatpak-cli),
    # and its windows' contents go to the desktop in shared memory (-shm).
    export XWAYLAND_NO_GLAMOR=1
    unset DDFLATPAK_LOADER DDMASK_GLIBC_LD_AUDIT
    # shellcheck disable=SC2086
    setsid $G "$XW" ":$XN" $size $decorate -shm -nolisten tcp -pn -terminate 10 -displayfd 3 \
      </dev/null >>"$D/xwayland.log" 2>&1 3>"$XR" &
    echo $! > "$XP"
  )
  # Ready once it names its display (-displayfd). Android keeps apps out of
  # /proc/net/unix and the /tmp socket fails here (-pn: it carries on with
  # its abstract one, which X clients try first).
  xpid="$( { tr -cd '0-9' < "$XP"; } 2>/dev/null)"
  i=0
  while [ $i -lt 160 ] && [ ! -s "$XR" ] && xalive "$xpid"; do sleep 0.25; i=$((i + 1)); done
  [ -s "$XR" ] && return 0
  if xalive "$xpid"; then
    echo "$SID: the X server isn't ready after 40 s (still running, pid $xpid): $(tail -n 3 "$D/xwayland.log" 2>/dev/null | tr '\n' ' ')" >&2
  else
    echo "$SID: the X server stopped (see xwayland.log): $(tail -n 5 "$D/xwayland.log" 2>/dev/null | tr '\n' ' ')" >&2
  fi
  return 1
}
xsockets="$(sed -n '/^\[Context\]/,/^\[/{s/^sockets *= *//p}' "$meta" | head -n 1)"
case ";$xsockets;" in
  *";x11;"*) case ";$xsockets;" in *";wayland;"*|*";fallback-x11;"*) ;; *) start_x ;; esac ;;
esac
export PATH=/app/bin:/usr/bin
echo "$SID: starting $prog $* (${FPID:-?}, ${RTPKG:-${RT:-no runtime}}, $gpu)" >&2
# The runtime's sh starts the command, so ddflatpak handles it like any
# program the app starts (a script, zypak, an ELF program). Not exec'd: the
# launcher waits, so a failure gets the crash dialog. Closing normally (0) or
# being told to stop (SIGHUP, SIGINT, SIGTERM: 129, 130, 143) isn't a failure.
if [ "$ARCH" = x86_64 ]; then
  guest="$(sed -n '/^\[Environment\]/,/^\[/{s/^LD_LIBRARY_PATH *= *//p}' "$meta" | head -n 1)"
  FEXRUN_ID="$SID" FEXRUN_APP="$APP" FEXRUN_RT="$RT" FEXRUN_GL="$GL" FEXRUN_LIBPATH="$guest" \
    "${DESKDROID_SH:-/system/bin/sh}" "$L/libdd_flatpak_fex.so" "$prog" "$@"
else
  $G "$RT/bin/sh" -c 'exec "$0" "$@"' "$prog" "$@"
fi
st=$?
# Android's tools again (the app's PATH has no sed or mkdir here).
export PATH="/system/bin:$PATH"
case "$st" in
  0|129|130|143) ;;
  *) if [ "$st" -gt 128 ]; then what="it was stopped by signal $((st - 128))$(kill -l "$((st - 128))" 2>/dev/null | sed 's/^/ (SIG/;s/$/)/')"
     else what="it exited with status $st"; fi
     echo "$SID: $what" >&2
     crashed "$st" "$what" ;;
esac
exit "$st"

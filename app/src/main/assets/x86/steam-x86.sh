#!/bin/bash
# The x86 half of deskdroid-steam: runs in DeskDroid's x86 system under
# FEX-Emu, where / is files/x86/rootfs (Ubuntu 24.04 for x86) and paths that
# aren't there (the app's files, $HOME) are Android's.
#   steam-x86.sh setup        downloads Valve's Steam bootstrap into ~/.local/share/Steam
#   steam-x86.sh run [ARGS]   starts an X server (Xwayland) and Steam in it
#   steam-x86.sh reset        Steam's own --reset: all but the games and userdata
#   steam-x86.sh exec FILE [ARGS]   any x86 Linux program, with an X server
#   steam-x86.sh wine FILE [ARGS]   a Windows program through Proton (or Wine)
#   steam-x86.sh wine-tool winecfg|uninstaller|explorer [PREFIX]
#
# The native desktop has no X server, and Steam's windows are X11: Xwayland
# from the x86 system runs as one window on the desktop ("rootful"), and Steam
# draws inside it. Its size: ~/.config/deskdroid-steam-geometry (WIDTHxHEIGHT,
# or "fullscreen"). Extra Steam arguments: ~/.config/deskdroid-steam-args.
# Extra variables (NAME=value lines, e.g. STEAM_FORCE_CLIENT=ubuntu12_32):
# ~/.config/deskdroid-steam-env.

STEAMDIR=$HOME/.local/share/Steam
DEB_URL=${DESKDROID_STEAM_DEB:-https://repo.steampowered.com/steam/archive/stable/steam_latest.deb}
# Chromium (steamwebhelper) can't use its sandbox here (no user namespaces on
# Android) and has no GPU (x86 Mesa draws on the CPU).
STEAM_ARGS="-no-cef-sandbox -cef-disable-gpu -cef-disable-gpu-compositing"
DISPLAY_NUM=7

say() { echo "steam-x86: $*" >&2; }
die() { say "$*"; exit 1; }

# The desktop's settings are for Android's Qt and KDE; x86 programs get the
# x86 system's.
clean_env() {
  unset QT_PLUGIN_PATH QML_IMPORT_PATH QT_QPA_PLATFORM QT_QPA_PLATFORMTHEME QT_QPA_FONTDIR \
    QT_QUICK_CONTROLS_STYLE QT_QUICK_BACKEND QT_WAYLAND_CLIENT_BUFFER_INTEGRATION QT_LOGGING_RULES \
    QT_DISABLE_SHADER_DISK_CACHE QML_XHR_ALLOW_FILE_READ FONTCONFIG_FILE XKB_CONFIG_ROOT XCURSOR_PATH \
    GDK_BACKEND GSETTINGS_BACKEND KDE_DEBUG LD_LIBRARY_PATH LD_PRELOAD \
    VK_ICD_FILENAMES VN_DEBUG MESA_LOADER_DRIVER_OVERRIDE
  export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
  export XDG_DATA_DIRS=/usr/local/share:/usr/share XDG_CONFIG_DIRS=/etc/xdg SHELL=/bin/bash
  export USER=deskdroid LOGNAME=deskdroid
  export TMPDIR=/tmp
  # Software OpenGL (llvmpipe): Android's GPU drivers aren't x86 ones.
  export LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe
}

setup() {
  local tmp
  tmp=$(mktemp -d) || die "no temporary folder"
  say "downloading Valve's Steam bootstrap"
  curl -fL --retry 3 --connect-timeout 30 --speed-limit 1024 --speed-time 120 -o "$tmp/steam.deb" "$DEB_URL" || { rm -rf "$tmp"; die "couldn't download Steam (offline?)"; }
  dpkg-deb -x "$tmp/steam.deb" "$tmp/deb" || { rm -rf "$tmp"; die "the Steam download is damaged, try again"; }
  local boot
  boot=$(ls "$tmp"/deb/usr/lib/steam/bootstraplinux_ubuntu12_32.tar.xz 2>/dev/null | head -n 1)
  [ -f "$boot" ] || { rm -rf "$tmp"; die "no bootstrap in Valve's package"; }
  mkdir -p "$STEAMDIR"
  tar -xJf "$boot" -C "$STEAMDIR" || { rm -rf "$tmp"; die "couldn't unpack Steam"; }
  cp "$boot" "$STEAMDIR/bootstrap.tar.xz"
  rm -rf "$tmp"
  [ -f "$STEAMDIR/steam.sh" ] || die "no steam.sh in Valve's bootstrap"
  chmod +x "$STEAMDIR/steam.sh"
  say "Steam bootstrap installed in $STEAMDIR"
}

# Xwayland as one window on the desktop, unless it's already up.
start_x() {
  export DISPLAY=:$DISPLAY_NUM
  if [ -S /tmp/.X11-unix/X$DISPLAY_NUM ] && xdpyinfo >/dev/null 2>&1; then
    return 0
  fi
  rm -f /tmp/.X11-unix/X$DISPLAY_NUM /tmp/.X$DISPLAY_NUM-lock
  mkdir -p /tmp/.X11-unix
  [ -n "${WAYLAND_DISPLAY:-}" ] || export WAYLAND_DISPLAY=wayland-0
  local geometry="1280x800" size
  [ -f "$HOME/.config/deskdroid-steam-geometry" ] && geometry=$(head -n 1 "$HOME/.config/deskdroid-steam-geometry")
  if [ "$geometry" = fullscreen ]; then size="-fullscreen"; else size="-geometry $geometry"; fi
  local decorate=""
  Xwayland -help 2>&1 | grep -q -- '-decorate' && decorate="-decorate"
  say "starting Xwayland :$DISPLAY_NUM ($geometry)"
  # shellcheck disable=SC2086
  Xwayland :$DISPLAY_NUM $size $decorate -nolisten tcp &
  XPID=$!
  local i
  for i in $(seq 1 60); do
    [ -S /tmp/.X11-unix/X$DISPLAY_NUM ] && xdpyinfo >/dev/null 2>&1 && return 0
    kill -0 $XPID 2>/dev/null || die "Xwayland exited (see above)"
    sleep 0.5
  done
  die "Xwayland didn't start in 30 seconds"
}

run() {
  [ -f "$STEAMDIR/steam.sh" ] || die "Steam isn't set up (run deskdroid-steam in Konsole)"
  local extra=""
  [ -f "$HOME/.config/deskdroid-steam-args" ] && extra=$(head -n 1 "$HOME/.config/deskdroid-steam-args")
  XPID=""
  start_x
  # Steam's windows go to Xwayland, not straight to the desktop's Wayland.
  unset WAYLAND_DISPLAY
  export SDL_VIDEODRIVER=x11 SDL_VIDEO_DRIVER=x11
  export STEAMSCRIPT="$STEAMDIR/steam.sh"
  if [ -f "$HOME/.config/deskdroid-steam-env" ]; then
    set -a
    # shellcheck disable=SC1091
    . "$HOME/.config/deskdroid-steam-env"
    set +a
  fi
  cd "$STEAMDIR" || die "no $STEAMDIR"
  say "starting Steam: steam.sh $STEAM_ARGS $extra $*"
  # shellcheck disable=SC2086
  "$STEAMDIR/steam.sh" $STEAM_ARGS $extra "$@"
  local status=$?
  say "Steam exited ($status)"
  [ -n "$XPID" ] && kill "$XPID" 2>/dev/null
  return $status
}

# Steam's own --reset (steam.sh): everything in STEAMDIR but the games, the
# players' data and the bootstrap goes, then the bootstrap is unpacked again.
reset() {
  [ -f "$STEAMDIR/bootstrap.tar.xz" ] || die "no bootstrap.tar.xz in $STEAMDIR (uninstall and set up Steam again)"
  local f
  for f in "$STEAMDIR"/* "$STEAMDIR"/.[!.]*; do
    [ -e "$f" ] || [ -L "$f" ] || continue
    case "${f##*/}" in steamapps | userdata | bootstrap.tar.xz) ;; *) rm -rf "$f" ;; esac
  done
  tar -xJf "$STEAMDIR/bootstrap.tar.xz" -C "$STEAMDIR" || die "couldn't unpack Steam's bootstrap"
  chmod +x "$STEAMDIR/steam.sh"
  say "Steam reset: it downloads its client again the next time it starts (games kept)"
}

# An x86 program: X11 ones get the Xwayland window, Wayland ones the desktop.
exec_x86() {
  [ -n "${1:-}" ] || die "usage: steam-x86.sh exec FILE [ARGS]"
  local wl=${WAYLAND_DISPLAY:-wayland-0}
  XPID=""
  start_x
  export WAYLAND_DISPLAY=$wl
  cd "$(dirname "$1")" 2>/dev/null || cd "$HOME"
  say "starting $*"
  "$@"
  local status=$?
  say "$1 exited ($status)"
  [ -n "$XPID" ] && kill "$XPID" 2>/dev/null
  return $status
}

# The newest Proton Steam has installed (Library > Tools), or the x86
# system's Wine if someone added one.
find_proton() {
  local p best=""
  for p in "$STEAMDIR"/steamapps/common/Proton*/proton; do
    [ -f "$p" ] && best=$p
  done
  [ -f "$STEAMDIR/steamapps/common/Proton - Experimental/proton" ] && best="$STEAMDIR/steamapps/common/Proton - Experimental/proton"
  echo "$best"
}

# Windows programs share one prefix of DeskDroid's own (~/.local/share/
# deskdroid-wine/default) unless another one is named; Steam's games keep
# theirs in steamapps/compatdata.
wine_run() { # <prefix> <program> [args]
  local prefix=$1; shift
  local proton
  proton=$(find_proton)
  mkdir -p "$prefix"
  if [ -n "$proton" ]; then
    export STEAM_COMPAT_DATA_PATH=$prefix STEAM_COMPAT_CLIENT_INSTALL_PATH=$STEAMDIR
    say "Proton: $proton, prefix $prefix"
    python3 "$proton" run "$@"
  elif command -v wine >/dev/null; then
    export WINEPREFIX=$prefix/pfx
    say "Wine: $(command -v wine), prefix $WINEPREFIX"
    wine "$@"
  else
    die "no Proton yet: in Steam, install Proton (Library > Tools > Proton), then try again"
  fi
}

wine_prefix() { # [prefix]: a prefix folder (the one with pfx/ in it)
  if [ -n "${1:-}" ]; then echo "$1"; else echo "$HOME/.local/share/deskdroid-wine/default"; fi
}

wine_main() {
  [ -n "${1:-}" ] || die "usage: steam-x86.sh wine FILE [ARGS]"
  local wl=${WAYLAND_DISPLAY:-wayland-0}
  XPID=""
  start_x
  export WAYLAND_DISPLAY=$wl
  cd "$(dirname "$1")" 2>/dev/null || cd "$HOME"
  wine_run "$(wine_prefix)" "$@"
  local status=$?
  [ -n "$XPID" ] && kill "$XPID" 2>/dev/null
  return $status
}

wine_tool() {
  case "${1:-}" in winecfg | uninstaller | explorer) ;; *) die "usage: steam-x86.sh wine-tool winecfg|uninstaller|explorer [PREFIX]" ;; esac
  local tool=$1 wl=${WAYLAND_DISPLAY:-wayland-0}
  XPID=""
  start_x
  export WAYLAND_DISPLAY=$wl
  cd "$HOME"
  wine_run "$(wine_prefix "${2:-}")" "$tool"
  local status=$?
  [ -n "$XPID" ] && kill "$XPID" 2>/dev/null
  return $status
}

clean_env
case "${1:-}" in
  setup) setup ;;
  run) shift; run "$@" ;;
  reset) reset ;;
  exec) shift; exec_x86 "$@" ;;
  wine) shift; wine_main "$@" ;;
  wine-tool) shift; wine_tool "$@" ;;
  *) die "usage: steam-x86.sh setup | run [ARGS] | reset | exec FILE | wine FILE | wine-tool TOOL" ;;
esac

#!/bin/bash
# The x86 half of deskdroid-steam: runs in DeskDroid's x86 system under
# FEX-Emu, where / is files/x86/rootfs (Ubuntu 24.04 for x86) and paths that
# aren't there (the app's files, $HOME) are Android's.
#   steam-x86.sh setup        downloads Valve's Steam bootstrap into ~/.local/share/Steam
#   steam-x86.sh run [ARGS]   starts an X server (Xwayland) and Steam in it
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
  # FEX's x86 system is read-only for new folders: mkdir and most other
  # changes go to Android's own paths, and Android has no /tmp. Temporary
  # files go to a folder in the app's files instead.
  export TMPDIR="$HOME/.cache/deskdroid-x86-tmp"
  mkdir -p "$TMPDIR"
  # Software OpenGL (llvmpipe): Android's GPU drivers aren't x86 ones.
  export LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe
}

setup() {
  local tmp
  tmp=$(mktemp -d) || die "no temporary folder"
  say "downloading Valve's Steam bootstrap"
  curl -fL --retry 3 -o "$tmp/steam.deb" "$DEB_URL" || { rm -rf "$tmp"; die "couldn't download Steam (offline?)"; }
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
  # No /tmp/.X11-unix here (see clean_env): Xwayland listens on its abstract
  # socket, which X clients try first, and keeps no lock file.
  if xdpyinfo >/dev/null 2>&1; then
    return 0
  fi
  [ -n "${WAYLAND_DISPLAY:-}" ] || export WAYLAND_DISPLAY=wayland-0
  local geometry="1280x800" size
  [ -f "$HOME/.config/deskdroid-steam-geometry" ] && geometry=$(head -n 1 "$HOME/.config/deskdroid-steam-geometry")
  if [ "$geometry" = fullscreen ]; then size="-fullscreen"; else size="-geometry $geometry"; fi
  local decorate=""
  Xwayland -help 2>&1 | grep -q -- '-decorate' && decorate="-decorate"
  say "starting Xwayland :$DISPLAY_NUM ($geometry)"
  # shellcheck disable=SC2086
  Xwayland :$DISPLAY_NUM $size $decorate -nolisten tcp -nolock &
  XPID=$!
  local i
  for i in $(seq 1 60); do
    xdpyinfo >/dev/null 2>&1 && return 0
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

clean_env
case "${1:-}" in
  setup) setup ;;
  run) shift; run "$@" ;;
  *) die "usage: steam-x86.sh setup | run [ARGS]" ;;
esac

#!/system/bin/sh
# Xwayland, the X server for apps that only draw through X11 (Flathub's VLC):
# flatpak-cli's glibc build, with the paths it needs. KWin starts it for its
# X11 support (rootless: each X11 window is a desktop window; KWIN_XWAYLAND,
# NativeDesk.kt), and adpk-run.sh as a window of its own when KWin can't.
# Arguments go to Xwayland. Shipped in the APK as libdd_xwayland.so.
L="${DESKDROID_LIBS:-${DDMASK_LIBS:-${0%/*}}}"
F="${DESKDROID_FILES:-$HOME}"
DM="${DDMASK_MODULE:-}"
[ -n "$DM" ] && [ -e "$DM/api-1" ] || DM=""
# The ddmask module's copy, when it has one, runs instead.
if [ -n "$DM" ] && [ -e "$DM/scripts/xwayland.sh" ]; then
  case "$0" in "$DM"/*) ;; *) exec /system/bin/sh "$DM/scripts/xwayland.sh" "$@" ;; esac
fi
ddlib() { if [ -n "$DM" ] && [ -e "$DM/lib/$1" ]; then echo "$DM/lib/$1"; else echo "$L/$1"; fi; }
TRIPLE=aarch64-linux-gnu
CLI="${DESKDROID_FLATPAK_CLI:-$F/flatpak-cli}"
XW="${DESKDROID_XWAYLAND:-$CLI/usr/bin/Xwayland}"
XT="$F/flatpak-tmp"
mkdir -p "$XT/xkb" "$XT/.X11-unix" "$XT/ddmask-shm"
# dash, the /bin/sh it runs xkbcomp (its keyboard maps) with: flatpak-cli
# has it as usr/bin/sh (the APK keeps one name per file).
XSH="$CLI/usr/bin/sh"
[ -f "$CLI/usr/bin/dash" ] && XSH="$CLI/usr/bin/dash"
export DDMASK_GLIBC_LD_PRELOAD="$(ddlib libddflatpak.so):$(ddlib libddmask_glibc.so)"
export DDFLATPAK_RUNTIME="$CLI/usr" DDFLATPAK_APP="$CLI/nothing" DDFLATPAK_TMP="$XT" TMPDIR="$XT" \
  DDFLATPAK_MOUNTS="/bin/sh=$XSH;/var/lib/xkb=$XT/xkb" \
  DDMASK_GLIBC_LD_LIBRARY_PATH="$F/glibc/lib:$CLI/usr/lib/$TRIPLE:$CLI/usr/lib" \
  DDFLATPAK_LIBPATH="$F/glibc/lib:$CLI/usr/lib/$TRIPLE:$CLI/usr/lib" \
  DDMASK_SHM="$XT/ddmask-shm" PATH="/system/bin:$PATH"
# Drawing on the CPU: no GL for its glamor here (no libEGL in flatpak-cli).
export XWAYLAND_NO_GLAMOR=1
unset DDFLATPAK_LOADER DDMASK_GLIBC_LD_AUDIT
# shellcheck disable=SC2086
exec ${DESKDROID_GLIBC_RUN:-} "$XW" "$@"

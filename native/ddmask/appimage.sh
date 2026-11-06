#!/system/bin/sh
# ddmask's AppImage runner, installed as libdd_appimage.so in the APK's library
# folder (ddmask.c starts AppImages through it):
#
#   libdd_appimage.so <appimage> <argv[0]> [args...]
#
# An AppImage mounts itself with FUSE, which Android apps can't use. This
# unpacks it instead (its own --appimage-extract, which needs no FUSE) into a
# cache folder, once per AppImage file, and starts its AppRun with the
# variables an AppImage's programs expect. ddmask starts the AppImage and its
# AppRun like any other program: DDMASK_APPIMAGE_RAW=1 tells it to run the
# AppImage itself rather than come back here.
#
# DDMASK_APPIMAGE_CACHE: where AppImages are unpacked (default
# $XDG_CACHE_HOME/ddmask-appimage, or ~/.cache/ddmask-appimage).
[ $# -ge 2 ] || { echo "usage: libdd_appimage.so <appimage> <argv[0]> [args...]" >&2; exit 127; }
ai="$1"
a0="$2"
shift 2
case "$ai" in /*) ;; *) ai="$PWD/$ai" ;; esac
cache="${DDMASK_APPIMAGE_CACHE:-${XDG_CACHE_HOME:-${HOME:-${TMPDIR:-/data/local/tmp}}/.cache}/ddmask-appimage}"
name="${ai##*/}"
# The same file (size, time, inode) unpacks once; a new version replaces the old.
id="$(stat -c '%s-%Y-%i' "$ai")" || exit 127
dir="$cache/$name-$id"
if [ ! -e "$dir/AppRun" ]; then
  tmp="$cache/.unpack-$$"
  rm -rf "$tmp" && mkdir -p "$tmp" || exit 127
  if ! (cd "$tmp" && DDMASK_APPIMAGE_RAW=1 "$ai" --appimage-extract > /dev/null) || [ ! -e "$tmp/squashfs-root/AppRun" ]; then
    echo "ddmask: couldn't unpack $ai" >&2
    rm -rf "$tmp"
    exit 127
  fi
  for old in "$cache/$name"-*; do [ "$old" != "$dir" ] && rm -rf "$old"; done
  mv "$tmp/squashfs-root" "$dir" 2> /dev/null || [ -e "$dir/AppRun" ] || exit 127
  rm -rf "$tmp"
fi
export APPIMAGE="$ai" APPDIR="$dir" ARGV0="$a0" OWD="$PWD"
exec "$dir/AppRun" "$@"

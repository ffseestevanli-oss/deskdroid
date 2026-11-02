#!/system/bin/sh
# DeskDroid: starts Firefox (native/firefox). Shipped as libdd_firefox-run.so;
# bin/firefox is a link to it. Firefox's files are in <data>/firefox, its
# programs and libraries links there to the APK's library folder, the only
# place Android runs programs from. Firefox finds its files next to its
# program, which it would otherwise take from /proc/self/exe (the library
# folder): DESKDROID_FIREFOX_BINARY tells it where that is (deskdroid.py).
self="$(readlink -f "$0")"
libs="${self%/*}"
bin="${0%/*}"
data="${bin%/bin}"
ff="$data/firefox"
program="$(cat "$ff/program.txt" 2>/dev/null)"
[ -n "$program" ] && [ -e "$ff/$program" ] || { echo "firefox: not in this build" >&2; exit 1; }
# Termux's patches put Unix's fixed folders (/tmp...) under this prefix.
mkdir -p /data/data/io.deskdroid.app/files/usr/tmp
export DESKDROID_FIREFOX_BINARY="$ff/$program"
export LD_LIBRARY_PATH="$libs${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export MOZ_ENABLE_WAYLAND=1 GDK_BACKEND=wayland
exec "$ff/$program" "$@"

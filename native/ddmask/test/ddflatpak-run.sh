#!/bin/sh
# ddflatpak-run <app-id>: starts an installed (flatpak --user) app without bubblewrap.
# Desktop-Linux test launcher for ddflatpak.c (see docs/flatpak-checklist.md):
#   DDFLATPAK_PRELOAD=/path/libddflatpak.so ddflatpak-run.sh org.kde.kcalc
set -e
ID="$1"; shift
FP="$HOME/.local/share/flatpak"
APP=$(readlink -f "$FP/app/$ID/current/active/files")
RTREF=$(sed -n 's/^runtime=//p' "$FP/app/$ID/current/active/metadata")
RT=$(readlink -f "$FP/runtime/$RTREF/active/files")
CMD=$(sed -n 's/^command=//p' "$FP/app/$ID/current/active/metadata")
ARCH=$(echo "$RTREF" | cut -d/ -f2)
case "$ARCH" in x86_64) LDSO=ld-linux-x86-64.so.2 TRIPLE=x86_64-linux-gnu;; aarch64) LDSO=ld-linux-aarch64.so.1 TRIPLE=aarch64-linux-gnu;; esac
export DDFLATPAK_APP="$APP" DDFLATPAK_RUNTIME="$RT"
export DDFLATPAK_LOADER="$RT/lib/$TRIPLE/$LDSO"
export DDFLATPAK_LIBPATH="$APP/lib:$RT/lib/$TRIPLE:$RT/lib"
# What flatpak run sets inside the sandbox; the preload makes these paths real.
export PATH=/app/bin:/usr/bin
export XDG_DATA_DIRS=/app/share:/usr/share:/usr/share/runtime/share:/run/host/share
export XDG_CONFIG_DIRS=/app/etc/xdg:/etc/xdg
export XDG_DATA_HOME="$HOME/.var/app/$ID/data" XDG_CONFIG_HOME="$HOME/.var/app/$ID/config" XDG_CACHE_HOME="$HOME/.var/app/$ID/cache"
export LOCPATH="$RT/lib/locale" FLATPAK_ID="$ID" GST_PLUGIN_SYSTEM_PATH=/app/lib/gstreamer-1.0:/usr/lib/extensions/gstreamer-1.0:/usr/lib/$TRIPLE/gstreamer-1.0
mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"
export LD_PRELOAD="${DDFLATPAK_PRELOAD:?}"
exec "$DDFLATPAK_LOADER" --library-path "$DDFLATPAK_LIBPATH" --argv0 "$CMD" "$APP/bin/$CMD" "$@"

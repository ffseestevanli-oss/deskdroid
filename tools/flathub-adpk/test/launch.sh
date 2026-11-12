#!/bin/sh
# launch.sh <store id> [args]: what store-program.sh does on the phone, with
# qemu standing in for ddmask and Android's linker.
F=/data/data/io.deskdroid.app/files L=/data/app/io.deskdroid.app/lib/arm64
id="$1"; shift
P="$F/store/apps/$id/program"
export HOME="$F" DDAPP_RUN="$P/run.sh" DDAPP_PROGRAM="$P"
export DESKDROID_FILES="$F" DESKDROID_LIBS="$L" DESKDROID_GLIBC_RUN="$L/qemu-loader.sh" DDFLATPAK_LOADER="$L/qemu-loader.sh"
export DDAPP_SETUP_CMD=${DDAPP_HOST:?build ddapp.c for this machine and set DDAPP_HOST}
cd "$F/home" && exec /system/bin/sh "$P/run.sh" "$@"

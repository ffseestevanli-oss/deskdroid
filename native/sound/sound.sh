#!/system/bin/sh
# DeskDroid's sound server (README.md): Debian's PulseAudio, unmodified, on
# DeskDroid's glibc. Linux programs (Flathub apps, AppImages, anything with
# libpulse) play into it as on any Linux desktop; it writes 48 kHz stereo
# s16le into a FIFO that the app plays with an AudioTrack (AudioBridge.kt).
#
#   libdd_sound.so [runtime dir]       runs the server (the desktop starts it)
#   libdd_sound.so pactl|pacat [args]  its tools, for the terminal
#
# Paths: $DESKDROID_FILES (default the app's files folder), this script's
# folder (the APK's library folder). Tests on a desktop machine set
# DESKDROID_GLIBC_RUN to their own loader and DESKDROID_SOUND_TRIPLE.
F="${DESKDROID_FILES:-/data/data/io.deskdroid.app/files}"
self="$(readlink -f "$0" 2>/dev/null || echo "$0")"
L="${DESKDROID_LIBS:-${self%/*}}"
S="$F/sound"
TRIPLE="${DESKDROID_SOUND_TRIPLE:-aarch64-linux-gnu}"
G="${DESKDROID_GLIBC_RUN:-$L/libdd_ld-glibc.so}"
M=""
for d in "$S"/usr/lib/pulse-*/modules; do [ -d "$d" ] && M="$d"; done
[ -n "$M" ] && [ -e "$S/usr/bin/pulseaudio" ] || { echo "sound: the sound server isn't unpacked yet (start the desktop once)" >&2; exit 1; }
LP="$F/glibc/lib:$S/usr/lib/$TRIPLE:$S/usr/lib/$TRIPLE/pulseaudio:$M"

case "$1" in
  pactl|pacat|paplay|parec|pacmd)
    tool="$1"; shift
    [ "$tool" = paplay ] && tool=pacat && set -- --playback "$@"
    [ "$tool" = parec ] && tool=pacat && set -- --record "$@"
    exec $G --library-path "$LP" "$S/usr/bin/$tool" "$@" ;;
esac

R="${1:-${XDG_RUNTIME_DIR:?sound: which runtime folder?}}"
P="$R/pulse"
mkdir -p "$P" "$F/sound-state" || exit 1
rm -f "$P/native" "$P/pid"
# One sink, the phone; no microphone yet (a silent source, so programs that
# open one still start); the protocol programs use, on the socket libpulse
# looks for first ($XDG_RUNTIME_DIR/pulse/native).
cat > "$P/deskdroid.pa" <<PA
load-module module-pipe-sink sink_name=phone file=$P/android.pipe format=s16le rate=48000 channels=2 sink_properties=device.description=Phone
set-default-sink phone
load-module module-null-source source_name=nomic description=No-microphone
set-default-source nomic
load-module module-native-protocol-unix auth-anonymous=1 socket=$P/native
load-module module-always-sink
PA
export HOME="${HOME:-$F/home}" XDG_RUNTIME_DIR="$R" PULSE_RUNTIME_PATH="$P" PULSE_STATE_PATH="$F/sound-state"
# No realtime or nice changes (Android refuses them), no shared memory files
# (/dev/shm isn't there; memfd still works), no D-Bus, no idle exit.
exec $G --library-path "$LP" "$S/usr/bin/pulseaudio" -n -F "$P/deskdroid.pa" --daemonize=no \
  --use-pid-file=no --exit-idle-time=-1 --disable-shm=yes --dl-search-path="$M" \
  --log-target=stderr --log-level=notice --system=no --realtime=no --high-priority=no

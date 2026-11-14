#!/system/bin/sh
# DeskDroid's sound server (README.md): Debian's PipeWire and WirePlumber,
# unmodified, on DeskDroid's glibc. Linux programs play into it as on any
# Linux desktop, through PulseAudio's protocol (libpulse: most programs) or
# PipeWire's own (EasyEffects, newer programs); it writes 48 kHz stereo s16le
# into a FIFO that the app plays with an AudioTrack (AudioBridge.kt).
#
#   libdd_sound.so [runtime dir]       runs the server (the desktop starts it)
#   libdd_sound.so pactl|pacat|wpctl|pw-cli|pw-dump|pw-top [args]
#                                      its tools, for the terminal
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
U="$S/usr/lib/$TRIPLE"
[ -e "$S/usr/bin/pipewire" ] || { echo "sound: the sound server isn't unpacked yet (start the desktop once)" >&2; exit 1; }
LP="$F/glibc/lib:$U:$U/pulseaudio:$U/pipewire-0.3:$U/wireplumber-0.5"
export SPA_PLUGIN_DIR="$U/spa-0.2" PIPEWIRE_MODULE_DIR="$U/pipewire-0.3" PIPEWIRE_CONFIG_DIR="$S/usr/share/pipewire"
export WIREPLUMBER_MODULE_DIR="$U/wireplumber-0.5" WIREPLUMBER_DATA_DIR="$S/usr/share/wireplumber"
export PIPEWIRE_LOG_SYSTEMD=false DISABLE_RTKIT=1

# ddmask's glibc side in the server and its tools: Android's filter blocks
# calls Linux daemons make at start, which ddmask answers.
# ddmask's glibc build: the ddmask module's (native/ddmask/module.sh), else the APK's.
dmg="$L/libddmask_glibc.so"
[ -n "${DDMASK_MODULE:-}" ] && [ -e "$DDMASK_MODULE/api-1" ] && [ -e "$DDMASK_MODULE/lib/libddmask_glibc.so" ] && dmg="$DDMASK_MODULE/lib/libddmask_glibc.so"
[ -e "$dmg" ] && export DDMASK_GLIBC_LD_PRELOAD="$dmg${DDMASK_GLIBC_LD_PRELOAD:+:$DDMASK_GLIBC_LD_PRELOAD}"
case "$1" in
  pactl|pacat|paplay|parec|wpctl|pw-cli|pw-dump|pw-top|pw-link|pw-metadata|pw-cat|pw-play|pw-record)
    tool="$1"; shift
    [ "$tool" = paplay ] && tool=pacat && set -- --playback "$@"
    [ "$tool" = parec ] && tool=pacat && set -- --record "$@"
    exec $G --library-path "$LP" "$S/usr/bin/$tool" "$@" ;;
esac

R="${1:-${XDG_RUNTIME_DIR:?sound: which runtime folder?}}"
P="$R/pulse"
mkdir -p "$P" "$F/sound-state" "$P/wireplumber/wireplumber.conf.d" || exit 1
rm -f "$P/native" "$P/pid" "$R/pipewire-0" "$R/pipewire-0.lock" "$R/pipewire-0-manager" "$R/pipewire-0-manager.lock"
export HOME="${HOME:-$F/home}" XDG_RUNTIME_DIR="$R" PIPEWIRE_RUNTIME_DIR="$R" PULSE_RUNTIME_PATH="$P" \
  XDG_STATE_HOME="$F/sound-state" XDG_CONFIG_HOME="$F/sound-state/config"
# Settings people change (EasyEffects' own presets aren't here: they're the app's).
export WIREPLUMBER_CONFIG_DIR="$P/wireplumber:$S/usr/share/wireplumber"

# One server process: PipeWire's graph, the PulseAudio protocol on the socket
# libpulse looks for first ($XDG_RUNTIME_DIR/pulse/native), PipeWire's own on
# $XDG_RUNTIME_DIR/pipewire-0, and one sink, the phone (the pipe tunnel), which
# writes into the FIFO AudioBridge reads. No microphone yet: a silent source,
# so programs that open one still start. WirePlumber (the session manager:
# default sink, linking, moving streams, which EasyEffects relies on) is
# started by the server itself and ends with it.
cat > "$P/deskdroid.conf" <<CONF
context.properties = {
    support.dbus = false
    mem.allow-mlock = false
    mem.warn-mlock = false
    log.level = 2
    core.daemon = true
    core.name = pipewire-0
    default.clock.rate = 48000
    default.clock.allowed-rates = [ 48000 ]
    default.clock.quantum = 1024
    default.clock.min-quantum = 256
    # Asleep the app forces 8192 (SleepMode: clock.force-quantum), ~6 cycles a second.
    default.clock.max-quantum = 8192
    module.x11.bell = false
}
context.spa-libs = {
    audio.convert.* = audioconvert/libspa-audioconvert
    audio.adapt     = audioconvert/libspa-audioconvert
    support.*       = support/libspa-support
}
context.modules = [
    { name = libpipewire-module-protocol-native }
    { name = libpipewire-module-profiler }
    { name = libpipewire-module-access args = { access.socket = { pipewire-0 = "unrestricted" pipewire-0-manager = "unrestricted" } } }
    { name = libpipewire-module-metadata }
    { name = libpipewire-module-spa-node-factory }
    { name = libpipewire-module-client-node }
    { name = libpipewire-module-client-device }
    { name = libpipewire-module-adapter }
    { name = libpipewire-module-link-factory }
    { name = libpipewire-module-session-manager }
    { name = libpipewire-module-pipe-tunnel
      args = { tunnel.mode = sink pipe.filename = "$P/android.pipe"
               audio.format = S16LE audio.rate = 48000 audio.channels = 2 audio.position = [ FL FR ]
               node.name = phone node.description = "Phone" } }
    { name = libpipewire-module-protocol-pulse
      args = { server.address = [ "unix:$P/native" ] pulse.min.quantum = 256/48000 } }
]
context.objects = [
    { factory = spa-node-factory args = { factory.name = support.node.driver node.name = Dummy-Driver
        node.group = pipewire.dummy priority.driver = 20000 } }
    { factory = spa-node-factory args = { factory.name = support.node.driver node.name = Freewheel-Driver
        priority.driver = 19000 node.group = pipewire.freewheel node.freewheel = true } }
    { factory = adapter args = { factory.name = support.null-audio-sink node.name = nomic
        node.description = "No microphone" media.class = Audio/Source/Virtual audio.position = [ FL FR ] } }
]
context.exec = [
    { path = "$G" args = "--library-path $LP $S/usr/bin/wireplumber" }
]
CONF
# WirePlumber: no hardware to look for (Android plays the sound) and no
# D-Bus services (logind, portals, device reservation).
cat > "$P/wireplumber/wireplumber.conf.d/deskdroid.conf" <<CONF
wireplumber.profiles = {
  main = {
    hardware.audio = disabled
    hardware.bluetooth = disabled
    hardware.video-capture = disabled
    monitor.alsa-midi = disabled
    monitor.bluez-midi = disabled
    support.dbus = disabled
    support.reserve-device = disabled
    support.portal-permissionstore = disabled
    support.logind = disabled
  }
}
CONF
# No realtime scheduling (Android refuses it: module-rt isn't loaded), no
# mlock, no D-Bus; memfd for shared memory (/dev/shm isn't there).
exec $G --library-path "$LP" "$S/usr/bin/pipewire" -c "$P/deskdroid.conf"

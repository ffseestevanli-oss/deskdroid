#!/usr/bin/env bash
# Tests the sound server on a desktop Linux machine (x86_64): builds it from
# Debian's amd64 packages, runs sound.sh with this machine's loader standing in
# for DeskDroid's, plays a second of sound with pacat (PulseAudio's protocol,
# what most programs use), and checks it comes out of the FIFO the app reads
# (AudioBridge.kt) unchanged, with WirePlumber managing the graph.
#   native/sound/test.sh
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
T="$(mktemp -d)"
cleanup() { [ -n "${srv:-}" ] && kill "$srv" 2>/dev/null; rm -rf "$T"; }
trap cleanup EXIT
DESKDROID_SOUND_DEBARCH=amd64 "$HERE/build.sh" "$T/apk" >/dev/null
F="$T/files" R="$T/run"
mkdir -p "$F/sound" "$F/home" "$R"
(cd "$F/sound" && unzip -q "$T/apk/libdd_soundsrv.so")
LD="$(readelf -l /bin/sh | sed -n 's/.*interpreter: \(.*\)]/\1/p')"
export DESKDROID_FILES="$F" DESKDROID_GLIBC_RUN="$LD" DESKDROID_SOUND_TRIPLE=x86_64-linux-gnu HOME="$F/home"
mkfifo -m 660 "$R/pulse/android.pipe" 2>/dev/null || { mkdir -p "$R/pulse" && mkfifo -m 660 "$R/pulse/android.pipe"; } # AudioBridge makes it first
sh "$T/apk/libdd_sound.so" "$R" > "$T/server.log" 2>&1 &
srv=$!
for i in $(seq 50); do [ -S "$R/pulse/native" ] && break; sleep 0.1; done
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; sed 's/^/    /' "$T/server.log"; fails=$((fails + 1)); }
[ -S "$R/pulse/native" ] && ok "the server starts and listens at \$XDG_RUNTIME_DIR/pulse/native" || bad "no socket"
timeout 10 cat "$R/pulse/android.pipe" > "$T/out.raw" &
reader=$!
head -c 192000 /dev/urandom > "$T/in.raw"
XDG_RUNTIME_DIR="$R" timeout 10 sh "$T/apk/libdd_sound.so" pacat --raw --format=s16le --rate=48000 --channels=2 < "$T/in.raw" \
  && ok "a client plays into it" || bad "pacat failed"
info="$(XDG_RUNTIME_DIR="$R" sh "$T/apk/libdd_sound.so" pactl info 2>&1 || true)"
grep -q "Default Sink: phone" <<<"$info" && ok "the phone is the default sink" || bad "pactl info: $info"
for i in $(seq 50); do [ -S "$R/pipewire-0-manager" ] && break; sleep 0.1; done; sleep 1
st="$(XDG_RUNTIME_DIR="$R" timeout 10 sh "$T/apk/libdd_sound.so" wpctl status 2>&1 </dev/null || true)"
grep -q "WirePlumber" <<<"$st" && grep -q "\*.*Phone" <<<"$st" && ok "WirePlumber runs and picked the phone" || bad "wpctl status: $st"
sleep 2; kill "$srv"; srv=""
wait "$reader" 2>/dev/null || true
n="$(wc -c < "$T/out.raw")"
[ "$n" -ge 192000 ] && ok "the sound comes out of the FIFO ($n bytes)" || bad "only $n bytes from the FIFO"
grep -q "$(head -c 48000 "$T/in.raw" | tail -c 4800 | od -An -tx1 | tr -d ' \n' | head -c 64)" <(od -An -tx1 "$T/out.raw" | tr -d ' \n') \
  && ok "the sound arrives unchanged" || bad "the FIFO's sound differs from what was played"
grep -qE "^(\[E\]|E )" "$T/server.log" && bad "the server reported errors" || ok "no errors from the server"
[ "$fails" -eq 0 ] && echo "all sound tests passed" || { echo "$fails failed"; exit 1; }

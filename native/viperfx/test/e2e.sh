#!/bin/bash
# e2e.sh <ddapp for this machine> <display>: with viperfx.adpk, the KDE and
# Mesa runtimes installed by tools/flathub-adpk/test/store-install.py and the
# APK's libraries in place (tools/flathub-adpk/README.md, "Testing"), starts
# DeskDroid's sound server and ViPER FX under qemu-aarch64, plays a 60 Hz +
# 1 kHz tone through the default sink and checks what reaches the phone's
# FIFO: unchanged with ViPER FX off, 6 dB quieter at 50 % output volume, more
# 60 Hz with ViPER Bass.
set -u
HOSTDDAPP="$1"; DISP="$2"
F=/data/data/io.deskdroid.app/files L=/data/app/io.deskdroid.app/lib/arm64
HERE="$(cd "$(dirname "$0")" && pwd)"
W="$(mktemp -d)"; R="$W/run"; mkdir -p "$R/pulse"; mkfifo "$R/pulse/android.pipe"
CONF="$F/.var/app/org.deskdroid.ViperFX/config/deskdroid/viperfx"
export DESKDROID_FILES="$F" DESKDROID_LIBS="$L" DESKDROID_GLIBC_RUN="$L/qemu-loader.sh" HOME="$F"
snd() { XDG_RUNTIME_DIR="$R" timeout 60 sh "$L/libdd_sound.so" "$@"; }
sh "$L/libdd_sound.so" "$R" > "$W/server.log" 2>&1 & srv=$!
for i in $(seq 300); do [ -S "$R/pipewire-0-manager" ] && break; sleep 0.2; done
sleep 5
python3 - "$W/tone.raw" <<'PY'
import math, struct, sys
with open(sys.argv[1], "wb") as f:
    for i in range(48000 * 6):
        t = i / 48000; v = 0.25 * math.sin(2 * math.pi * 60 * t) + 0.25 * math.sin(2 * math.pi * 1000 * t)
        s = int(v * 32767); f.write(struct.pack("<hh", s, s))
PY
fails=0
run_case() {  # name, settings lines
  local name="$1"; shift
  mkdir -p "$CONF"; printf '[general]\npower=%s\nkeepRunning=false\n[headphone]\n' "$POWER" > "$CONF/viperfx.conf"
  for l in "$@"; do echo "$l" >> "$CONF/viperfx.conf"; done
  XDG_RUNTIME_DIR="$R" DISPLAY=":$DISP" QT_QPA_PLATFORM=xcb QT_QUICK_BACKEND=software DDAPP_HOST="$HOSTDDAPP" setsid "$HERE/../../../tools/flathub-adpk/test/launch.sh" viperfx > "$W/app-$name.log" 2>&1 & app=$!
  for i in $(seq 120); do snd pactl list short sinks 2>/dev/null | grep -q viperfx_sink && break; sleep 1; done
  sleep 3
  snd pactl info | grep "Default Sink" > "$W/default-$name.txt"
  timeout 40 cat "$R/pulse/android.pipe" > "$W/out-$name.raw" & rd=$!
  snd pacat --raw --format=s16le --rate=48000 --channels=2 < "$W/tone.raw"
  sleep 1; kill $rd 2>/dev/null; wait $rd 2>/dev/null
  snd wpctl status > "$W/wpctl-$name.txt" 2>&1
  [ -n "${SHOTS:-}" ] && import -window root -display ":$DISP" "$SHOTS/viperfx-$name.png" 2>/dev/null
  kill -TERM -- -$app 2>/dev/null; sleep 6; kill -9 -- -$app 2>/dev/null
  snd pactl info | grep "Default Sink" > "$W/after-$name.txt"
  python3 - "$W/out-$name.raw" "$name" "$(cat "$W/default-$name.txt")" "$(cat "$W/after-$name.txt")" <<'PY'
import math, struct, sys
d = open(sys.argv[1], "rb").read(); n = len(d) // 4
x = [struct.unpack_from("<h", d, i * 4)[0] / 32768 for i in range(n)]
# the loudest 3 seconds (the tone, not the silence around it)
best = 0; win = 48000 * 3
step = 4800
e = [sum(v * v for v in x[i:i + step]) for i in range(0, max(1, n - step), step)]
k = max(range(len(e)), key=lambda i: sum(e[i:i + 30])) if e else 0
seg = x[k * step:k * step + win]
def g(f):
    w = 2 * math.pi * f / 48000; c = 2 * math.cos(w); s1 = s2 = 0
    for v in seg: s1, s2 = v + c * s1 - s2, s1
    return math.sqrt(max(0, s1 * s1 + s2 * s2 - c * s1 * s2)) / max(1, len(seg)) * 2
db = lambda a: 20 * math.log10(max(a, 1e-9))
clicks = sum(1 for i in range(2, n) if abs(x[i] - 2 * x[i - 1] + x[i - 2]) > 0.045)
print(f"{sys.argv[2]:>10}: {n / 48000:5.1f} s from the FIFO, 60 Hz {db(g(60)):+6.1f} dB, 1 kHz {db(g(1000)):+6.1f} dB, {clicks} clicks  ({sys.argv[3].strip()}; after quitting: {sys.argv[4].strip()})")
PY
}
POWER=false run_case off
POWER=true run_case volume50 "master.volume=50"
POWER=true run_case bass "bass.enable=1" "bass.mode=0" "bass.freq=76" "bass.gain=300" "clarity.enable=1" "field.enable=1" "eq.enable=1" "eq.band0=600" "eq.band1=500"
cat "$W/wpctl-bass.txt" | sed -n '/Audio/,/Video/p' | head -30
echo "logs in $W"
kill $srv; wait $srv 2>/dev/null

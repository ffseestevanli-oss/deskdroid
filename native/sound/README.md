# Sound for Linux programs

Linux programs play sound through PulseAudio's protocol (libpulse), or
through PipeWire's PulseAudio server, which speaks the same protocol. Flathub
apps, AppImages and Debian's programs all expect a server at
`$XDG_RUNTIME_DIR/pulse/native`. Android has none, and the desktop's own
programs (bionic, built for the APK) play through Android directly, so a
Linux program that opened fine stayed silent.

DeskDroid runs **Debian's PipeWire and WirePlumber, unmodified**, on its own
glibc (`../glibc`), the same way ddmask runs any Linux program. That is the
compatibility layer's rule: the program isn't patched; the layer provides
what it expects. (It was PulseAudio until EasyEffects: PipeWire speaks
PulseAudio's protocol too, so every program that played before still does,
and PipeWire programs such as EasyEffects work as well.)

| File | What it is |
|---|---|
| `build.sh` | Fetches Debian trixie's `pipewire-bin`, `pipewire-pulse`, `wireplumber`, their modules and `pulseaudio-utils` (arm64) and their dependencies, and keeps only the files the server, WirePlumber, the tools and the modules `sound.sh` loads need (`closure.py`): about 12 MB zipped. Cached like the flatpak command's packages. |
| `libdd_soundsrv.so` | That tree, zipped. The app unpacks it into `files/sound` (`NativeDesk.glibcRuntime`). |
| `libdd_sound.so` (`sound.sh`) | Runs the server through glibc's loader in the APK, or its tools: `libdd_sound.so pactl info`, `libdd_sound.so wpctl status`, `pw-top`, `pw-dump`, `pw-link`. |

The desktop starts it with the session bus (`NativeDesk.startSound`) and sets
`PULSE_SERVER` for every program. It is one `pipewire` process with PipeWire's
graph, the PulseAudio protocol (`$XDG_RUNTIME_DIR/pulse/native`) and
PipeWire's own (`$XDG_RUNTIME_DIR/pipewire-0`); it starts WirePlumber, the
session manager (default sink, linking, moving streams between sinks, which
EasyEffects relies on), which ends with it. There is one sink, **Phone**
(`module-pipe-tunnel`), which writes 48 kHz stereo s16le into
`$XDG_RUNTIME_DIR/pulse/android.pipe`; `AudioBridge.kt` reads it and plays it
with an AudioTrack, so Android routes it like any app's sound (speaker,
headphones, Bluetooth) and the phone's volume applies. The sink sleeps when
nothing plays, so the AudioTrack pauses. There's a silent source (no
microphone yet), so programs that open one still start.

With EasyEffects (a store package) running, it adds its own sink and becomes
the default, so programs play into EasyEffects, and EasyEffects plays the
processed sound into Phone:

    program > EasyEffects (PipeWire) > Phone (FIFO) > AudioBridge > Android > speaker/Bluetooth

Settings for Android: no realtime scheduling (module-rt isn't loaded), no
mlock, memfd for shared memory (`/dev/shm` doesn't exist), no D-Bus, no
hardware monitors in WirePlumber (ALSA, Bluetooth, cameras: Android has
them). Its log lines are in the app log as `[sound]`.

## Testing

`test.sh` builds it from Debian's amd64 packages and runs it on a desktop
machine with that machine's loader standing in for DeskDroid's: the server
starts, WirePlumber picks Phone, `pacat` plays into it, and the same sound
comes out of the FIFO. CI runs it. The arm64 build was also run under
`qemu-aarch64` with DeskDroid's own glibc loader and libraries (build 1089's),
with the same result.

## Still open

- A microphone (a source fed from Android's AudioRecord through a second FIFO).
- The desktop's own (bionic) programs play into it when they use libpulse:
  Qt Multimedia's (Sasha) and Etherium (cubeb's PulseAudio backend, through
  the `libpulse.so.0` stand-in native/nativedesk puts next to it). Others,
  and Android apps, still play through Android directly, so EasyEffects and
  ViPER FX don't reach them.
- Phone's clock is the system clock, not the phone's audio clock: a tiny
  drift either way is a few samples dropped or a short underrun now and then.

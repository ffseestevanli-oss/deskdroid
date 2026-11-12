# Sound for Linux programs

Linux programs play sound through PulseAudio's protocol (libpulse), or
through PipeWire's PulseAudio server, which speaks the same protocol. Flathub
apps, AppImages and Debian's programs all expect a server at
`$XDG_RUNTIME_DIR/pulse/native`. Android has none, and the desktop's own
programs (bionic, built for the APK) play through Android directly, so a
Linux program that opened fine stayed silent.

DeskDroid runs **Debian's PulseAudio, unmodified**, on its own glibc
(`../glibc`), the same way ddmask runs any Linux program. That is the
compatibility layer's rule: the program isn't patched; the layer provides
what it expects.

| File | What it is |
|---|---|
| `build.sh` | Fetches Debian trixie's `pulseaudio` and `pulseaudio-utils` (arm64) and their dependencies, and keeps only the files the server, `pactl`, `pacat` and the modules below need (`closure.py`): about 6 MB instead of 190. Cached like the flatpak command's packages. |
| `libdd_soundsrv.so` | That tree, zipped. The app unpacks it into `files/sound` (`NativeDesk.glibcRuntime`). |
| `libdd_sound.so` (`sound.sh`) | Runs the server through glibc's loader in the APK, or its tools: `libdd_sound.so pactl info`. |

The desktop starts it with the session bus (`NativeDesk.startSound`) and sets
`PULSE_SERVER` for every program. The server has one sink, **Phone**
(`module-pipe-sink`), which writes 48 kHz stereo s16le into
`$XDG_RUNTIME_DIR/pulse/android.pipe`; `AudioBridge.kt` reads it and plays it
with an AudioTrack, so Android routes it like any app's sound (speaker,
headphones, Bluetooth) and the phone's volume applies. There's a silent
source (no microphone yet), so programs that open one still start.

Settings for Android: no realtime scheduling or nice changes (Android
refuses them), no shared-memory files (`/dev/shm` doesn't exist; clients fall
back to the socket), no D-Bus, no idle exit. Its log lines are in the app log
as `[sound]`.

## Testing

`test.sh` builds it from Debian's amd64 packages and runs it on a desktop
machine with that machine's loader standing in for DeskDroid's: the server
starts, `pacat` plays into it, and the sound comes out of the FIFO. CI runs
it. The arm64 build was also run under `qemu-aarch64` with DeskDroid's own
glibc loader and libraries (build 1064's).

## Still open

- A microphone (a source fed from Android's AudioRecord through a second FIFO).
- PipeWire-only programs (few: most use PulseAudio's protocol).

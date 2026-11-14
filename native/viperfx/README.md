# ViPER FX: ViPER4Android's effects on DeskDroid's desktop

An experiment: ViPER4Android FX, the Android sound mod that needs root,
as a Linux desktop app that needs none. It plugs into DeskDroid's PipeWire
sound server the way EasyEffects does, so every Linux program's sound goes
through it, and it wears DD Party's look (palette, chamfered cards, rainbow
lines, Orbitron and Chakra Petch).

    program > ViPER FX sink > ViPER's effects > Phone (FIFO) > AudioBridge > Android

## The engine

The original `libv4afx.so` is a closed binary for Android (bionic) with no
licence to redistribute it, and no Linux aarch64 build exists (Viper4Linux
used an x86_64-only blob). So this uses **ViPERFX_RE**
(github.com/AndroidAudioMods/ViPERFX_RE, branch `aidl2`, commit in
`engine/viperfx_re/UPSTREAM_COMMIT`), the open reverse-engineered
reimplementation of ViPER4Android's DSP, with these changes:

- `include/log/log.h`: Android's log macros for desktop Linux (stderr when
  `VIPERFX_DEBUG` is set).
- `viper/utils/PConvSingle.*`: the partitioned convolution was a stub
  upstream, so **Headphone Surround+ and the Convolver did nothing**. It is a
  uniformly partitioned FFT convolution now (one 4096-sample block of
  latency, as in ViPER).

Licence caveat: ViPERFX_RE's own source files carry no licence (only its
Magisk module folder is GPL-2.0), so treat this as a personal build, not
something to publish in a public store.

What works (`tests/dsptest.cpp`, `build.sh` with `VIPERFX_HOST=1`): master
volume/pan/limiter, playback gain control, ViPER-DDC (.vdc files),
spectrum extension, 10-band FIR equalizer, convolver (WAV/IRS impulse
responses, mono or stereo, resampled to 48 kHz), field surround,
differential surround, Headphone Surround+ (5 levels), reverberation,
dynamic system, tube simulator, ViPER Bass (3 modes), ViPER Clarity (3
modes), auditory system protection (Cure+), AnalogX, speaker optimization.

Not there: the **FET compressor** (ViPERFX_RE's `Process()` returns at once),
the convolver's cross-channel mix, and four-channel ("true stereo")
impulse responses. ViPER Bass's "Pure bass +" mode measures oddly (it cuts
60 Hz) and may still have a reverse-engineering bug.

## Files

| File | What it is |
|---|---|
| `engine/ViperDsp.*` | ViPER behind string keys (`bass.gain`, `eq.band3`...) in ViPER4Android's units; the app, presets and tests all use them |
| `src/PwEngine.*` | The PipeWire side: a virtual sink "ViPER FX" (`viperfx_sink`) and a playback stream into Phone in one node group, processed in the sink's RT callback; it makes itself the default sink and gives the old default back when it stops |
| `src/Backend.*` | Settings per mode (Headphone, Speaker), presets (JSON), .vdc and impulse response files (copied into the app's data), meters |
| `qml/` | The UI: one card per effect like ViPER4Android's, DD Party's components |
| `build.sh` | Cross-compiles for aarch64 against Flathub's `org.kde.Sdk//6.11` (clang + lld, Qt's moc and rcc under qemu-aarch64) into a Flatpak-style `/app` |
| `adpk.sh` | Packs that with `tools/flathub-adpk` into `viperfx.adpk` (store "program" kind on `runtime-kde-6.11`, like EasyEffects) |
| `test/e2e.sh` | Sound server + ViPER FX under qemu-aarch64, a tone through it, checks what reaches the phone's FIFO |

## Use

Needs the PipeWire sound server (APK build 1095 or newer) and the
`runtime-kde-6.11` and `runtime-mesa-25.08` packages. Install
`viperfx.adpk` from Software ("Install from a file") and open ViPER FX.
Programs that were already playing move to it; the big switch turns the
effects off (sound passes through unchanged). With "Keep processing after
closing the window" on, closing the window keeps the effects running;
opening ViPER FX again shows the same window. Quitting gives the default
sink back to Phone.

## Build

    native/viperfx/build.sh <out>                 # aarch64 app in <out>/app
    DDAPP_BIN=... native/viperfx/adpk.sh <out> <out>/viperfx.adpk
    VIPERFX_HOST=1 native/viperfx/build.sh /tmp   # offline effect test on this machine

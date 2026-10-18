# External modules (git submodules)

| Path | Upstream | Pinned at | License |
|---|---|---|---|
| `termux-x11/` | https://github.com/termux/termux-x11 | `fa3a8b430e2896a19f44c99a9cb056254615ae06` | GPL-3.0 |

DeskDroid embeds Termux:X11's `lorie` library module (the X server, its
Android activity, touch/mouse/keyboard input and clipboard sync) instead of
asking users to install the Termux:X11 app. Its native X server is built from
source by CMake from its own nested submodules (xserver, pixman, libxkbfile, ...),
so clone with:

    git submodule update --init --recursive

The settings in `settings.gradle.kts` include `:lorie` and `:shell-loader:stub`
straight from the submodule. Our AGP, Gradle and NDK versions follow the
submodule's (`external/termux-x11/build.gradle`, `lorie/version.gradle`), so bump
them together when updating the pin.

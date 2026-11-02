#!/usr/bin/env python3
"""Ports a Floorp runtime (Firefox) source tree to DeskDroid: the desktop
browser, with GTK 3 on Wayland, for Android's libc. Firefox for Android is a
different program (GeckoView, Java UI); this is desktop Firefox built for
target aarch64-linux-android, drawing through the same GTK/Wayland stack as
the other apps on the native desktop.

    native/floorp/port.py <source dir>

Each edit must apply exactly, so a new Firefox version fails loudly here."""
import pathlib
import sys

src = pathlib.Path(sys.argv[1])


def edit(path, old, new, count=1):
    p = src / path
    s = p.read_text()
    if s.count(old) != count:
        sys.exit(f"{path}: expected {count} of {old.strip()[:80]!r}, found {s.count(old)}")
    p.write_text(s.replace(old, new))


# The toolkit: GTK on Wayland for Android too (upstream allows only its own
# Android widget layer, which needs GeckoView's Java side).
edit("toolkit/moz.configure",
     '    elif target.os == "Android":\n        return ("cairo-android",)\n',
     '    elif target.os == "Android":  # DeskDroid: desktop Firefox on GTK/Wayland\n'
     '        return ("cairo-gtk3-wayland-only", "cairo-android")\n')

# The NDK: the one the rest of DeskDroid builds with (r29), where Firefox
# pins its own exact version for GeckoView.
edit("build/moz.configure/android-ndk.configure",
     "    if NDK_VERSION != human:\n",
     "    if int(major) < 29:  # DeskDroid: the app's NDK\n")

print("floorp port: applied")

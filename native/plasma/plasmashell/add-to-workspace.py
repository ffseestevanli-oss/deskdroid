#!/usr/bin/env python3
"""Cuts plasma-workspace down to plasmashell (and libkworkspace, which it
needs) and builds plasmashell as a library that DeskDroid's QtHost starts,
like kwin_wayland (see kwin-nativedesk/qthost_entry.cpp)."""
import pathlib
import sys

ws = pathlib.Path(sys.argv[1])
here = pathlib.Path(__file__).resolve().parent


def edit(rel, old, new):
    p = ws / rel
    t = p.read_text()
    if old not in t:
        sys.exit(f"add-to-workspace: {old!r} not in {rel}")
    p.write_text(t.replace(old, new, 1))


(ws / "CMakeLists.txt").write_text((here / "CMakeLists.top.txt").read_text())
(ws / "org.freedesktop.ScreenSaver.xml").write_text((here / "org.freedesktop.ScreenSaver.xml").read_text())

edit("shell/CMakeLists.txt", "add_executable(plasmashell)",
     "add_library(plasmashell SHARED)\n"
     "set_target_properties(plasmashell PROPERTIES CXX_VISIBILITY_PRESET default)")
# The systemd unit and the autostart entry are for a Linux session.
edit("shell/CMakeLists.txt", "ecm_install_configured_files(INPUT plasma-plasmashell.service.in",
     "# ecm_install_configured_files(INPUT plasma-plasmashell.service.in")
edit("shell/main.cpp", "int main(int argc, char *argv[])", "int plasmashellMain(int argc, char *argv[])")

entry = (here.parent / "kwin-nativedesk" / "qthost_entry.cpp").read_text()
entry = entry.replace("KWin's main_wayland.cpp: on Android kwin_wayland", "plasmashell's main.cpp: on Android plasmashell")
entry = entry.replace('args.push_back("kwin_wayland")', 'args.push_back("plasmashell")')
entry = entry.replace("return kwinMain(", "return plasmashellMain(")
assert "kwinMain" not in entry and '"kwin_wayland"' not in entry
p = ws / "shell" / "main.cpp"
p.write_text(p.read_text() + "\n" + entry)

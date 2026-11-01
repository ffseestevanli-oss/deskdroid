#!/usr/bin/env python3
"""Builds a KDE app as a shared library that DeskDroid's QtHost starts in an
app_process (Qt for Android needs a Java VM), like plasmashell and KWin.

as-library.py <source dir> <CMakeLists.txt, relative> <target> <main.cpp, relative>

add_executable(<target>) becomes a shared library (lib<target>.so), its
main() becomes <target>Main(), and QtHost's entry point (from
kwin-nativedesk/qthost_entry.cpp) is appended to main.cpp."""
import pathlib
import re
import sys

src, cmake, target, main = sys.argv[1:5]
src = pathlib.Path(src)
here = pathlib.Path(__file__).resolve().parent

p = src / cmake
t = p.read_text()
exe = f"add_executable({target})"
if exe not in t:
    sys.exit(f"as-library: no {exe!r} in {cmake}")
t = t.replace(exe, f"add_library({target} SHARED)\nset_target_properties({target} PROPERTIES CXX_VISIBILITY_PRESET default)", 1)
# Installed with the libraries, not as a program.
t = t.replace(f"install(TARGETS {target} ${{KDE_INSTALL_TARGETS_DEFAULT_ARGS}})",
              f"install(TARGETS {target} LIBRARY DESTINATION ${{KDE_INSTALL_LIBDIR}})")
p.write_text(t)

p = src / main
t = p.read_text()
func = f"{re.sub(r'[^A-Za-z0-9_]', '_', target)}Main"
t, n = re.subn(r"^int main\((int argc, char \*\*argv|int argc, char \*argv\[\])\)", f"int {func}(int argc, char **argv)", t, count=1, flags=re.M)
if n != 1:
    sys.exit(f"as-library: no main() in {main}")
entry = (here.parent / "kwin-nativedesk" / "qthost_entry.cpp").read_text()
entry = entry.replace('args.push_back("kwin_wayland")', f'args.push_back("{target}")')
entry = entry.replace("return kwinMain(", f"return {func}(")
assert "kwinMain" not in entry and '"kwin_wayland"' not in entry
p.write_text(t + "\n" + entry)

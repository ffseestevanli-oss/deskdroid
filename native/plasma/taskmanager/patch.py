#!/usr/bin/env python3
"""Cuts plasma-desktop's task manager down to what builds here: no X11
header, no libksysguard (process parents aren't looked up), and the
activity manager's settings file from plasma-desktop's own folder."""
import pathlib
import sys

src = pathlib.Path(sys.argv[1])
tm = src / "applets/taskmanager"


def edit(rel, old, new):
    p = tm / rel
    t = p.read_text()
    if old not in t:
        sys.exit(f"taskmanager patch: {old!r} not in {rel}")
    p.write_text(t.replace(old, new, 1))


edit("CMakeLists.txt", "${CMAKE_SOURCE_DIR}/kcms/recentFiles/", f"{src}/kcms/recentFiles/")
edit("backend.h", "#include <netwm.h>\n", "")
edit("backend.cpp", "#include <processcore/process.h>\n#include <processcore/processes.h>\n", "")
p = tm / "backend.cpp"
t = p.read_text()
a = t.index("qint64 Backend::parentPid(qint64 pid) const\n{")
b = t.index("\n}\n", a)
t = t[:a] + "qint64 Backend::parentPid(qint64 pid) const\n{\n    Q_UNUSED(pid) // DeskDroid: no libksysguard\n    return -1;" + t[b:]
p.write_text(t)
assert "KSysGuard" not in t

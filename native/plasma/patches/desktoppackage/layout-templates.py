#!/usr/bin/env python3
"""plasma-desktop's panel layout templates, which Add Panel offers: the
empty panel, and the default panel without the widgets DeskDroid doesn't
build yet (pager, system tray, show desktop, input method panel).

layout-templates.py <plasma-desktop source dir> <share/plasma/layout-templates>"""
import pathlib
import re
import shutil
import sys

src = pathlib.Path(sys.argv[1]) / "layout-templates"
out = pathlib.Path(sys.argv[2])
built = {"org.kde.plasma.kickoff", "org.kde.plasma.icontasks", "org.kde.plasma.taskmanager", "org.kde.plasma.digitalclock"}

for name in ("org.kde.plasma.desktop.defaultPanel", "org.kde.plasma.desktop.emptyPanel"):
    shutil.rmtree(out / name, ignore_errors=True)
    shutil.copytree(src / name, out / name)

js = out / "org.kde.plasma.desktop.defaultPanel/contents/layout.js"
t = js.read_text()
added = re.findall(r'panel\.addWidget\("([^"]+)"\)', t)
if "org.kde.plasma.kickoff" not in added or "org.kde.plasma.digitalclock" not in added:
    sys.exit("layout-templates.py: defaultPanel's layout.js changed")
t = re.sub(r'^(\s*)(panel\.addWidget\("([^"]+)"\);?)',
           lambda m: m.group(0) if m.group(3) in built else f"{m.group(1)}// DeskDroid: not built yet: {m.group(2)}",
           t, flags=re.M)
js.write_text(t)

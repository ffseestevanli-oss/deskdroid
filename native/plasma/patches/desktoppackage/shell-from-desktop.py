#!/usr/bin/env python3
"""Plasma's desktop shell package (plasma-desktop's desktoppackage) parts
for DeskDroid's shell: the desktop and panel views with edit mode, the
panel and widget settings, and the Add Widgets sidebar. DeskDroid's own
shell files (layout, defaults, metadata) are laid over these.

The activity switcher is left out (Plasma's activities QML needs Boost,
which isn't built yet).

shell-from-desktop.py <plasma-desktop source dir> <shell package dir>"""
import pathlib
import shutil
import sys

src = pathlib.Path(sys.argv[1]) / "desktoppackage" / "contents"
out = pathlib.Path(sys.argv[2]) / "contents"

for d in ("configuration", "explorer", "applet"):
    shutil.rmtree(out / d, ignore_errors=True)
    shutil.copytree(src / d, out / d)
(out / "views").mkdir(parents=True, exist_ok=True)
for f in ("Desktop.qml", "DesktopEditMode.qml", "Panel.qml", "PreviewBanner.qml"):
    shutil.copy(src / "views" / f, out / "views" / f)

p = out / "views" / "Desktop.qml"
t = p.read_text()


def cut(old, new=""):
    global t
    if old not in t:
        sys.exit(f"shell-from-desktop.py: Desktop.qml changed near {old[:60]!r}")
    t = t.replace(old, new, 1)


cut("import org.kde.plasma.activityswitcher as ActivitySwitcher\n")
cut('import "../activitymanager"\n')
start = t.index("    Connections {\n        target: ActivitySwitcher.Backend")
end = t.index("    function toggleWidgetExplorer")
t = t[:start] + t[end:]
cut("                ActivitySwitcher.Backend.shouldShowSwitcher = false;\n")
cut("item.showSwitcherOnly = ActivitySwitcher.Backend.shouldShowSwitcher;", "item.showSwitcherOnly = false;")
cut("item => !ActivitySwitcher.Backend.shouldShowSwitcher && !item.showingDialog,", "item => !item.showingDialog,")
if "ActivitySwitcher" in t:
    sys.exit("shell-from-desktop.py: Desktop.qml still uses ActivitySwitcher")
p.write_text(t)

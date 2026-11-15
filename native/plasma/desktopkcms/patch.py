#!/usr/bin/env python3
"""DeskDroid's changes to plasma-desktop's settings pages (build_kcms_desktop).

Accessibility without X11: the page looks up the X11 key that turns Mouse
Keys on (Xlib, XKB, KKeyServer), only when it runs on X11. That lookup and
its headers are taken out; on Wayland the page never shows it anyway."""
import pathlib
import re
import sys

ds = pathlib.Path(sys.argv[1])


def edit(rel, old, new, count=1):
    p = ds / rel
    t = p.read_text()
    if t.count(old) != count:
        sys.exit(f"desktopkcms/patch.py: {old!r} not {count}x in {rel}")
    p.write_text(t.replace(old, new))


a = "kcms/access/kcmaccess.cpp"
for inc in ("#include <QtGui/private/qtx11extras_p.h>\n", "#include <KKeyServer>\n",
            "#include <X11/XKBlib.h>\n", "#include <X11/Xlib.h>\n",
            "#define XK_MISCELLANY\n#define XK_XKB_KEYS\n#include <X11/keysymdef.h>\n"):
    edit(a, inc, "")
p = ds / a
t = p.read_text()
t, n = re.subn(r"\nQString mouseKeysShortcut\(Display \*display\)\n\{\n.*?\n\}\n", "\n", t, count=1, flags=re.S)
if n != 1:
    sys.exit("desktopkcms/patch.py: mouseKeysShortcut not found")
p.write_text(t)
edit(a, "m_desktopShortcutInfo(QX11Info::isPlatformX11() ? mouseKeysShortcut(QX11Info::display()) : QString())",
     "m_desktopShortcutInfo(QString())")

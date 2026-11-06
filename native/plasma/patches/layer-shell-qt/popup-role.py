#!/usr/bin/env python3
"""DeskDroid: layer-shell-qt takes a popup's xdg_popup from Qt's surfaceRole()
with std::any_cast<::xdg_popup *>, which compares type_info across libraries.
On Android each library has its own type_info for that pointer type, so the
cast fails, the popup is never attached to its layer surface, and KWin ends
the client (no xdg_popup parent). Fall back to Qt's native interface
("xdg_popup" for the popup's window), which needs no RTTI."""
import sys, pathlib
p = pathlib.Path(sys.argv[1]) / "src/qwaylandlayersurface.cpp"
s = p.read_text()
old = """        get_popup(*role);
    } else {"""
new = """        get_popup(*role);
    } else if (auto xdgPopup = static_cast<::xdg_popup *>(QGuiApplication::platformNativeInterface()->nativeResourceForWindow(
                   QByteArrayLiteral("xdg_popup"), popup->window()->window()))) {
        get_popup(xdgPopup); // DeskDroid: std::any_cast fails across libraries on Android
    } else {"""
if old not in s:
    sys.exit("popup-role.py: attachPopup not as expected")
s = s.replace(old, new, 1)
s = s.replace("#include <QGuiApplication>", "#include <QGuiApplication>\n#include <qpa/qplatformnativeinterface.h>", 1)
p.write_text(s)

#!/usr/bin/env python3
"""DeskDroid: plasma-workspace's Fonts page without X11. Its previews of
anti-aliasing and hinting are drawn with Xft (kfontinst's FcEngine), so
they're left out; the settings themselves are fontconfig's and Qt's."""
import pathlib
import sys

ws = pathlib.Path(sys.argv[1])


def edit(rel, old, new, count=1):
    p = ws / rel
    t = p.read_text()
    if t.count(old) != count:
        sys.exit(f"workspacekcms/patch.py: {old!r} not {count}x in {rel}")
    p.write_text(t.replace(old, new))


f = "kcms/fonts/"
edit(f + "kxftconfig.cpp", "#include <private/qtx11extras_p.h>\n", "")
edit(f + "kxftconfig.cpp", "QX11Info::appDpiY()", "96", 2)
edit(f + "fonts.cpp", '#include "previewimageprovider.h"\n', "")
edit(f + "fonts.cpp", '    engine()->addImageProvider(u"preview"_s, new PreviewImageProvider(fontsSettings()->font()));\n', "")
edit(f + "ui/main.qml", 'source: "image://preview/" + model.index + "_" + kcm.hintingCurrentIndex + ".png"', 'visible: false')
edit(f + "ui/main.qml", 'source: "image://preview/" + kcm.subPixelCurrentIndex + "_" + model.index + ".png"', 'visible: false')

#!/usr/bin/env python3
"""DeskDroid's changes to plasma-workspace's settings pages.

Fonts without X11: its previews of anti-aliasing and hinting are drawn with
Xft (kfontinst's FcEngine), so they're left out; the settings themselves
are fontconfig's and Qt's.

Application Style without Qt's Android style: it reads Android's theme
through Java, which an app on the desktop doesn't have, and its preview
crashed System Settings (QAndroidStyle::pixelMetric).

Plasma Style without plain Breeze ("default", which follows the colour
scheme): DeskDroid offers Breeze Light and Breeze Dark, and Breeze Dark is
the default. "default" stays installed: the other themes fall back to it.
The Breeze global themes pick the matching one (build_kcms_workspace).

Cursors without X11 (x11-shim/): there's nothing to apply a theme to besides
kcminputrc, which KWin watches, so applying doesn't ask for a new session.

Wallpaper: its build lists config-workspace.h two folders up, which is one
folder up in this build. It reads the desktop's settings from DeskDroid's
shell (org.deskdroid.desktop), not Plasma's.

System Sounds links Plasma's notification library, which isn't built here,
for nothing it uses."""
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

s = "kcms/style/stylesmodel.cpp"
edit(s, """    for (const QString &styleName : allStyles) {
        auto &item = styleData[styleName];""", """    for (const QString &styleName : allStyles) {
        if (styleName.compare(QLatin1String("Android"), Qt::CaseInsensitive) == 0) {
            continue;
        }
        auto &item = styleData[styleName];""")

d = "kcms/desktoptheme/"
edit(d + "themesmodel.cpp", """        const QString packageName = themeRoot.right(themeRoot.length() - themeNameSepIndex - 1);
""", """        const QString packageName = themeRoot.right(themeRoot.length() - themeNameSepIndex - 1);
        if (packageName == QLatin1String("default")) {
            continue;
        }
""")
edit(d + "desktopthemesettings.kcfg", "<default>default</default>", "<default>breeze-dark</default>")

c = "kcms/cursortheme/xcursor/themeapplicator.cpp"
edit(c, """    Q_UNUSED(theme)
    Q_UNUSED(size)
    return false;
#endif""", """    Q_UNUSED(theme)
    Q_UNUSED(size)
    return true; // DeskDroid: KWin reads the theme from kcminputrc by itself
#endif""")

edit("kcms/wallpaper/wallpapermodule.cpp", 'u"/plasma-org.kde.plasma.desktop-appletsrc"', 'u"/plasma-org.deskdroid.desktop-appletsrc"')
edit("kcms/wallpaper/CMakeLists.txt", "${CMAKE_CURRENT_BINARY_DIR}/../../config-workspace.h", "${CMAKE_CURRENT_BINARY_DIR}/../config-workspace.h")

edit("kcms/soundtheme/CMakeLists.txt", "    PW::LibNotificationManager\n", "")

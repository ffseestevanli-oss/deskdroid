#!/usr/bin/env python3
"""KIconTheme::initTheme() for DeskDroid: kiconthemes built without the
BreezeIcons library (the Android branch) leaves Qt with no icon theme, so
Qt Widgets apps such as Dolphin draw no icons. This makes the branch read
the theme from kdeglobals ([Icons] Theme, Breeze by default) and look for
it in $XDG_DATA_DIRS/icons, as Plasma does.

icon-theme.py <kiconthemes source dir>"""
import pathlib
import sys

p = pathlib.Path(sys.argv[1]) / "src" / "kicontheme.cpp"
t = p.read_text()
old = """static void initThemeHelper()
{
    // postpone until QGuiApplication applies initial palette
    QTimer::singleShot(0, [] {
        // follow the system color, construct the global manager for that
        (void)KColorSchemeManager::instance();
    });
}

void KIconTheme::initTheme()
{
}
"""
new = """static void initThemeHelper()
{
    // DeskDroid: icon themes from $XDG_DATA_DIRS/icons, the user's theme
    // from kdeglobals, Breeze when an icon is missing from it.
    if (!qobject_cast<QGuiApplication *>(QCoreApplication::instance())) {
        return;
    }
    QStringList paths = QIcon::themeSearchPaths();
    const QStringList dataDirs = QStandardPaths::standardLocations(QStandardPaths::GenericDataLocation);
    for (const QString &dir : dataDirs) {
        const QString icons = dir + QStringLiteral("/icons");
        if (!paths.contains(icons) && QFile::exists(icons)) {
            paths.append(icons);
        }
    }
    QIcon::setThemeSearchPaths(paths);
    QIcon::setFallbackThemeName(QStringLiteral("breeze"));
    const QString themeToUse = KConfigGroup(KSharedConfig::openConfig(), QStringLiteral("Icons")).readEntry("Theme", QStringLiteral("breeze"));
    QIcon::setThemeName(themeToUse);
    *_themeOverride() = themeToUse;

    // postpone until QGuiApplication applies initial palette
    QTimer::singleShot(0, [] {
        // follow the system color, construct the global manager for that
        (void)KColorSchemeManager::instance();
    });
}

void KIconTheme::initTheme()
{
}
"""
if old not in t:
    sys.exit("icon-theme.py: kicontheme.cpp's Android branch changed")
t = t.replace(old, new, 1)
for inc in ("#include <QIcon>", "#include <QGuiApplication>", "#include <QStandardPaths>", "#include <QFile>", "#include <KConfigGroup>", "#include <KSharedConfig>"):
    if inc not in t:
        t = t.replace('#include "config.h"', inc + '\n#include "config.h"', 1)
p.write_text(t)

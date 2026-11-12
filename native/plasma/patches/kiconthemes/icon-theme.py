#!/usr/bin/env python3
"""KIconTheme::initTheme() for DeskDroid: kiconthemes built without the
BreezeIcons library (the Android branch) leaves Qt with no icon theme, so
Qt Widgets apps such as Dolphin draw no icons. This makes the branch read
the theme from kdeglobals ([Icons] Theme, Breeze by default) and look for
it in $XDG_DATA_DIRS/icons, as Plasma does. Under Plasma's platform theme
it only adds the search paths: the platform theme picks the theme.

It also has KIconLoader look for an icon's exact name in every theme
before its shortened names (kiconloader.cpp, below).

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
    // With Plasma's platform theme (QT_QPA_PLATFORMTHEME=kde) the theme comes
    // from it and follows System Settings › Icons; pinning it here (as KDE
    // does without that platform theme) kept apps on the theme they started with.
    if (QGuiApplicationPrivate::platformTheme() && QGuiApplicationPrivate::platformTheme()->name() == QLatin1String("kde")) {
        return;
    }
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

# Exact names before shortened ones: KIconLoader tries an icon's shortened
# names (preferences-desktop-color, then preferences-desktop, then
# preferences) in each theme before it looks in the next. Breeze Dark here
# holds only the icons it recolors and inherits the rest from Breeze (no
# copies of them all, build-deps.sh's build_breeze_icons), so its own
# "preferences" icon (System Settings' cog) stood in for every colour icon
# only Breeze has: System Settings' pages all showed it. Upstream ships those
# copies in Breeze Dark, so it never meets this.
p = pathlib.Path(sys.argv[1]) / "src" / "kiconloader.cpp"
t = p.read_text()
old = """    bool genericFallback = name.endsWith(QLatin1String("-x-generic"));
    bool isSymbolic = name.endsWith(QLatin1String("-symbolic"));
    QString path;
    for (KIconThemeNode *themeNode : std::as_const(links)) {
"""
new = """    bool genericFallback = name.endsWith(QLatin1String("-x-generic"));
    bool isSymbolic = name.endsWith(QLatin1String("-symbolic"));
    QString path;
    // DeskDroid: the exact name in every theme (Breeze Dark, then Breeze,
    // then hicolor) before any shortened one.
    for (KIconThemeNode *themeNode : std::as_const(links)) {
        path = themeNode->theme->iconPathByName(name, size, KIconLoader::MatchBest, scale);
        if (!path.isEmpty()) {
            return path;
        }
    }
    for (KIconThemeNode *themeNode : std::as_const(links)) {
"""
if old not in t:
    sys.exit("icon-theme.py: kiconloader.cpp's findMatchingIcon changed")
p.write_text(t.replace(old, new, 1))

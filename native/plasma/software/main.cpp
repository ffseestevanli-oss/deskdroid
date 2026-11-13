// DeskDroid's Software: the app store on the desktop. Finds, installs,
// updates and removes apps from Software's catalog, and installs .adpk
// packages (DeskDroid's own package files, like .deb) when one is opened
// (`software <file.adpk>`, a double-click in Dolphin). Browses all of Flathub
// too, and installs from it, or from a .flatpakref / .flatpakrepo / .flatpak
// file, with the flatpak command (native/flatpak). Kirigami, in the
// Steam Installation Assistant's party look. The work is the phone app's
// (Store.kt, through SoftwareBridge.kt); this is its window.
#include "backend.h"

#include <QApplication>
#include <QFontDatabase>
#include <QIcon>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QUrl>
#include <QtQml>

static int softwareMain(int argc, char **argv)
{
    QApplication app(argc, argv);
    QApplication::setApplicationName(QStringLiteral("software"));
    QApplication::setApplicationDisplayName(QStringLiteral("Agora"));
    QApplication::setOrganizationDomain(QStringLiteral("deskdroid.io"));
    QApplication::setDesktopFileName(QStringLiteral("org.deskdroid.software"));
    QApplication::setWindowIcon(QIcon::fromTheme(QStringLiteral("org.deskdroid.software"), QIcon(QStringLiteral(":/icon.svg"))));
    for (const char *font : {":/fonts/Orbitron.ttf", ":/fonts/ChakraPetch-Regular.ttf", ":/fonts/ChakraPetch-SemiBold.ttf", ":/fonts/ChakraPetch-Bold.ttf"})
        QFontDatabase::addApplicationFont(QString::fromLatin1(font));

    // The crash dialog: --crashed <id> <name> <log> (adpk-run.sh).
    const QStringList all = app.arguments();
    const int crashed = all.indexOf(QStringLiteral("--crashed"));
    if (crashed > 0 && all.size() > crashed + 3) {
        CrashReport report(all[crashed + 1], all[crashed + 2], all[crashed + 3]);
        QApplication::setApplicationDisplayName(QStringLiteral("Something's not right"));
        QApplication::setWindowIcon(QIcon::fromTheme(QStringLiteral("dialog-error"), QIcon(QStringLiteral(":/icon.svg"))));
        QQmlApplicationEngine engine;
        engine.rootContext()->setContextProperty(QStringLiteral("report"), &report);
        engine.load(QUrl(QStringLiteral("qrc:/qml/Crash.qml")));
        if (engine.rootObjects().isEmpty())
            return 1;
        return app.exec();
    }

    Backend backend;
    // A package to install: the first argument that isn't an option.
    QString package;
    const QStringList args = app.arguments().mid(1);
    for (const QString &a : args)
        if (!a.startsWith(QLatin1Char('-'))) { package = backend.localPath(a); break; }

    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty(QStringLiteral("backend"), &backend);
    // A .flatpakref, .flatpakrepo or .flatpak goes to the Flatpak page, an
    // .adpk to the package page.
    const bool flatpakFile = Backend::isFlatpakFile(package);
    engine.rootContext()->setContextProperty(QStringLiteral("startPackage"), flatpakFile ? QString() : package);
    engine.rootContext()->setContextProperty(QStringLiteral("startFlatpakFile"), flatpakFile ? package : QString());
    engine.load(QUrl(QStringLiteral("qrc:/qml/Main.qml")));
    if (engine.rootObjects().isEmpty())
        return 1;
    return app.exec();
}

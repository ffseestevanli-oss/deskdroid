// DeskDroid's Software: the app store on the desktop. Finds, installs,
// updates and removes apps from Software's catalog, and installs .adpk
// packages (DeskDroid's own package files, like .deb) when one is opened
// (`software <file.adpk>`, a double-click in Dolphin). Kirigami, in the
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

    Backend backend;
    // A package to install: the first argument that isn't an option.
    QString package;
    const QStringList args = app.arguments().mid(1);
    for (const QString &a : args)
        if (!a.startsWith(QLatin1Char('-'))) { package = backend.localPath(a); break; }

    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty(QStringLiteral("backend"), &backend);
    engine.rootContext()->setContextProperty(QStringLiteral("startPackage"), package);
    engine.load(QUrl(QStringLiteral("qrc:/qml/Main.qml")));
    if (engine.rootObjects().isEmpty())
        return 1;
    return app.exec();
}

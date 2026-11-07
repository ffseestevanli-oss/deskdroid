// DeskDroid's Steam Installation Assistant: sets up Steam (FEX-Emu, its x86
// system, Valve's bootstrap) with a guide instead of a terminal, then stays as
// the place to look after Steam, FEX-Emu and Proton. Kirigami, in DeskDroid's
// party look (qml/Party.qml). Built as a library QtHost starts, like the
// desktop's other apps (bin/steam-assistant, native/nativedesk/qtapp.sh).
#include "backend.h"

#include <QApplication>
#include <QFontDatabase>
#include <QIcon>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QUrl>
#include <QtQml>

static int assistantMain(int argc, char **argv)
{
    QApplication app(argc, argv);
    QApplication::setApplicationName(QStringLiteral("steam-assistant"));
    QApplication::setApplicationDisplayName(QStringLiteral("Steam Installation Assistant"));
    QApplication::setOrganizationDomain(QStringLiteral("deskdroid.io"));
    QApplication::setDesktopFileName(QStringLiteral("org.deskdroid.steamassistant"));
    QApplication::setWindowIcon(QIcon::fromTheme(QStringLiteral("org.deskdroid.steamassistant"), QIcon(QStringLiteral(":/icon.svg"))));
    // DeskDroid's fonts (the phone app's Orbitron and Chakra Petch).
    for (const char *font : {":/fonts/Orbitron.ttf", ":/fonts/ChakraPetch-Regular.ttf", ":/fonts/ChakraPetch-SemiBold.ttf", ":/fonts/ChakraPetch-Bold.ttf"})
        QFontDatabase::addApplicationFont(QString::fromLatin1(font));

    Backend backend;
    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty(QStringLiteral("backend"), &backend);
    const bool tools = app.arguments().contains(QStringLiteral("--tools"));
    engine.rootContext()->setContextProperty(QStringLiteral("startOnTools"), tools);
    engine.load(QUrl(QStringLiteral("qrc:/qml/Main.qml")));
    if (engine.rootObjects().isEmpty())
        return 1;
    return app.exec();
}

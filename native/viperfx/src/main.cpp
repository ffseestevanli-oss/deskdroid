// ViPER FX for DeskDroid: ViPER4Android's effects as a desktop app on the
// PipeWire sound server, in DD Party's look.
#include <QFontDatabase>
#include <QGuiApplication>
#include <QIcon>
#include <QLocalServer>
#include <QLocalSocket>
#include <QPalette>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QQuickWindow>
#include <csignal>
#include <unistd.h>

#include "Backend.h"

namespace {
QString socketName() { return QStringLiteral("viperfx-%1").arg(getuid()); }

void ddPartyPalette(QGuiApplication &app) {
    QPalette p;
    auto c = [](const char *h) { return QColor(QString::fromLatin1(h)); };
    p.setColor(QPalette::Window, c("#07070D"));
    p.setColor(QPalette::WindowText, c("#F2F2F7"));
    p.setColor(QPalette::Base, c("#0D0D16"));
    p.setColor(QPalette::AlternateBase, c("#10101B"));
    p.setColor(QPalette::Text, c("#F2F2F7"));
    p.setColor(QPalette::Button, c("#12121E"));
    p.setColor(QPalette::ButtonText, c("#F2F2F7"));
    p.setColor(QPalette::Highlight, c("#990045"));
    p.setColor(QPalette::HighlightedText, c("#FFFFFF"));
    p.setColor(QPalette::ToolTipBase, c("#10101B"));
    p.setColor(QPalette::ToolTipText, c("#F2F2F7"));
    p.setColor(QPalette::PlaceholderText, c("#8A8AA6"));
    p.setColor(QPalette::Mid, c("#2A2A3D"));
    p.setColor(QPalette::Dark, c("#07070D"));
    p.setColor(QPalette::Light, c("#262638"));
    p.setColor(QPalette::Link, c("#FF4D94"));
    p.setColor(QPalette::Disabled, QPalette::Text, c("#8A8AA6"));
    p.setColor(QPalette::Disabled, QPalette::ButtonText, c("#8A8AA6"));
    p.setColor(QPalette::Disabled, QPalette::WindowText, c("#8A8AA6"));
    app.setPalette(p);
}
}  // namespace

int main(int argc, char *argv[]) {
    QGuiApplication app(argc, argv);
    app.setApplicationName("viperfx");
    app.setOrganizationName("deskdroid");
    app.setApplicationDisplayName("ViPER FX");
    app.setDesktopFileName("org.deskdroid.ViperFX");
    app.setWindowIcon(QIcon(":/icons/viperfx.svg"));

    // One ViPER FX: a second start shows the running one's window.
    {
        QLocalSocket probe;
        probe.connectToServer(socketName());
        if (probe.waitForConnected(500)) {
            probe.write("show\n");
            probe.waitForBytesWritten(500);
            return 0;
        }
    }
    QLocalServer::removeServer(socketName());
    QLocalServer server;
    server.listen(socketName());

    for (const char *f : {":/fonts/Orbitron.ttf", ":/fonts/ChakraPetch-Regular.ttf",
                          ":/fonts/ChakraPetch-SemiBold.ttf", ":/fonts/ChakraPetch-Bold.ttf"})
        QFontDatabase::addApplicationFont(QString::fromLatin1(f));
    QFont font("Chakra Petch");
    font.setPointSizeF(10.5);
    app.setFont(font);
    ddPartyPalette(app);
    QQuickStyle::setStyle("Basic");

    Backend backend;
    backend.startEngine();
    app.setQuitOnLastWindowClosed(false);

    QQmlApplicationEngine qml;
    qml.rootContext()->setContextProperty("viper", &backend);
    qml.load(QUrl("qrc:/qml/Main.qml"));
    if (qml.rootObjects().isEmpty()) return 1;
    auto *window = qobject_cast<QQuickWindow *>(qml.rootObjects().first());

    QObject::connect(&server, &QLocalServer::newConnection, [&]() {
        while (QLocalSocket *s = server.nextPendingConnection()) {
            QObject::connect(s, &QLocalSocket::readyRead, s, [s, window]() {
                if (s->readAll().startsWith("show") && window) {
                    window->show();
                    window->raise();
                    window->requestActivate();
                }
                s->deleteLater();
            });
        }
    });
    // Closing the window: keep processing (like ViPER4Android's service) or quit.
    QObject::connect(window, &QQuickWindow::visibleChanged, [&](bool visible) {
        if (!visible && !backend.keepRunning()) app.quit();
    });
    QObject::connect(&app, &QGuiApplication::aboutToQuit, [&]() { backend.stopEngine(); });
    // A stop from outside (logout, kill) still gives the default sink back.
    std::signal(SIGTERM, [](int) { QMetaObject::invokeMethod(qApp, "quit", Qt::QueuedConnection); });
    std::signal(SIGINT, [](int) { QMetaObject::invokeMethod(qApp, "quit", Qt::QueuedConnection); });

    if (app.arguments().contains("--background")) window->hide();
    return app.exec();
}

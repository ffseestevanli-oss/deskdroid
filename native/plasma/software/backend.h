// DeskDroid's Software: the QML pages' link to the phone app's store
// (SoftwareBridge.kt). Requests go to $HOME/open-requests, like android-open;
// the answer is $HOME/software/state.json, watched for changes.
#pragma once

#include <QFileSystemWatcher>
#include <QObject>
#include <QString>
#include <QTimer>
#include <QVariantList>
#include <QVariantMap>

class Backend : public QObject
{
    Q_OBJECT
    // [{id, name, summary, version, size, installed (version or null), icon (a file), local}], A to Z
    Q_PROPERTY(QVariantList apps READ apps NOTIFY changed)
    // {id: progress 0..1, or -1 without an estimate}; "file:<path>" for a package
    Q_PROPERTY(QVariantMap busy READ busy NOTIFY changed)
    Q_PROPERTY(QString error READ error NOTIFY changed)
    Q_PROPERTY(QString catalogError READ catalogError NOTIFY changed)
    // Where the catalog was read from.
    Q_PROPERTY(QString source READ source NOTIFY changed)
    // The .adpk being looked at: {path, id, name, summary, version, installed, icon, done, invalid}
    Q_PROPERTY(QVariantMap package READ package NOTIFY changed)
    // Waiting for the first answer.
    Q_PROPERTY(bool loading READ loading NOTIFY changed)
    // No phone app answering (a preview off the phone, or an old APK).
    Q_PROPERTY(bool offline READ offline NOTIFY changed)

public:
    explicit Backend(QObject *parent = nullptr);

    QVariantList apps() const { return m_apps; }
    QVariantMap busy() const { return m_busy; }
    QString error() const { return m_error; }
    QString catalogError() const { return m_catalogError; }
    QString source() const { return m_source; }
    QVariantMap package() const { return m_package; }
    bool loading() const { return m_serial < 0 && !m_offline; }
    bool offline() const { return m_offline; }

    Q_INVOKABLE void refresh();
    Q_INVOKABLE void install(const QString &id);
    Q_INVOKABLE void remove(const QString &id);
    Q_INVOKABLE void inspect(const QString &path);
    Q_INVOKABLE void installPackage(const QString &path);
    Q_INVOKABLE void dismiss();
    // Starts an installed app (bin/<id>).
    Q_INVOKABLE void launch(const QString &id);
    Q_INVOKABLE QString localPath(const QString &url) const;

Q_SIGNALS:
    void changed();

private:
    void request(const QString &what);
    void read();
    QString stateDir() const;

    QFileSystemWatcher m_watcher;
    QTimer m_poll;
    QTimer m_timeout;
    QVariantList m_apps;
    QVariantMap m_busy;
    QVariantMap m_package;
    QString m_error;
    QString m_catalogError;
    QString m_source;
    qint64 m_serial = -1;
    qint64 m_stamp = 0;
    qint64 m_started = 0;
    bool m_offline = false;
    int m_counter = 0;
};

// The crash dialog (`software --crashed <id> <name> <log>`, Crash.qml): the
// launcher (native/flatpak/adpk-run.sh) opens it when an app fails, with the
// report it wrote. No catalog, so no Backend.
class CrashReport : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString id MEMBER m_id CONSTANT)
    Q_PROPERTY(QString name MEMBER m_name CONSTANT)
    Q_PROPERTY(QString log MEMBER m_log CONSTANT)
public:
    CrashReport(const QString &id, const QString &name, const QString &log, QObject *parent = nullptr)
        : QObject(parent), m_id(id), m_name(name), m_log(log) {}
    // The report's last lines, for a look before saving.
    Q_INVOKABLE QString tail(int lines) const;
    // A file name to suggest: <id>-crash-<date>.log.
    Q_INVOKABLE QString suggestedName() const;
    // Copies the report to a file the person chose; "" or the error.
    Q_INVOKABLE QString saveTo(const QString &url) const;
private:
    QString m_id, m_name, m_log;
};

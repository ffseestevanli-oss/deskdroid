// DeskDroid's Software: the QML pages' link to the phone app's store
// (SoftwareBridge.kt). Requests go to $HOME/open-requests, like android-open;
// the answer is $HOME/software/state.json, watched for changes.
#pragma once

#include <QFileSystemWatcher>
#include <QObject>
#include <QProcess>
#include <QString>
#include <QTimer>
#include <QVariantList>
#include <QVariantMap>

#include <functional>

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

    // All of Flathub, through the phone app (FlathubCatalog.kt): {category,
    // query, page, total, loading, error, results: [{id, name, summary,
    // description, icon, arches, developer, verified, license, installs}]}.
    Q_PROPERTY(QVariantMap flathub READ flathub NOTIFY changed)
    // Flathub apps the flatpak command installed: {id: {version, arch}}.
    Q_PROPERTY(QVariantMap flatpaks READ flatpaks NOTIFY changed)
    // The flatpak command is there (native/flatpak's bin/flatpak).
    Q_PROPERTY(bool flatpakAvailable READ flatpakAvailable CONSTANT)
    // The machine's own architecture as Flatpak names it (aarch64 on a phone).
    Q_PROPERTY(QString arch READ arch CONSTANT)
    // A .flatpakref, .flatpakrepo or .flatpak opened in Agora: {path, kind
    // ("ref" | "repo" | "bundle"), name, title, summary, description,
    // homepage, url, branch, icon (an http URL or ""), runtime, done, invalid}.
    Q_PROPERTY(QVariantMap flatpakFile READ flatpakFile NOTIFY changed)
    // The last flatpak job that failed, per busy key ("flatpak:<id>"): why,
    // shown on that app's row and page. Everything flatpak said is in
    // $HOME/software/flatpak.log (in the app's saved log too).
    Q_PROPERTY(QVariantMap failures READ failures NOTIFY changed)

public:
    explicit Backend(QObject *parent = nullptr);

    QVariantList apps() const { return m_apps; }
    QVariantMap busy() const;
    QString error() const { return m_flatpakError.isEmpty() ? m_error : m_flatpakError; }
    QString catalogError() const { return m_catalogError; }
    QString source() const { return m_source; }
    QVariantMap package() const { return m_package; }
    bool loading() const { return m_serial < 0 && !m_offline; }
    bool offline() const { return m_offline; }
    QVariantMap flathub() const { return m_flathub; }
    QVariantMap flatpaks() const { return m_flatpaks; }
    bool flatpakAvailable() const;
    QString arch() const;
    QVariantMap flatpakFile() const { return m_flatpakFile; }
    QVariantMap failures() const { return m_failures; }

    Q_INVOKABLE void refresh();
    Q_INVOKABLE void install(const QString &id);
    Q_INVOKABLE void remove(const QString &id);
    Q_INVOKABLE void inspect(const QString &path);
    Q_INVOKABLE void installPackage(const QString &path);
    Q_INVOKABLE void dismiss();
    // Starts an installed app (bin/<id>).
    Q_INVOKABLE void launch(const QString &id);
    Q_INVOKABLE QString localPath(const QString &url) const;

    // All of Flathub. No query and no category: the popular list. A page
    // after the first adds to the results.
    Q_INVOKABLE void searchFlathub(const QString &query, const QString &category, int page = 1);
    // Flathub apps, with the flatpak command (busy key "flatpak:<id>").
    // arch "": the machine's own; "x86_64" on a phone runs through FEX.
    Q_INVOKABLE void installFlatpak(const QString &id, const QString &arch);
    Q_INVOKABLE void removeFlatpak(const QString &id);
    Q_INVOKABLE void updateFlatpaks(); // busy key "flatpak:*"
    Q_INVOKABLE void launchFlatpak(const QString &id);
    Q_INVOKABLE void refreshFlatpaks();
    // Which of Flathub's builds Agora installs: "" (the machine's own), "x86_64"
    // (through FEX), or "none".
    Q_INVOKABLE QString archFor(const QVariantList &arches) const;
    // A .flatpakref / .flatpakrepo / .flatpak file: true if the path is one.
    Q_INVOKABLE static bool isFlatpakFile(const QString &path);
    Q_INVOKABLE void inspectFlatpakFile(const QString &path);
    Q_INVOKABLE void installFlatpakFile(const QString &path); // busy key "file:<path>"

Q_SIGNALS:
    void changed();

private:
    void request(const QString &what);
    void read();
    QString stateDir() const;

    // The flatpak command's work, one job at a time (Flatpak locks its repo).
    struct Job {
        QString key;                 // the busy key
        QList<QStringList> steps;    // flatpak's arguments, run in order
        QStringList retry;           // run instead of the last step if it fails, or empty
        QString what;                // for the error: "Couldn't <what>"
        std::function<void(bool)> done;
    };
    void enqueue(Job job);
    void nextJob();
    void runStep();
    void listFlatpaks();
    QString flatpakError(const QString &output) const;

    QVariantMap m_flathub;
    QVariantMap m_flatpaks;
    QVariantMap m_flatpakBusy;
    QVariantMap m_flatpakFile;
    QVariantMap m_failures;
    void log(const QString &text);
    QString m_flatpakError;
    QList<Job> m_jobs;
    QProcess *m_proc = nullptr;
    QString m_output;
    int m_step = 0;
    bool m_retrying = false;

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

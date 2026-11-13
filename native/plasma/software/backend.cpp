#include "backend.h"

#include <QCollator>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QUrl>
#include <algorithm>
#include <unistd.h>

static QString home()
{
    const QString h = qEnvironmentVariable("HOME");
    return h.isEmpty() ? QDir::homePath() : h;
}

Backend::Backend(QObject *parent)
    : QObject(parent)
{
    m_started = QDateTime::currentMSecsSinceEpoch() - 1000;
    QDir().mkpath(stateDir());
    // The phone app replaces state.json (a rename), which a watcher on the
    // file loses: the folder is watched, and a timer looks too while work
    // is going on, in case a change is missed.
    m_watcher.addPath(stateDir());
    connect(&m_watcher, &QFileSystemWatcher::directoryChanged, this, &Backend::read);
    m_poll.setInterval(400);
    connect(&m_poll, &QTimer::timeout, this, &Backend::read);
    // No answer at all: the phone app isn't listening (or this is a preview).
    m_timeout.setSingleShot(true);
    m_timeout.setInterval(8000);
    connect(&m_timeout, &QTimer::timeout, this, [this] {
        if (m_serial < 0) { m_offline = true; m_poll.stop(); Q_EMIT changed(); }
    });
    read(); // what the last run left, until the phone answers
    m_serial = -1;
    refresh();
}

QString Backend::stateDir() const
{
    const QString preview = qEnvironmentVariable("SOFTWARE_STATE_DIR");
    return preview.isEmpty() ? home() + QStringLiteral("/software") : preview;
}

void Backend::request(const QString &what)
{
    // As android-open.sh does: a file in open-requests, written then renamed.
    const QString dir = home() + QStringLiteral("/open-requests");
    QDir().mkpath(dir);
    const QString name = QStringLiteral("software-%1-%2").arg(getpid()).arg(++m_counter);
    QFile tmp(dir + QStringLiteral("/.") + name);
    if (tmp.open(QIODevice::WriteOnly)) {
        tmp.write((QStringLiteral("deskdroid:software:") + what + QLatin1Char('\n')).toUtf8());
        tmp.close();
        QFile::rename(tmp.fileName(), dir + QLatin1Char('/') + name + QStringLiteral(".req"));
    }
    m_poll.start();
    if (m_serial < 0) m_timeout.start();
}

void Backend::refresh() { request(QStringLiteral("refresh")); }

void Backend::install(const QString &id)
{
    m_busy.insert(id, 0.0); // at once, before the phone answers
    Q_EMIT changed();
    request(QStringLiteral("install:") + id);
}

void Backend::remove(const QString &id)
{
    m_busy.insert(id, -1.0);
    Q_EMIT changed();
    request(QStringLiteral("remove:") + id);
}

void Backend::inspect(const QString &path)
{
    m_package = QVariantMap{{QStringLiteral("path"), path}};
    Q_EMIT changed();
    request(QStringLiteral("inspect:") + path);
}

void Backend::installPackage(const QString &path)
{
    m_busy.insert(QStringLiteral("file:") + path, -1.0);
    Q_EMIT changed();
    request(QStringLiteral("adpk:") + path);
}

void Backend::dismiss()
{
    m_package.clear();
    m_error.clear();
    Q_EMIT changed();
    request(QStringLiteral("dismiss"));
}

void Backend::launch(const QString &id)
{
    // A theme has no program: its "open" (open.txt, Store.kt) says what to run.
    for (const QVariant &a : std::as_const(m_apps)) {
        const QVariantMap m = a.toMap();
        if (m.value(QStringLiteral("id")).toString() != id) continue;
        QStringList cmd = QProcess::splitCommand(m.value(QStringLiteral("open")).toString());
        if (!cmd.isEmpty()) {
            const QString program = cmd.takeFirst();
            QProcess::startDetached(program, cmd, home());
            return;
        }
    }
    QProcess::startDetached(id, {}, home());
}

QString Backend::localPath(const QString &url) const
{
    const QUrl u(url);
    return u.isLocalFile() ? u.toLocalFile() : url.startsWith(QLatin1Char('/')) ? url : QFileInfo(url).absoluteFilePath();
}

void Backend::read()
{
    QFile f(stateDir() + QStringLiteral("/state.json"));
    const qint64 stamp = QFileInfo(f).lastModified().toMSecsSinceEpoch();
    if (!f.open(QIODevice::ReadOnly)) return;
    const QJsonObject o = QJsonDocument::fromJson(f.readAll()).object();
    if (o.isEmpty()) return;
    const qint64 serial = o.value(QStringLiteral("serial")).toInteger(-1);
    if (serial == m_serial && stamp == m_stamp) return;
    // The first answer this run: a state written after the requests were sent.
    if (m_serial < 0 && m_counter > 0 && stamp < m_started) return;
    m_serial = serial;
    m_stamp = stamp;
    m_offline = false;
    m_timeout.stop();

    QVariantList apps = o.value(QStringLiteral("apps")).toArray().toVariantList();
    QCollator c;
    c.setCaseSensitivity(Qt::CaseInsensitive);
    std::stable_sort(apps.begin(), apps.end(), [&](const QVariant &a, const QVariant &b) {
        return c.compare(a.toMap().value(QStringLiteral("name")).toString(), b.toMap().value(QStringLiteral("name")).toString()) < 0;
    });
    m_apps = apps;
    m_busy = o.value(QStringLiteral("busy")).toObject().toVariantMap();
    m_error = o.value(QStringLiteral("error")).toString();
    m_catalogError = o.value(QStringLiteral("catalogError")).toString();
    m_source = o.value(QStringLiteral("source")).toString();
    const QVariantMap pkg = o.value(QStringLiteral("package")).toObject().toVariantMap();
    // Only the package this window asked about.
    if (!m_package.isEmpty() && pkg.value(QStringLiteral("path")) == m_package.value(QStringLiteral("path")))
        m_package = pkg;
    if (m_busy.isEmpty()) m_poll.stop();
    Q_EMIT changed();
}

QString CrashReport::tail(int lines) const
{
    QFile f(m_log);
    if (!f.open(QIODevice::ReadOnly))
        return QStringLiteral("(no log at %1)").arg(m_log);
    if (f.size() > 64 * 1024)
        f.seek(f.size() - 64 * 1024);
    QStringList all = QString::fromUtf8(f.readAll()).split(QLatin1Char('\n'));
    while (!all.isEmpty() && all.last().trimmed().isEmpty())
        all.removeLast();
    return all.mid(std::max<qsizetype>(0, all.size() - lines)).join(QLatin1Char('\n'));
}

QString CrashReport::suggestedName() const
{
    return QStringLiteral("%1-crash-%2.log").arg(m_id, QDateTime::currentDateTime().toString(QStringLiteral("yyyy-MM-dd-HHmm")));
}

QString CrashReport::saveTo(const QString &url) const
{
    const QUrl u(url);
    const QString to = u.isLocalFile() ? u.toLocalFile() : url;
    if (QFile::exists(to))
        QFile::remove(to);
    QFile from(m_log);
    if (!from.copy(to))
        return from.errorString();
    return QString();
}

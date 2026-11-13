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
#include <QRegularExpression>
#include <QSettings>
#include <QStandardPaths>
#include <QSysInfo>
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
    refreshFlatpaks();
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
    m_flatpakError.clear();
    m_flatpakFile.clear();
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
    if (o.contains(QStringLiteral("flathub")))
        m_flathub = o.value(QStringLiteral("flathub")).toObject().toVariantMap();
    const QVariantMap pkg = o.value(QStringLiteral("package")).toObject().toVariantMap();
    // Only the package this window asked about.
    if (!m_package.isEmpty() && pkg.value(QStringLiteral("path")) == m_package.value(QStringLiteral("path")))
        m_package = pkg;
    if (m_busy.isEmpty() && !m_flathub.value(QStringLiteral("loading")).toBool()) m_poll.stop();
    Q_EMIT changed();
}

// ---- All of Flathub ------------------------------------------------------
//
// The catalog comes from the phone app (FlathubCatalog.kt, which has the
// network and Android's certificates); installing is the flatpak command
// (native/flatpak: bin/flatpak, per-user installs in the app's files), run
// from here like Konsole would. Flathub's ARM64 builds run through ddmask;
// an app Flathub only builds for x86-64 is installed with --arch=x86_64 and
// `flatpak run` starts it through FEX (native/flatpak/fex-run.sh).

static const QString kFlathubRepo = QStringLiteral("https://dl.flathub.org/repo/flathub.flatpakrepo");

QVariantMap Backend::busy() const
{
    QVariantMap all = m_busy;
    for (auto it = m_flatpakBusy.cbegin(); it != m_flatpakBusy.cend(); ++it)
        all.insert(it.key(), it.value());
    return all;
}

bool Backend::flatpakAvailable() const
{
    return !QStandardPaths::findExecutable(QStringLiteral("flatpak")).isEmpty();
}

QString Backend::arch() const
{
    // Previews and tests off the phone can pretend (SOFTWARE_ARCH=aarch64).
    const QString forced = qEnvironmentVariable("SOFTWARE_ARCH");
    if (!forced.isEmpty()) return forced;
    const QString cpu = QSysInfo::currentCpuArchitecture();
    if (cpu == QLatin1String("arm64")) return QStringLiteral("aarch64");
    if (cpu == QLatin1String("x86_64")) return QStringLiteral("x86_64");
    return cpu;
}

QString Backend::archFor(const QVariantList &arches) const
{
    QStringList a;
    for (const QVariant &v : arches) a << v.toString();
    if (a.isEmpty() || a.contains(arch())) return QString();
    // A phone runs x86-64 builds through FEX.
    if (arch() == QLatin1String("aarch64") && a.contains(QLatin1String("x86_64"))) return QStringLiteral("x86_64");
    return QStringLiteral("none");
}

void Backend::searchFlathub(const QString &query, const QString &category, int page)
{
    m_flathub.insert(QStringLiteral("loading"), true);
    m_flathub.insert(QStringLiteral("error"), QString());
    Q_EMIT changed();
    QString q = query.simplified();
    q.replace(QLatin1Char('\n'), QLatin1Char(' '));
    request(QStringLiteral("flathub:%1:%2:%3").arg(category).arg(std::max(1, page)).arg(q));
}

void Backend::refreshFlatpaks()
{
    if (!flatpakAvailable()) return;
    listFlatpaks();
}

void Backend::listFlatpaks()
{
    // Quick, and not one of the jobs: it only reads.
    auto *p = new QProcess(this);
    p->setWorkingDirectory(home());
    connect(p, &QProcess::finished, this, [this, p](int code, QProcess::ExitStatus status) {
        p->deleteLater();
        if (status != QProcess::NormalExit || code != 0) return;
        QVariantMap installed;
        const QStringList lines = QString::fromUtf8(p->readAllStandardOutput()).split(QLatin1Char('\n'), Qt::SkipEmptyParts);
        for (const QString &line : lines) {
            const QStringList f = line.split(QLatin1Char('\t'));
            if (f.isEmpty() || f[0].trimmed().isEmpty()) continue;
            installed.insert(f[0].trimmed(), QVariantMap{
                {QStringLiteral("version"), f.value(1).trimmed()},
                {QStringLiteral("arch"), f.value(2).trimmed()},
            });
        }
        m_flatpaks = installed;
        Q_EMIT changed();
    });
    p->start(QStringLiteral("flatpak"), {QStringLiteral("list"), QStringLiteral("--user"), QStringLiteral("--app"),
                                         QStringLiteral("--columns=application,version,arch")});
}

void Backend::installFlatpak(const QString &id, const QString &forArch)
{
    QStringList install{QStringLiteral("install"), QStringLiteral("--user"), QStringLiteral("-y"), QStringLiteral("--noninteractive")};
    if (!forArch.isEmpty()) install << QStringLiteral("--arch=") + forArch;
    install << QStringLiteral("flathub") << id;
    enqueue({QStringLiteral("flatpak:") + id,
             {{QStringLiteral("remote-add"), QStringLiteral("--user"), QStringLiteral("--if-not-exists"), QStringLiteral("flathub"), kFlathubRepo},
              install},
             {}, QStringLiteral("install ") + id, {}});
}

void Backend::removeFlatpak(const QString &id)
{
    enqueue({QStringLiteral("flatpak:") + id,
             {{QStringLiteral("uninstall"), QStringLiteral("--user"), QStringLiteral("-y"), QStringLiteral("--noninteractive"), id}},
             {}, QStringLiteral("remove ") + id, {}});
}

void Backend::updateFlatpaks()
{
    enqueue({QStringLiteral("flatpak:*"),
             {{QStringLiteral("update"), QStringLiteral("--user"), QStringLiteral("-y"), QStringLiteral("--noninteractive")}},
             {}, QStringLiteral("update the Flathub apps"), {}});
}

void Backend::launchFlatpak(const QString &id)
{
    QStringList args{QStringLiteral("run")};
    const QString a = m_flatpaks.value(id).toMap().value(QStringLiteral("arch")).toString();
    if (!a.isEmpty()) args << QStringLiteral("--arch=") + a;
    args << id;
    QProcess::startDetached(QStringLiteral("flatpak"), args, home());
}

bool Backend::isFlatpakFile(const QString &path)
{
    const QString p = path.toLower();
    return p.endsWith(QLatin1String(".flatpakref")) || p.endsWith(QLatin1String(".flatpakrepo")) || p.endsWith(QLatin1String(".flatpak"));
}

void Backend::inspectFlatpakFile(const QString &path)
{
    m_flatpakError.clear();
    QVariantMap f{{QStringLiteral("path"), path}};
    const QString lower = path.toLower();
    const QString kind = lower.endsWith(QLatin1String(".flatpakref")) ? QStringLiteral("ref")
        : lower.endsWith(QLatin1String(".flatpakrepo")) ? QStringLiteral("repo") : QStringLiteral("bundle");
    f.insert(QStringLiteral("kind"), kind);
    if (!QFileInfo(path).isFile()) {
        f.insert(QStringLiteral("invalid"), true);
        m_flatpakError = QStringLiteral("Can't open %1: there's no such file.").arg(QFileInfo(path).fileName());
    } else if (kind == QLatin1String("bundle")) {
        // A bundle is an OSTree commit; its name is in the file name, usually.
        f.insert(QStringLiteral("title"), QFileInfo(path).completeBaseName());
        f.insert(QStringLiteral("summary"), QStringLiteral("A Flatpak bundle: the whole app in one file."));
    } else {
        // Both are key files: [Flatpak Ref] or [Flatpak Repo].
        QSettings ini(path, QSettings::IniFormat);
        ini.beginGroup(kind == QLatin1String("ref") ? QStringLiteral("Flatpak Ref") : QStringLiteral("Flatpak Repo"));
        const QString name = ini.value(QStringLiteral("Name")).toString();
        const QString url = ini.value(QStringLiteral("Url")).toString();
        if (ini.status() != QSettings::NoError || url.isEmpty() || (kind == QLatin1String("ref") && name.isEmpty())) {
            f.insert(QStringLiteral("invalid"), true);
            m_flatpakError = QStringLiteral("Can't open %1: it isn't a Flatpak %2 file.")
                                 .arg(QFileInfo(path).fileName(), kind == QLatin1String("ref") ? QStringLiteral("app") : QStringLiteral("repository"));
        } else {
            const QString title = ini.value(QStringLiteral("Title")).toString();
            f.insert(QStringLiteral("name"), name);
            f.insert(QStringLiteral("title"), title.isEmpty() ? (name.isEmpty() ? QFileInfo(path).completeBaseName() : name) : title);
            f.insert(QStringLiteral("summary"), ini.value(QStringLiteral("Comment")).toString());
            f.insert(QStringLiteral("description"), ini.value(QStringLiteral("Description")).toString());
            f.insert(QStringLiteral("homepage"), ini.value(QStringLiteral("Homepage")).toString());
            f.insert(QStringLiteral("url"), url);
            f.insert(QStringLiteral("branch"), ini.value(QStringLiteral("Branch")).toString());
            f.insert(QStringLiteral("runtime"), ini.value(QStringLiteral("IsRuntime")).toString() == QLatin1String("true"));
            const QString icon = ini.value(QStringLiteral("Icon")).toString();
            f.insert(QStringLiteral("icon"), icon.startsWith(QLatin1String("https://")) ? icon : QString());
            if (kind == QLatin1String("ref"))
                f.insert(QStringLiteral("installed"), m_flatpaks.contains(name));
        }
    }
    m_flatpakFile = f;
    Q_EMIT changed();
}

void Backend::installFlatpakFile(const QString &path)
{
    if (m_flatpakFile.value(QStringLiteral("path")).toString() != path) inspectFlatpakFile(path);
    const QString kind = m_flatpakFile.value(QStringLiteral("kind")).toString();
    const QString name = m_flatpakFile.value(QStringLiteral("name")).toString();
    const QString key = QStringLiteral("file:") + path;
    auto done = [this, path](bool ok) {
        if (ok && m_flatpakFile.value(QStringLiteral("path")).toString() == path) {
            m_flatpakFile.insert(QStringLiteral("done"), true);
            Q_EMIT changed();
        }
    };
    const QStringList common{QStringLiteral("--user"), QStringLiteral("-y"), QStringLiteral("--noninteractive")};
    if (kind == QLatin1String("repo")) {
        // The repository's own name, from the file's: "foo.flatpakrepo" -> foo.
        QString remote = QFileInfo(path).completeBaseName().toLower();
        remote.replace(QRegularExpression(QStringLiteral("[^a-z0-9_-]+")), QStringLiteral("-"));
        if (remote.isEmpty()) remote = QStringLiteral("repo");
        enqueue({key, {{QStringLiteral("remote-add"), QStringLiteral("--user"), QStringLiteral("--if-not-exists"), QStringLiteral("--from"), remote, path}},
                 {}, QStringLiteral("add the repository"), done});
    } else if (kind == QLatin1String("ref")) {
        // The machine's own build first; one Flathub only makes for x86-64
        // fails ("No such ref", "not found"), then installs through FEX.
        QStringList first = QStringList{QStringLiteral("install")} + common + QStringList{QStringLiteral("--from"), path};
        QStringList x86 = QStringList{QStringLiteral("install")} + common + QStringList{QStringLiteral("--arch=x86_64"), QStringLiteral("--from"), path};
        enqueue({key, {first}, arch() == QLatin1String("aarch64") ? x86 : QStringList(), QStringLiteral("install ") + (name.isEmpty() ? QFileInfo(path).fileName() : name), done});
    } else {
        enqueue({key, {QStringList{QStringLiteral("install")} + common + QStringList{QStringLiteral("--bundle"), path}},
                 {}, QStringLiteral("install ") + QFileInfo(path).fileName(), done});
    }
}

void Backend::enqueue(Job job)
{
    m_flatpakError.clear();
    if (!flatpakAvailable()) {
        m_flatpakError = QStringLiteral("Couldn't %1: the flatpak command isn't on this desktop. Update DeskDroid, then try again.").arg(job.what);
        Q_EMIT changed();
        return;
    }
    m_flatpakBusy.insert(job.key, -1.0);
    m_jobs.append(std::move(job));
    Q_EMIT changed();
    if (!m_proc) nextJob();
}

void Backend::nextJob()
{
    if (m_jobs.isEmpty()) return;
    m_step = 0;
    m_retrying = false;
    m_output.clear();
    runStep();
}

void Backend::runStep()
{
    Job &job = m_jobs.first();
    const QStringList args = m_retrying ? job.retry : job.steps.at(m_step);
    m_proc = new QProcess(this);
    m_proc->setWorkingDirectory(home());
    m_proc->setProcessChannelMode(QProcess::MergedChannels);
    connect(m_proc, &QProcess::readyRead, this, [this] {
        const QString more = QString::fromUtf8(m_proc->readAll());
        m_output += more;
        if (m_output.size() > 64 * 1024) m_output = m_output.right(32 * 1024);
        // flatpak's progress: "Installing 2/3… ████▌  45%  2.1 MB/s". With
        // several refs the percentage restarts; it's the current one's.
        static const QRegularExpression percent(QStringLiteral("(\\d{1,3})%"));
        auto it = percent.globalMatch(more);
        int last = -1;
        while (it.hasNext()) last = it.next().captured(1).toInt();
        if (last >= 0 && last <= 100 && !m_jobs.isEmpty() && m_step == m_jobs.first().steps.size() - 1) {
            m_flatpakBusy.insert(m_jobs.first().key, last / 100.0);
            Q_EMIT changed();
        }
    });
    connect(m_proc, &QProcess::finished, this, [this](int code, QProcess::ExitStatus status) {
        m_output += QString::fromUtf8(m_proc->readAll());
        m_proc->deleteLater();
        m_proc = nullptr;
        Job &job = m_jobs.first();
        const bool ok = status == QProcess::NormalExit && code == 0;
        const bool last = m_retrying || m_step == job.steps.size() - 1;
        if (ok && !last) {
            ++m_step;
            m_output.clear();
            runStep();
            return;
        }
        if (!ok && last && !m_retrying && !job.retry.isEmpty()) {
            m_retrying = true;
            m_output.clear();
            runStep();
            return;
        }
        if (!ok)
            m_flatpakError = QStringLiteral("Couldn't %1: %2").arg(job.what, flatpakError(m_output));
        m_flatpakBusy.remove(job.key);
        auto done = job.done;
        m_jobs.removeFirst();
        if (done) done(ok);
        Q_EMIT changed();
        listFlatpaks();
        nextJob();
    });
    m_proc->start(QStringLiteral("flatpak"), args);
}

QString Backend::flatpakError(const QString &output) const
{
    // flatpak's own "error: ..." line, else its last words.
    QStringList lines = output.split(QRegularExpression(QStringLiteral("[\\r\\n]+")), Qt::SkipEmptyParts);
    for (auto it = lines.crbegin(); it != lines.crend(); ++it)
        if (it->trimmed().startsWith(QLatin1String("error:"), Qt::CaseInsensitive))
            return it->trimmed().mid(6).trimmed();
    while (!lines.isEmpty() && lines.last().trimmed().isEmpty()) lines.removeLast();
    const QString tail = lines.mid(std::max<qsizetype>(0, lines.size() - 2)).join(QLatin1Char(' ')).trimmed();
    return tail.isEmpty() ? QStringLiteral("flatpak stopped without saying why") : tail;
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

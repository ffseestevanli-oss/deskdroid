#include "backend.h"

#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QRegularExpression>
#include <QSettings>
#include <QUrl>

namespace
{
QString home()
{
    const QString h = qEnvironmentVariable("HOME");
    return h.isEmpty() ? QDir::homePath() : h;
}

// files/x86 (X86.kt), where deskdroid-steam and FEX live.
QString x86Dir()
{
    const QString d = qEnvironmentVariable("DESKDROID_X86");
    return d.isEmpty() ? home() + QStringLiteral("/x86") : d;
}

// Android's shell (deskdroid-steam is written for it); /bin/sh off the phone.
QString shell()
{
    static const QString sh = QFileInfo::exists(QStringLiteral("/system/bin/sh")) ? QStringLiteral("/system/bin/sh") : QStringLiteral("/bin/sh");
    return sh;
}

const char *const kDefaultSource = "https://github.com/ffseestevanli-oss/deskdroid/releases/download/fex-latest/";

// The steps of `deskdroid-steam --install`, as the share of the bar they take.
struct Stage {
    const char *match; // start of a line that begins the step
    double from, to;
    const char *label;
};
const Stage kStages[] = {
    {"Downloading FEX-Emu", 0.00, 0.04, "Fetching FEX-Emu"},
    {"Unzipping FEX-Emu", 0.00, 0.04, "Unzipping FEX-Emu"},
    {"Unpacking FEX-Emu", 0.04, 0.06, "Assembling FEX-Emu"},
    {"Downloading the x86 system", 0.06, 0.45, "Fetching the x86 system"},
    {"Unzipping the x86 system", 0.06, 0.45, "Unzipping the x86 system"},
    {"Unpacking the x86 system", 0.45, 0.80, "Assembling the x86 system"},
    {"The x86 system", 0.80, 0.80, "The x86 system is up to date"},
    {"Ready", 0.82, 0.82, "FEX-Emu is ready"},
    {"steam-x86: downloading Valve", 0.84, 0.96, "Fetching Steam"},
    {"steam-x86: Steam bootstrap installed", 0.98, 0.98, "Assembling Steam"},
    {"deskdroid-steam: Steam is installed", 1.0, 1.0, "Steam is installed!"},
};
} // namespace

Backend::Backend(QObject *parent)
    : QObject(parent)
{
    refresh();
}

QString Backend::script() const
{
    return x86Dir() + QStringLiteral("/bin/deskdroid-steam");
}

QString Backend::steamDir() const
{
    return home() + QStringLiteral("/.local/share/Steam");
}

QString Backend::configFile(const QString &name) const
{
    return home() + QStringLiteral("/.config/") + name;
}

bool Backend::skipped() const
{
    QSettings s(configFile(QStringLiteral("deskdroid-steam-assistant.conf")), QSettings::IniFormat);
    return s.value(QStringLiteral("skipped"), false).toBool();
}

void Backend::setSkipped(bool on)
{
    QDir().mkpath(home() + QStringLiteral("/.config"));
    QSettings s(configFile(QStringLiteral("deskdroid-steam-assistant.conf")), QSettings::IniFormat);
    s.setValue(QStringLiteral("skipped"), on);
    s.sync();
    Q_EMIT statusChanged();
}

bool Backend::welcomedBack() const
{
    QSettings s(configFile(QStringLiteral("deskdroid-steam-assistant.conf")), QSettings::IniFormat);
    return s.value(QStringLiteral("welcomedBack"), false).toBool();
}

void Backend::setWelcomedBack(bool on)
{
    QDir().mkpath(home() + QStringLiteral("/.config"));
    QSettings s(configFile(QStringLiteral("deskdroid-steam-assistant.conf")), QSettings::IniFormat);
    s.setValue(QStringLiteral("welcomedBack"), on);
    s.sync();
    Q_EMIT statusChanged();
}

QString Backend::fexSource() const
{
    QFile f(configFile(QStringLiteral("deskdroid-fex-url")));
    if (!f.open(QIODevice::ReadOnly))
        return QString();
    return QString::fromUtf8(f.readAll()).trimmed();
}

void Backend::setFexSource(const QString &url)
{
    const QString path = configFile(QStringLiteral("deskdroid-fex-url"));
    const QString text = url.trimmed();
    if (text.isEmpty() || text == QLatin1String(kDefaultSource)) {
        QFile::remove(path);
    } else {
        QDir().mkpath(home() + QStringLiteral("/.config"));
        QFile f(path);
        if (f.open(QIODevice::WriteOnly | QIODevice::Truncate))
            f.write(text.toUtf8() + '\n');
    }
    Q_EMIT fexSourceChanged();
}

QString Backend::defaultFexSource() const
{
    return QString::fromLatin1(kDefaultSource);
}

QString Backend::fexZip() const
{
    QFile f(configFile(QStringLiteral("deskdroid-fex-zip")));
    if (!f.open(QIODevice::ReadOnly))
        return QString();
    return QString::fromUtf8(f.readAll()).trimmed();
}

void Backend::setFexZip(const QString &path)
{
    // X86.kt reads the path and unzips FEX (and the x86 system, when it's in there) from it.
    const QString file = localPath(path.trimmed());
    const QString config = configFile(QStringLiteral("deskdroid-fex-zip"));
    if (file.isEmpty()) {
        QFile::remove(config);
    } else {
        QDir().mkpath(home() + QStringLiteral("/.config"));
        QFile f(config);
        if (f.open(QIODevice::WriteOnly | QIODevice::Truncate))
            f.write(file.toUtf8() + '\n');
    }
    Q_EMIT fexSourceChanged();
}

void Backend::refresh()
{
    // Cheap enough to check directly; the same tests as deskdroid-steam --status.
    const bool fex = QFileInfo::exists(x86Dir() + QStringLiteral("/ready")) && QFileInfo::exists(x86Dir() + QStringLiteral("/fex/bin/FEXInterpreter"));
    const bool steam = QFileInfo::exists(steamDir() + QStringLiteral("/steam.sh"));
    if (fex != m_fex || steam != m_steam) {
        m_fex = fex;
        m_steam = steam;
    }
    Q_EMIT statusChanged();
}

void Backend::start(const QStringList &args, bool install)
{
    if (busy())
        return;
    if (!QFileInfo::exists(script())) {
        Q_EMIT line(QStringLiteral("deskdroid-steam isn't in %1 yet: start the desktop again and retry.").arg(x86Dir() + QStringLiteral("/bin")));
        Q_EMIT finished(false, QStringLiteral("DeskDroid's Steam scripts are missing"));
        return;
    }
    delete m_proc;
    m_proc = new QProcess(this);
    m_proc->setProcessChannelMode(QProcess::MergedChannels);
    m_pending.clear();
    m_lastLine.clear();
    m_installing = install;
    m_stage = -1;
    connect(m_proc, &QProcess::readyRead, this, [this] {
        m_pending += m_proc->readAll();
        // curl's meter redraws with \r; each redraw counts as a line.
        for (;;) {
            int i = -1;
            for (int k = 0; k < m_pending.size(); k++) {
                if (m_pending[k] == '\n' || m_pending[k] == '\r') {
                    i = k;
                    break;
                }
            }
            if (i < 0)
                break;
            const QString text = QString::fromUtf8(m_pending.left(i));
            m_pending.remove(0, i + 1);
            if (!text.trimmed().isEmpty())
                onLine(text);
        }
    });
    connect(m_proc, &QProcess::finished, this, [this](int code, QProcess::ExitStatus status) {
        if (!m_pending.trimmed().isEmpty())
            onLine(QString::fromUtf8(m_pending));
        m_pending.clear();
        const bool ok = status == QProcess::NormalExit && code == 0;
        refresh();
        Q_EMIT busyChanged();
        QString message = m_lastLine;
        message.remove(QRegularExpression(QStringLiteral("^(deskdroid-steam|steam-x86|failed): *")));
        Q_EMIT finished(ok, message);
    });
    connect(m_proc, &QProcess::errorOccurred, this, [this](QProcess::ProcessError e) {
        if (e == QProcess::FailedToStart) {
            Q_EMIT line(QStringLiteral("couldn't start %1: %2").arg(script(), m_proc->errorString()));
            Q_EMIT busyChanged();
            Q_EMIT finished(false, m_proc->errorString());
        }
    });
    m_proc->start(shell(), QStringList{script()} + args);
    Q_EMIT busyChanged();
}

void Backend::onLine(const QString &text)
{
    // curl's meter redraws a line many times a second: the log keeps every tenth percent.
    static const QRegularExpression curl(QStringLiteral("^\\s*(\\d{1,3})\\s+[\\d.]+[kMG]?\\s+(\\d{1,3})\\s"));
    const auto meter = curl.match(text);
    if (meter.hasMatch()) {
        const int p = meter.captured(1).toInt();
        if (p / 10 != m_lastMeter / 10 || p == 100) {
            m_lastMeter = p;
            Q_EMIT line(text);
        }
    } else {
        m_lastLine = text.trimmed();
        Q_EMIT line(text);
    }
    if (!m_installing)
        return;
    const QString t = text.trimmed();
    for (int i = 0; i < int(sizeof kStages / sizeof kStages[0]); i++) {
        if (t.startsWith(QLatin1String(kStages[i].match))) {
            m_stage = i;
            m_lastMeter = -10;
            Q_EMIT progress(kStages[i].from, QString::fromLatin1(kStages[i].label));
            return;
        }
    }
    if (m_stage < 0)
        return;
    // "  40% of 1200 MB" (X86.kt's downloads and unpacking), or curl's meter
    // while Steam downloads (its first number is the percent).
    static const QRegularExpression percent(QStringLiteral("^\\s*(\\d{1,3})%"));
    int p = -1;
    const auto m = percent.match(text);
    if (m.hasMatch())
        p = m.captured(1).toInt();
    else if (meter.hasMatch() && QString::fromLatin1(kStages[m_stage].match).startsWith(QLatin1String("steam-x86")))
        p = meter.captured(1).toInt();
    if (p < 0 || p > 100)
        return;
    const Stage &s = kStages[m_stage];
    Q_EMIT progress(s.from + (s.to - s.from) * p / 100.0, QString::fromLatin1(s.label));
}

void Backend::install()
{
    Q_EMIT progress(0, QStringLiteral("Getting started"));
    start({QStringLiteral("--install")}, true);
}

void Backend::runTool(const QString &name)
{
    start({QStringLiteral("--tool"), name}, false);
}

void Backend::cancel()
{
    if (busy())
        m_proc->kill();
}

void Backend::detached(const QStringList &args)
{
    QProcess::startDetached(shell(), QStringList{script()} + args, home());
}

void Backend::launchSteam(const QString &url)
{
    detached(url.isEmpty() ? QStringList{} : QStringList{url});
}

QString Backend::localPath(const QString &url) const
{
    const QUrl u(url);
    return u.isLocalFile() ? u.toLocalFile() : url;
}

void Backend::runX86(const QString &file)
{
    detached({QStringLiteral("--run-x86"), localPath(file)});
}

void Backend::runWindows(const QString &file)
{
    detached({QStringLiteral("--run-windows"), localPath(file)});
}

void Backend::wineTool(const QString &tool, const QString &prefix)
{
    QStringList args{QStringLiteral("--wine-tool"), tool};
    if (!prefix.isEmpty())
        args << prefix;
    detached(args);
}

void Backend::openFolder(const QString &path)
{
    // Dolphin is bin/dolphin on the desktop's PATH.
    QProcess::startDetached(QStringLiteral("dolphin"), {path});
}

bool Backend::removeFolder(const QString &path)
{
    // Only prefixes this assistant lists.
    const QString canon = QFileInfo(path).absoluteFilePath();
    if (!canon.startsWith(steamDir() + QStringLiteral("/steamapps/compatdata/")) && !canon.startsWith(home() + QStringLiteral("/.local/share/deskdroid-wine/")))
        return false;
    return QDir(canon).removeRecursively();
}

static QString acfValue(const QString &text, const QString &key)
{
    const QRegularExpression re(QStringLiteral("\"%1\"\\s+\"([^\"]*)\"").arg(QRegularExpression::escape(key)), QRegularExpression::CaseInsensitiveOption);
    const auto m = re.match(text);
    return m.hasMatch() ? m.captured(1) : QString();
}

QVariantList Backend::games() const
{
    QVariantList out;
    QDir dir(steamDir() + QStringLiteral("/steamapps"));
    const auto files = dir.entryInfoList({QStringLiteral("appmanifest_*.acf")}, QDir::Files, QDir::Name);
    for (const QFileInfo &fi : files) {
        QFile f(fi.filePath());
        if (!f.open(QIODevice::ReadOnly))
            continue;
        const QString text = QString::fromUtf8(f.readAll());
        const QString name = acfValue(text, QStringLiteral("name"));
        // Steam's own runtimes and Proton show as tools, not games.
        const bool tool = name.startsWith(QLatin1String("Proton")) || name.startsWith(QLatin1String("Steam Linux Runtime")) || name.startsWith(QLatin1String("Steamworks Common"));
        out.append(QVariantMap{
            {QStringLiteral("appid"), acfValue(text, QStringLiteral("appid"))},
            {QStringLiteral("name"), name.isEmpty() ? fi.baseName() : name},
            {QStringLiteral("size"), acfValue(text, QStringLiteral("SizeOnDisk")).toLongLong()},
            {QStringLiteral("tool"), tool},
        });
    }
    return out;
}

QVariantList Backend::prefixes() const
{
    QVariantList out;
    QHash<QString, QString> names;
    for (const QVariant &g : games()) {
        const auto m = g.toMap();
        names.insert(m.value(QStringLiteral("appid")).toString(), m.value(QStringLiteral("name")).toString());
    }
    QDir compat(steamDir() + QStringLiteral("/steamapps/compatdata"));
    for (const QFileInfo &fi : compat.entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name)) {
        const QString id = fi.fileName();
        out.append(QVariantMap{
            {QStringLiteral("name"), names.value(id, id == QLatin1String("0") ? QStringLiteral("Steam (shared)") : QStringLiteral("App %1").arg(id))},
            {QStringLiteral("path"), fi.absoluteFilePath()},
            {QStringLiteral("appid"), id},
            {QStringLiteral("kind"), QStringLiteral("steam")},
        });
    }
    QDir own(home() + QStringLiteral("/.local/share/deskdroid-wine"));
    for (const QFileInfo &fi : own.entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name)) {
        out.append(QVariantMap{
            {QStringLiteral("name"), fi.fileName() == QLatin1String("default") ? QStringLiteral("Windows apps (DeskDroid)") : fi.fileName()},
            {QStringLiteral("path"), fi.absoluteFilePath()},
            {QStringLiteral("appid"), QString()},
            {QStringLiteral("kind"), QStringLiteral("deskdroid")},
        });
    }
    return out;
}

bool Backend::hasProton() const
{
    QDir common(steamDir() + QStringLiteral("/steamapps/common"));
    for (const QFileInfo &fi : common.entryInfoList({QStringLiteral("Proton*")}, QDir::Dirs))
        if (QFileInfo::exists(fi.filePath() + QStringLiteral("/proton")))
            return true;
    return false;
}

QString Backend::logTail(const QString &which, int lines) const
{
    QString name = QStringLiteral("install.log");
    if (which == QLatin1String("steam"))
        name = QStringLiteral("steam.log");
    else if (which == QLatin1String("apps"))
        name = QStringLiteral("apps.log");
    QFile f(x86Dir() + QLatin1Char('/') + name);
    if (!f.open(QIODevice::ReadOnly))
        return QString();
    if (f.size() > 64 * 1024)
        f.seek(f.size() - 64 * 1024);
    QStringList all = QString::fromUtf8(f.readAll()).split(QLatin1Char('\n'));
    if (all.size() > lines)
        all = all.mid(all.size() - lines);
    return all.join(QLatin1Char('\n'));
}

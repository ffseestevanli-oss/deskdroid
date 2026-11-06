// DeskDroid: added to the end of plasma-workspace's applets/kicker/processrunner.cpp
// by add-to-workspace.py, for Start 7 Plus
// (native/plasma/shell/plasmoids/com.steventechno.start7plus).
//
// On Linux the widget lists apps with a Python script and starts apps, opens
// files and runs commands through sh. Android has neither Python nor /bin/sh,
// so Kicker's ProcessRunner, a QML type the widget already imports, does these
// here instead, through KIO and KDE's app database, like Kickoff. The widget
// uses them when they are there and its own scripts otherwise.

#include <KApplicationTrader>
#include <KIO/ApplicationLauncherJob>
#include <KIO/JobUiDelegateFactory>
#include <KIO/OpenUrlJob>
#include <KServiceGroup>
#include <KUser>
#include <QDeadlineTimer>
#include <QDir>
#include <QDirIterator>
#include <QFileInfo>
#include <QStandardPaths>
#include <QUrl>
#include <QVariantMap>
#include <algorithm>
#include <sessionmanagement.h>

static QString deskdroidEntryPath(const KService::Ptr &service)
{
    const QString path = service->entryPath();
    if (QFileInfo(path).isAbsolute()) {
        return path;
    }
    const QString found = QStandardPaths::locate(QStandardPaths::ApplicationsLocation, path);
    return found.isEmpty() ? path : found;
}

static QVariantMap deskdroidApp(const KService::Ptr &service)
{
    const QString path = deskdroidEntryPath(service);
    QString icon = service->icon();
    if (icon.isEmpty()) {
        icon = QStringLiteral("application-x-executable");
    } else if (icon.startsWith(QLatin1Char('/'))) {
        icon = QStringLiteral("file://") + icon;
    }
    return {{QStringLiteral("id"), QFileInfo(path).fileName()},
            {QStringLiteral("name"), service->name()},
            {QStringLiteral("icon"), icon},
            {QStringLiteral("path"), path},
            {QStringLiteral("kw"), (service->genericName() + QLatin1Char(' ') + service->keywords().join(QLatin1Char(' '))).trimmed()}};
}

// The apps in a menu folder and its subfolders, in one list (as the script did).
static void deskdroidCollect(const KServiceGroup::Ptr &group, QVariantList &apps, QStringList &seen)
{
    const KServiceGroup::List list = group->entries(true /* sorted */, true /* excludeNoDisplay */, false, false);
    for (const KSycocaEntry::Ptr &p : list) {
        if (p->isType(KST_KService)) {
            const KService::Ptr service(static_cast<KService *>(p.data()));
            if (service->noDisplay() || seen.contains(service->storageId())) {
                continue;
            }
            seen << service->storageId();
            apps << deskdroidApp(service);
        } else if (p->isType(KST_KServiceGroup)) {
            const KServiceGroup::Ptr sub(static_cast<KServiceGroup *>(p.data()));
            if (!sub->noDisplay()) {
                deskdroidCollect(sub, apps, seen);
            }
        }
    }
}

// The application menu's top folders (Development, Games, Android Apps...) as
// [{name, icon, apps: [{id, name, icon, path, kw}]}], with apps outside any
// folder last, in "Other": the shape Start 7 Plus's apps.py prints.
QVariantList ProcessRunner::appMenu()
{
    QVariantList folders;
    QVariantList loose;
    QStringList seenLoose;
    const KServiceGroup::Ptr root = KServiceGroup::root();
    if (!root || !root->isValid()) {
        return folders;
    }
    const KServiceGroup::List list = root->entries(true, true, false, false);
    for (const KSycocaEntry::Ptr &p : list) {
        if (p->isType(KST_KServiceGroup)) {
            const KServiceGroup::Ptr group(static_cast<KServiceGroup *>(p.data()));
            if (group->noDisplay()) {
                continue;
            }
            QVariantList apps;
            QStringList seen;
            deskdroidCollect(group, apps, seen);
            if (!apps.isEmpty()) {
                folders << QVariantMap{{QStringLiteral("name"), group->caption()},
                                       {QStringLiteral("icon"), group->icon().isEmpty() ? QStringLiteral("folder") : group->icon()},
                                       {QStringLiteral("apps"), apps}};
            }
        } else if (p->isType(KST_KService)) {
            const KService::Ptr service(static_cast<KService *>(p.data()));
            if (!service->noDisplay() && !seenLoose.contains(service->storageId())) {
                seenLoose << service->storageId();
                loose << deskdroidApp(service);
            }
        }
    }
    std::sort(folders.begin(), folders.end(), [](const QVariant &a, const QVariant &b) {
        return a.toMap().value(QStringLiteral("name")).toString().localeAwareCompare(b.toMap().value(QStringLiteral("name")).toString()) < 0;
    });
    if (!loose.isEmpty()) {
        folders << QVariantMap{{QStringLiteral("name"), QStringLiteral("Other")},
                               {QStringLiteral("icon"), QStringLiteral("applications-other")},
                               {QStringLiteral("apps"), loose}};
    }
    return folders;
}

// An app by its desktop file's path, or by its id (org.kde.dolphin.desktop).
bool ProcessRunner::runApp(const QString &pathOrId)
{
    KService::Ptr service;
    if (pathOrId.startsWith(QLatin1Char('/'))) {
        service = KService::serviceByDesktopPath(pathOrId);
        if (!service && QFileInfo::exists(pathOrId)) {
            service = KService::Ptr(new KService(pathOrId));
        }
    } else {
        service = KService::serviceByStorageId(pathOrId);
    }
    if (!service || !service->isValid()) {
        qWarning() << "Start 7 Plus: no app" << pathOrId;
        return false;
    }
    auto *job = new KIO::ApplicationLauncherJob(service);
    job->setUiDelegate(new KNotificationJobUiDelegate(KJobUiDelegate::AutoHandlingEnabled));
    job->start();
    return true;
}

// A file, folder or web address, in its default app.
void ProcessRunner::openUrl(const QString &url)
{
    auto *job = new KIO::OpenUrlJob(QUrl::fromUserInput(url, QDir::homePath(), QUrl::AssumeLocalFile));
    job->setUiDelegate(KIO::createDefaultJobUiDelegate(KJobUiDelegate::AutoHandlingEnabled, nullptr));
    job->setRunExecutables(false);
    job->start();
}

// A plain command: a program and its arguments, no shell.
void ProcessRunner::runCommand(const QString &command)
{
    auto *job = new KIO::CommandLauncherJob(command);
    job->setUiDelegate(new KNotificationJobUiDelegate(KJobUiDelegate::AutoErrorHandlingEnabled));
    job->start();
}

// Files and folders in the home folder whose names hold every word, as
// search.py: hidden ones skipped, 8 folders deep, for at most a second.
QVariantMap ProcessRunner::searchFiles(const QString &query)
{
    const QStringList terms = query.toLower().split(QLatin1Char(' '), Qt::SkipEmptyParts);
    QVariantList files;
    if (!terms.isEmpty()) {
        const QString home = QDir::homePath();
        const int homeDepth = home.count(QLatin1Char('/'));
        const QDeadlineTimer deadline(1000);
        QList<QFileInfo> found;
        QDirIterator it(home, QDir::AllEntries | QDir::NoDotAndDotDot, QDirIterator::Subdirectories);
        while (it.hasNext() && found.size() < 300 && !deadline.hasExpired()) {
            const QFileInfo info = it.nextFileInfo();
            if (info.filePath().count(QLatin1Char('/')) - homeDepth > 8) {
                continue;
            }
            const QString low = info.fileName().toLower();
            if (std::all_of(terms.cbegin(), terms.cend(), [&low](const QString &term) {
                    return low.contains(term);
                })) {
                found << info;
            }
        }
        const QString first = terms.first();
        std::sort(found.begin(), found.end(), [&first](const QFileInfo &a, const QFileInfo &b) {
            const QString la = a.fileName().toLower(), lb = b.fileName().toLower();
            const bool sa = la.startsWith(first), sb = lb.startsWith(first);
            if (sa != sb) {
                return sa;
            }
            return la.size() != lb.size() ? la.size() < lb.size() : la < lb;
        });
        for (qsizetype i = 0; i < found.size() && i < 25; ++i) {
            files << QVariantMap{{QStringLiteral("name"), found[i].fileName()},
                                 {QStringLiteral("path"), found[i].filePath()},
                                 {QStringLiteral("dir"), found[i].isDir()}};
        }
    }
    return {{QStringLiteral("query"), query}, {QStringLiteral("files"), files}};
}

// [display name, account picture or ""], as userinfo.py.
QStringList ProcessRunner::userInfo()
{
    const KUser user(KUser::UseRealUserID);
    const QString name = user.property(KUser::FullName).toString();
    QString face = user.faceIconPath();
    if (!face.isEmpty() && !QFileInfo(face).isFile()) {
        face.clear();
    }
    return {name.isEmpty() ? user.loginName() : name, face};
}

// The default web browser's desktop file name, as xdg-settings prints it.
QString ProcessRunner::defaultBrowser()
{
    const KService::Ptr service = KApplicationTrader::preferredService(QStringLiteral("x-scheme-handler/https"));
    return service ? QFileInfo(deskdroidEntryPath(service)).fileName() : QString();
}

// The power and session buttons, as Kickoff's: Shut Down, Restart and Log
// Off show the logout screen (End Session; its Restart and Power Off open
// Android's power menu).
void ProcessRunner::session(const QString &action)
{
    static SessionManagement *sm = new SessionManagement;
    if (action == QLatin1String("lock")) {
        sm->lock();
    } else if (action == QLatin1String("suspend")) {
        sm->suspend();
    } else if (action == QLatin1String("hibernate")) {
        sm->hibernate();
    } else {
        sm->requestLogoutPrompt();
    }
}

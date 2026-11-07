/*
 *   SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
 */
#include "DeskDroidBackend.h"
#include "DeskDroidResource.h"
#include "DeskDroidTransaction.h"

#include <AppStreamQt/pool.h>
#include <KLocalizedString>
#include <KPluginFactory>
#include <QDir>
#include <QFileInfo>
#include <QStandardPaths>
#include <QTimer>
#include <Transaction/Transaction.h>
#include <appstream/AppStreamConcurrentPool.h>
#include <appstream/AppStreamUtils.h>
#include <appstream/OdrsReviewsBackend.h>
#include <resources/StandardBackendUpdater.h>

DISCOVER_BACKEND_PLUGIN(DeskDroidBackend)

using namespace Qt::StringLiterals;

static const auto s_flathubUrl = u"https://dl.flathub.org/repo/flathub.flatpakrepo"_s;

DeskDroidBackend::DeskDroidBackend(QObject *parent)
    : AbstractResourcesBackend(parent)
    , m_updater(new StandardBackendUpdater(this))
    , m_reviews(OdrsReviewsBackend::global())
{
    connect(m_updater, &StandardBackendUpdater::updatesCountChanged, this, &DeskDroidBackend::updatesCountChanged);
    connect(m_reviews.data(), &OdrsReviewsBackend::ratingsReady, this, [this] {
        QList<AbstractResource *> all;
        for (auto r : std::as_const(m_resources)) {
            all += r;
        }
        m_reviews->emitRatingFetched(this, all);
    });

    m_flatpak = qEnvironmentVariable("DESKDROID_FLATPAK");
    if (m_flatpak.isEmpty()) {
        m_flatpak = QStandardPaths::findExecutable(u"flatpak"_s);
    }
    if (m_flatpak.isEmpty()) {
        m_error = i18n("The flatpak command isn't installed.");
        return;
    }

    if (QFileInfo::exists(appstreamDir() + u"/appstream.xml.gz"_s) || QFileInfo::exists(appstreamDir() + u"/appstream.xml"_s)) {
        loadPool();
        // Fresh catalog in the background; the old one shows meanwhile.
        QTimer::singleShot(0, this, &DeskDroidBackend::checkForUpdates);
    } else {
        // First start: add Flathub and fetch its catalog.
        setFetching(true);
        runSteps({{u"remote-add"_s, u"--user"_s, u"--if-not-exists"_s, u"flathub"_s, s_flathubUrl},
                  {u"update"_s, u"--user"_s, u"--appstream"_s, u"flathub"_s}},
                 [this](bool ok) {
                     if (!ok) {
                         m_error = i18n("Couldn't reach Flathub. Check the network connection, then try again.");
                         Q_EMIT inlineMessageChanged(QSharedPointer<InlineMessage>(explainDysfunction()));
                     }
                     loadPool();
                     setFetching(false);
                 });
    }
}

DeskDroidBackend::~DeskDroidBackend()
{
    m_threadPool.waitForDone(2000);
}

QString DeskDroidBackend::installationDir() const
{
    QString dir = qEnvironmentVariable("FLATPAK_USER_DIR");
    if (dir.isEmpty()) {
        QString files = qEnvironmentVariable("DESKDROID_FILES");
        if (files.isEmpty()) {
            files = u"/data/data/io.deskdroid.app/files"_s;
        }
        dir = files + u"/flatpak"_s;
    }
    return dir;
}

QString DeskDroidBackend::arch() const
{
    const QString a = qEnvironmentVariable("DESKDROID_FLATPAK_ARCH");
    if (!a.isEmpty()) {
        return a;
    }
#if defined(__aarch64__)
    return u"aarch64"_s;
#else
    return u"x86_64"_s;
#endif
}

QString DeskDroidBackend::appstreamDir() const
{
    return installationDir() + u"/appstream/flathub/"_s + arch() + u"/active"_s;
}

void DeskDroidBackend::startFlatpak(QProcess *process, const QStringList &args) const
{
    process->start(m_flatpak, args);
}

void DeskDroidBackend::runApp(const QString &id) const
{
    QProcess::startDetached(m_flatpak, {u"run"_s, id});
}

void DeskDroidBackend::runSteps(const QList<QStringList> &steps, std::function<void(bool)> done)
{
    if (steps.isEmpty()) {
        done(true);
        return;
    }
    auto p = new QProcess(this);
    p->setProcessChannelMode(QProcess::MergedChannels);
    connect(p, &QProcess::finished, this, [this, p, steps, done](int code, QProcess::ExitStatus st) {
        p->deleteLater();
        if (st != QProcess::NormalExit || code != 0) {
            qWarning() << "flatpak" << steps.first() << "failed:" << p->readAll().right(400);
            done(false);
            return;
        }
        runSteps(steps.mid(1), done);
    });
    connect(p, &QProcess::errorOccurred, this, [p, done](QProcess::ProcessError e) {
        if (e == QProcess::FailedToStart) {
            p->deleteLater();
            done(false);
        }
    });
    startFlatpak(p, steps.first());
}

void DeskDroidBackend::setFetching(bool fetching)
{
    m_fetching += fetching ? 1 : -1;
    Q_EMIT fetchingUpdatesProgressChanged();
    if (m_fetching == 0) {
        Q_EMIT contentsChanged();
    }
}

void DeskDroidBackend::loadPool()
{
    auto pool = new AppStream::Pool;
    pool->setLoadStdDataLocations(false);
    pool->addExtraDataLocation(appstreamDir(), AppStream::Metadata::FormatStyleCatalog);
    m_pool.reset(new AppStream::ConcurrentPool);
    m_pool->reset(pool, &m_threadPool);
    setFetching(true);
    connect(m_pool.get(), &AppStream::ConcurrentPool::loadFinished, this, &DeskDroidBackend::poolLoaded);
    m_pool->loadAsync();
}

void DeskDroidBackend::poolLoaded(bool success)
{
    if (!success) {
        qWarning() << "DeskDroid: couldn't load Flathub's catalog" << m_pool->lastError();
    }
    const auto components = m_pool->get()->componentsByKind(AppStream::Component::KindDesktopApp);
    for (const auto &c : components) {
        auto r = new DeskDroidResource(c, this);
        const QString id = r->flatpakId();
        if (m_resources.contains(id)) {
            delete r;
            continue;
        }
        m_resources.insert(id, r);
        connect(r, &DeskDroidResource::stateChanged, this, &DeskDroidBackend::updatesCountChanged);
    }
    refreshInstalled();
    setFetching(false);
}

void DeskDroidBackend::refreshInstalled()
{
    auto list = new QProcess(this);
    connect(list, &QProcess::finished, this, [this, list] {
        list->deleteLater();
        const QByteArray installed = list->readAllStandardOutput();
        auto updates = new QProcess(this);
        connect(updates, &QProcess::finished, this, [this, updates, installed] {
            updates->deleteLater();
            applyInstalled(installed, updates->readAllStandardOutput());
        });
        startFlatpak(updates, {u"remote-ls"_s, u"--user"_s, u"--updates"_s, u"--app"_s, u"--columns=application"_s});
    });
    startFlatpak(list, {u"list"_s, u"--user"_s, u"--app"_s, u"--columns=application,version"_s});
}

void DeskDroidBackend::applyInstalled(const QByteArray &list, const QByteArray &updates)
{
    QHash<QString, QString> installed;
    for (const auto &line : list.split('\n')) {
        const auto cols = QString::fromUtf8(line).split(u'\t');
        if (!cols.value(0).trimmed().isEmpty()) {
            installed.insert(cols.value(0).trimmed(), cols.value(1).trimmed());
        }
    }
    QSet<QString> upgradeable;
    for (const auto &line : updates.split('\n')) {
        const QString id = QString::fromUtf8(line).trimmed();
        if (!id.isEmpty()) {
            upgradeable.insert(id);
        }
    }
    for (auto it = m_resources.begin(); it != m_resources.end(); ++it) {
        auto r = it.value();
        if (!installed.contains(it.key())) {
            r->setState(AbstractResource::None);
            continue;
        }
        r->setInstalledVersion(installed.value(it.key()));
        r->setState(upgradeable.contains(it.key()) ? AbstractResource::Upgradeable : AbstractResource::Installed);
    }
    Q_EMIT updatesCountChanged();
}

int DeskDroidBackend::updatesCount() const
{
    return m_updater->updatesCount();
}

AbstractBackendUpdater *DeskDroidBackend::backendUpdater() const
{
    return m_updater;
}

AbstractReviewsBackend *DeskDroidBackend::reviewsBackend() const
{
    return m_reviews.data();
}

ResultsStream *DeskDroidBackend::search(const AbstractResourcesBackend::Filters &filter)
{
    QVector<StreamResult> ret;
    if (!filter.resourceUrl.isEmpty()) {
        if (filter.resourceUrl.scheme() == "appstream"_L1) {
            const auto ids = AppStreamUtils::appstreamIds(filter.resourceUrl);
            for (auto r : std::as_const(m_resources)) {
                for (const auto &id : ids) {
                    if (r->appstreamId() == id || r->flatpakId() == id || r->appstreamId() == id + ".desktop"_L1) {
                        ret += r;
                    }
                }
            }
        }
        return new ResultsStream(u"DeskDroidStream-url"_s, ret);
    }

    auto wanted = [&filter](DeskDroidResource *r) {
        if (r->type() != AbstractResource::Application && filter.state != AbstractResource::Upgradeable) {
            return false;
        }
        return filter.shouldFilter(r);
    };

    if (!filter.search.isEmpty() && m_pool) {
        // AppStream's own search ranks by name, keywords and summary.
        const auto found = m_pool->get()->search(filter.search);
        QSet<DeskDroidResource *> seen;
        for (const auto &c : found) {
            QString id = c.bundle(AppStream::Bundle::KindFlatpak).id().section(u'/', 1, 1);
            if (id.isEmpty()) {
                id = c.id();
                if (id.endsWith(".desktop"_L1)) {
                    id.chop(8);
                }
            }
            auto r = m_resources.value(id);
            if (r && !seen.contains(r) && wanted(r)) {
                seen.insert(r);
                ret += r;
            }
        }
    } else if (filter.search.isEmpty()) {
        for (auto r : std::as_const(m_resources)) {
            if (wanted(r)) {
                ret += r;
            }
        }
    }
    return new ResultsStream(u"DeskDroidStream"_s, ret);
}

bool DeskDroidBackend::isValid() const
{
    return !m_flatpak.isEmpty();
}

Transaction *DeskDroidBackend::installApplication(AbstractResource *app, const AddonList &addons)
{
    Q_UNUSED(addons)
    return installApplication(app);
}

Transaction *DeskDroidBackend::installApplication(AbstractResource *app)
{
    return new DeskDroidTransaction(static_cast<DeskDroidResource *>(app), Transaction::InstallRole);
}

Transaction *DeskDroidBackend::removeApplication(AbstractResource *app)
{
    return new DeskDroidTransaction(static_cast<DeskDroidResource *>(app), Transaction::RemoveRole);
}

void DeskDroidBackend::checkForUpdates()
{
    if (m_fetching > 0 || m_flatpak.isEmpty()) {
        return;
    }
    setFetching(true);
    runSteps({{u"remote-add"_s, u"--user"_s, u"--if-not-exists"_s, u"flathub"_s, s_flathubUrl},
              {u"update"_s, u"--user"_s, u"--appstream"_s, u"flathub"_s}},
             [this](bool ok) {
                 if (ok) {
                     loadPool();
                 } else {
                     refreshInstalled();
                 }
                 setFetching(false);
             });
}

QString DeskDroidBackend::displayName() const
{
    return u"Flathub"_s;
}

bool DeskDroidBackend::hasApplications() const
{
    return true;
}

int DeskDroidBackend::fetchingUpdatesProgress() const
{
    return m_fetching > 0 ? 50 : 100;
}

InlineMessage *DeskDroidBackend::explainDysfunction() const
{
    if (!m_error.isEmpty()) {
        return new InlineMessage(InlineMessage::Error, u"dialog-error"_s, m_error);
    }
    return AbstractResourcesBackend::explainDysfunction();
}

#include "DeskDroidBackend.moc"
#include "moc_DeskDroidBackend.cpp"

/*
 *   DeskDroid: Flathub in Discover through DeskDroid's flatpak command.
 *
 *   Discover's own Flatpak backend links libflatpak and asks its system
 *   helper over D-Bus, which DeskDroid has neither of. This one reads
 *   Flathub's AppStream catalog, which "flatpak update --appstream" keeps in
 *   the user installation, and runs the flatpak command for the rest.
 *
 *   SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
 */
#pragma once

#include <QHash>
#include <QPointer>
#include <QSharedPointer>
#include <QProcess>
#include <QThreadPool>
#include <memory>
#include <resources/AbstractResourcesBackend.h>

namespace AppStream
{
class ConcurrentPool;
}
class DeskDroidResource;
class StandardBackendUpdater;
class OdrsReviewsBackend;

class DeskDroidBackend : public AbstractResourcesBackend
{
    Q_OBJECT
public:
    explicit DeskDroidBackend(QObject *parent = nullptr);
    ~DeskDroidBackend() override;

    int updatesCount() const override;
    AbstractBackendUpdater *backendUpdater() const override;
    AbstractReviewsBackend *reviewsBackend() const override;
    ResultsStream *search(const AbstractResourcesBackend::Filters &filter) override;
    bool isValid() const override;
    Transaction *installApplication(AbstractResource *app, const AddonList &addons) override;
    Transaction *installApplication(AbstractResource *app) override;
    Transaction *removeApplication(AbstractResource *app) override;
    void checkForUpdates() override;
    QString displayName() const override;
    bool hasApplications() const override;
    int fetchingUpdatesProgress() const override;
    InlineMessage *explainDysfunction() const override;

    QString installationDir() const;
    QString appstreamDir() const;
    QString arch() const;
    void startFlatpak(QProcess *process, const QStringList &args) const;
    void runApp(const QString &id) const;
    // Reads "flatpak list" and "flatpak remote-ls --updates" again.
    void refreshInstalled();

private:
    void setFetching(bool fetching);
    void loadPool();
    void poolLoaded(bool success);
    void runSteps(const QList<QStringList> &steps, std::function<void(bool)> done);
    void applyInstalled(const QByteArray &list, const QByteArray &updates);

    QString m_flatpak;
    QThreadPool m_threadPool;
    std::unique_ptr<AppStream::ConcurrentPool> m_pool;
    QHash<QString, DeskDroidResource *> m_resources; // by flatpak id
    StandardBackendUpdater *m_updater;
    QSharedPointer<OdrsReviewsBackend> m_reviews;
    int m_fetching = 0;
    QString m_error;
};

/*
 *   DeskDroid: one Flathub app in Discover, from Flathub's AppStream catalog.
 *   SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
 */
#pragma once

#include <AppStreamQt/component.h>
#include <QIcon>
#include <optional>
#include <resources/AbstractResource.h>

class DeskDroidBackend;

class DeskDroidResource : public AbstractResource
{
    Q_OBJECT
public:
    DeskDroidResource(const AppStream::Component &component, DeskDroidBackend *backend);

    DeskDroidBackend *deskdroidBackend() const;
    const AppStream::Component &component() const
    {
        return m_appdata;
    }
    // app/<id>/<arch>/<branch>, as flatpak install takes it.
    QString ref() const;
    QString flatpakId() const;

    void setState(State state);
    void setInstalledVersion(const QString &version);

    QString packageName() const override;
    QString name() const override;
    QString comment() override;
    QVariant icon() const override;
    bool canExecute() const override;
    void invokeApplication() const override;
    State state() override;
    bool hasCategory(const QString &category) const override;
    Type type() const override;
    quint64 size() override;
    QString sizeDescription() override;
    QJsonArray licenses() override;
    QString installedVersion() const override;
    QString availableVersion() const override;
    QString longDescription() override;
    QString origin() const override;
    QString displayOrigin() const override;
    QString section() override;
    QString author() const override;
    QList<PackageState> addonsInformation() override;
    QString sourceIcon() const override;
    QDate releaseDate() const override;
    void fetchChangelog() override;
    void fetchScreenshots() override;
    QString appstreamId() const override;
    QUrl homepage() override;
    QUrl helpURL() override;
    QUrl bugURL() override;
    QUrl donationURL() override;
    QUrl contributeURL() override;
    QStringList mimetypes() const override;
    QStringList extends() const override;
    QString contentRatingDescription() const override;
    uint contentRatingMinimumAge() const override;
    QUrl url() const override;
    [[nodiscard]] bool hasResolvedIcon() const override;
    void resolveIcon() override;

private:
    const AppStream::Component m_appdata;
    State m_state = None;
    QString m_installedVersion;
    std::optional<QIcon> m_icon;
};

/*
 *   SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
 */
#include "DeskDroidResource.h"
#include "DeskDroidBackend.h"

#include <AppStreamQt/bundle.h>
#include <AppStreamQt/developer.h>
#include <AppStreamQt/icon.h>
#include <AppStreamQt/release.h>
#include <AppStreamQt/utils.h>
#include <KLocalizedString>
#include <LazyIconResolver.h>
#include <QDir>
#include <QFileInfo>
#include <QProcess>
#include <appstream/AppStreamUtils.h>

using namespace Qt::StringLiterals;

DeskDroidResource::DeskDroidResource(const AppStream::Component &component, DeskDroidBackend *backend)
    : AbstractResource(backend)
    , m_appdata(component)
{
}

DeskDroidBackend *DeskDroidResource::deskdroidBackend() const
{
    return static_cast<DeskDroidBackend *>(backend());
}

QString DeskDroidResource::ref() const
{
    const auto bundle = m_appdata.bundle(AppStream::Bundle::KindFlatpak);
    if (!bundle.isEmpty()) {
        return bundle.id();
    }
    return u"app/"_s + flatpakId() + u"/"_s + deskdroidBackend()->arch() + u"/stable"_s;
}

QString DeskDroidResource::flatpakId() const
{
    const auto bundle = m_appdata.bundle(AppStream::Bundle::KindFlatpak);
    if (!bundle.isEmpty()) {
        return bundle.id().section(u'/', 1, 1);
    }
    QString id = m_appdata.id();
    if (id.endsWith(".desktop"_L1)) {
        id.chop(8);
    }
    return id;
}

void DeskDroidResource::setState(State state)
{
    if (m_state == state) {
        return;
    }
    m_state = state;
    Q_EMIT stateChanged();
}

void DeskDroidResource::setInstalledVersion(const QString &version)
{
    m_installedVersion = version;
}

QString DeskDroidResource::packageName() const
{
    return flatpakId();
}

QString DeskDroidResource::name() const
{
    const QString n = m_appdata.name();
    return n.isEmpty() ? flatpakId() : n;
}

QString DeskDroidResource::comment()
{
    return m_appdata.summary();
}

bool DeskDroidResource::hasResolvedIcon() const
{
    return m_icon.has_value();
}

void DeskDroidResource::resolveIcon()
{
    m_icon = QIcon();
    const QString iconsDir = deskdroidBackend()->appstreamDir() + u"/icons/"_s;
    for (const AppStream::Icon &icon : m_appdata.icons()) {
        switch (icon.kind()) {
        case AppStream::Icon::KindCached:
        case AppStream::Icon::KindLocal: {
            // AppStream gives the catalog's icons as icons/flatpak/<size>/<file>
            // (links to icons/<size>); look for the file name if that's missing.
            const QString path = icon.url().toLocalFile();
            if (!QDir::isRelativePath(path) && QFileInfo::exists(path)) {
                m_icon->addFile(path, icon.size());
                break;
            }
            const QString file = QDir::isRelativePath(path) && !path.isEmpty() ? path : icon.name();
            for (const char *size : {"128x128", "64x64", "128x128@2"}) {
                const QString p = iconsDir + QLatin1String(size) + u'/' + file;
                if (QFileInfo::exists(p)) {
                    m_icon->addFile(p, icon.size());
                    break;
                }
            }
            break;
        }
        case AppStream::Icon::KindStock:
            if (QIcon::hasThemeIcon(icon.name())) {
                m_icon = QIcon::fromTheme(icon.name());
            }
            break;
        default:
            break;
        }
        if (!m_icon->isNull()) {
            break;
        }
    }
    if (m_icon->isNull()) {
        m_icon = QIcon::fromTheme(u"package-x-generic"_s);
    }
    Q_EMIT iconChanged();
}

QVariant DeskDroidResource::icon() const
{
    if (m_icon.has_value()) {
        return m_icon.value();
    }
    LazyIconResolver::instance()->queue(const_cast<DeskDroidResource *>(this));
    return u"package-x-generic"_s;
}

bool DeskDroidResource::canExecute() const
{
    return m_state >= Installed;
}

void DeskDroidResource::invokeApplication() const
{
    deskdroidBackend()->runApp(flatpakId());
}

AbstractResource::State DeskDroidResource::state()
{
    return m_state;
}

bool DeskDroidResource::hasCategory(const QString &category) const
{
    if (category == "Application"_L1) {
        return m_appdata.kind() != AppStream::Component::KindAddon;
    }
    return m_appdata.hasCategory(category);
}

AbstractResource::Type DeskDroidResource::type() const
{
    switch (m_appdata.kind()) {
    case AppStream::Component::KindAddon:
        return Addon;
    case AppStream::Component::KindRuntime:
        return ApplicationSupport;
    default:
        return Application;
    }
}

quint64 DeskDroidResource::size()
{
    return 0;
}

QString DeskDroidResource::sizeDescription()
{
    // Flathub's catalog doesn't carry sizes; flatpak shows them while installing.
    return i18nc("@info:status", "Size not known");
}

QJsonArray DeskDroidResource::licenses()
{
    return AppStreamUtils::licenses(m_appdata);
}

QString DeskDroidResource::installedVersion() const
{
    return m_installedVersion;
}

QString DeskDroidResource::availableVersion() const
{
    QString latest;
    const auto releases = m_appdata.releasesPlain().entries();
    for (const auto &release : releases) {
        if (latest.isEmpty() || AppStream::Utils::vercmpSimple(release.version(), latest) > 0) {
            latest = release.version();
        }
    }
    return latest;
}

QString DeskDroidResource::longDescription()
{
    return m_appdata.description();
}

QString DeskDroidResource::origin() const
{
    return u"flathub"_s;
}

QString DeskDroidResource::displayOrigin() const
{
    return u"Flathub"_s;
}

QString DeskDroidResource::section()
{
    return {};
}

QString DeskDroidResource::author() const
{
    const QString n = m_appdata.developer().name();
    return n.isEmpty() ? m_appdata.projectGroup() : n;
}

QList<PackageState> DeskDroidResource::addonsInformation()
{
    return {};
}

QString DeskDroidResource::sourceIcon() const
{
    return u"flatpak-discover"_s;
}

QDate DeskDroidResource::releaseDate() const
{
    const auto releases = m_appdata.releasesPlain();
    if (!releases.isEmpty()) {
        if (const auto r = releases.indexSafe(0)) {
            return r->timestamp().date();
        }
    }
    return {};
}

void DeskDroidResource::fetchChangelog()
{
    Q_EMIT changelogFetched(AppStreamUtils::changelogToHtml(m_appdata));
}

void DeskDroidResource::fetchScreenshots()
{
    Q_EMIT screenshotsFetched(AppStreamUtils::fetchScreenshots(m_appdata));
}

QString DeskDroidResource::appstreamId() const
{
    return m_appdata.id();
}

QUrl DeskDroidResource::homepage()
{
    return m_appdata.url(AppStream::Component::UrlKindHomepage);
}

QUrl DeskDroidResource::helpURL()
{
    return m_appdata.url(AppStream::Component::UrlKindHelp);
}

QUrl DeskDroidResource::bugURL()
{
    return m_appdata.url(AppStream::Component::UrlKindBugtracker);
}

QUrl DeskDroidResource::donationURL()
{
    return m_appdata.url(AppStream::Component::UrlKindDonation);
}

QUrl DeskDroidResource::contributeURL()
{
    return m_appdata.url(AppStream::Component::UrlKindContribute);
}

QStringList DeskDroidResource::mimetypes() const
{
    return m_appdata.provided(AppStream::Provided::KindMimetype).items();
}

QStringList DeskDroidResource::extends() const
{
    return m_appdata.extends();
}

QString DeskDroidResource::contentRatingDescription() const
{
    return AppStreamUtils::contentRatingDescription(m_appdata);
}

uint DeskDroidResource::contentRatingMinimumAge() const
{
    return AppStreamUtils::contentRatingMinimumAge(m_appdata);
}

QUrl DeskDroidResource::url() const
{
    return QUrl(u"appstream://"_s + appstreamId());
}

#include "moc_DeskDroidResource.cpp"

/*
    DeskDroid: the clipboard and media keys shared with the phone; see the header.

    SPDX-License-Identifier: GPL-2.0-or-later
*/
#include "nativedesk_bridge.h"

#include "protocol.h"
#include "wayland/display.h"
#include "wayland/seat.h"
#include "wayland_server.h"

#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusVariant>

#include <fcntl.h>
#include <unistd.h>

namespace KWin
{

static const QString s_utf8 = QStringLiteral("text/plain;charset=utf-8");
static const QString s_plain = QStringLiteral("text/plain");

// ---- the clipboard ------------------------------------------------------------

NativeDeskPhoneClipboard::NativeDeskPhoneClipboard(std::function<void(int fd)> paste)
    : m_paste(std::move(paste))
{
}

void NativeDeskPhoneClipboard::requestData(const QString &mimeType, qint32 fd)
{
    // Text only (mimeTypes); the phone writes UTF-8, which text/plain is too
    // for every app here. Like any data source, this one owns fd now.
    Q_UNUSED(mimeType)
    m_paste(fd);
    ::close(fd);
}

void NativeDeskPhoneClipboard::cancel()
{
}

QStringList NativeDeskPhoneClipboard::mimeTypes() const
{
    return {s_utf8, s_plain, QStringLiteral("UTF8_STRING"), QStringLiteral("STRING"), QStringLiteral("TEXT")};
}

NativeDeskClipboard::NativeDeskClipboard(std::function<void(int fd)> copied, std::function<void(int fd)> paste)
    : m_copied(std::move(copied))
    , m_paste(std::move(paste))
{
}

NativeDeskClipboard::~NativeDeskClipboard()
{
    if (m_phone && waylandServer() && waylandServer()->seat() && waylandServer()->seat()->selection() == m_phone.get()) {
        waylandServer()->seat()->setSelection(nullptr, waylandServer()->display()->nextSerial());
    }
}

void NativeDeskClipboard::start()
{
    if (m_started || !waylandServer() || !waylandServer()->seat()) {
        return;
    }
    m_started = true;
    connect(waylandServer()->seat(), &SeatInterface::selectionChanged, this, &NativeDeskClipboard::selectionChanged);
}

void NativeDeskClipboard::phoneChanged()
{
    start();
    if (!m_started) {
        return;
    }
    // A new source each time, as for a new copy in an app: apps that cache
    // what they last pasted read it again.
    auto old = std::move(m_phone);
    m_phone = std::make_unique<NativeDeskPhoneClipboard>(m_paste);
    waylandServer()->seat()->setSelection(m_phone.get(), waylandServer()->display()->nextSerial());
}

void NativeDeskClipboard::selectionChanged(AbstractDataSource *source)
{
    if (!source || source == m_phone.get()) {
        return; // nothing copied, or the phone's own text coming back
    }
    const QStringList offered = source->mimeTypes();
    QString mime;
    for (const QString &m : {s_utf8, s_plain, QStringLiteral("UTF8_STRING"), QStringLiteral("text/plain;charset=UTF-8")}) {
        if (offered.contains(m)) {
            mime = m;
            break;
        }
    }
    if (mime.isEmpty()) {
        return; // images, files...: the phone's clipboard keeps what it had
    }
    int fds[2];
    if (pipe2(fds, O_CLOEXEC) != 0) {
        return;
    }
    source->requestData(mime, fds[1]); // the app writes the text into the pipe (and the source closes fds[1])
    waylandServer()->display()->flush();
    m_copied(fds[0]); // the phone reads it from the other end
    ::close(fds[0]);
}

// ---- media keys -----------------------------------------------------------------

static const QString s_mprisPrefix = QStringLiteral("org.mpris.MediaPlayer2.");
static const QString s_mprisPath = QStringLiteral("/org/mpris/MediaPlayer2");
static const QString s_mprisPlayer = QStringLiteral("org.mpris.MediaPlayer2.Player");
static const QString s_properties = QStringLiteral("org.freedesktop.DBus.Properties");

NativeDeskMedia::NativeDeskMedia(std::function<void(uint32_t state)> state)
    : m_state(std::move(state))
{
}

bool NativeDeskMedia::isMediaKey(int code)
{
    switch (code) {
    case 79: // KEYCODE_HEADSETHOOK (a wired earpiece's button)
    case 85: // KEYCODE_MEDIA_PLAY_PAUSE
    case 86: // KEYCODE_MEDIA_STOP
    case 87: // KEYCODE_MEDIA_NEXT
    case 88: // KEYCODE_MEDIA_PREVIOUS
    case 89: // KEYCODE_MEDIA_REWIND
    case 90: // KEYCODE_MEDIA_FAST_FORWARD
    case 126: // KEYCODE_MEDIA_PLAY
    case 127: // KEYCODE_MEDIA_PAUSE
        return true;
    }
    return false;
}

void NativeDeskMedia::start()
{
    QDBusConnection bus = QDBusConnection::sessionBus();
    if (!bus.isConnected()) {
        qWarning("nativedesk: no session bus, the phone's media keys only reach the focused window");
        return;
    }
    bus.connect(QStringLiteral("org.freedesktop.DBus"), QStringLiteral("/org/freedesktop/DBus"), QStringLiteral("org.freedesktop.DBus"),
                QStringLiteral("NameOwnerChanged"), this, SLOT(nameOwnerChanged(QString, QString, QString)));
    // Any sender: the message says which player it was.
    bus.connect(QString(), s_mprisPath, s_properties, QStringLiteral("PropertiesChanged"), this,
                SLOT(propertiesChanged(QString, QVariantMap, QStringList, QDBusMessage)));
    // The players already there.
    auto *watcher = new QDBusPendingCallWatcher(bus.interface()->asyncCall(QStringLiteral("ListNames")), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *w) {
        w->deleteLater();
        QDBusPendingReply<QStringList> reply = *w;
        if (reply.isError()) {
            return;
        }
        for (const QString &name : reply.value()) {
            if (!name.startsWith(s_mprisPrefix)) {
                continue;
            }
            auto *owner = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().interface()->asyncCall(QStringLiteral("GetNameOwner"), name), this);
            connect(owner, &QDBusPendingCallWatcher::finished, this, [this, name](QDBusPendingCallWatcher *o) {
                o->deleteLater();
                QDBusPendingReply<QString> r = *o;
                if (!r.isError()) {
                    addPlayer(name, r.value());
                }
            });
        }
    });
}

void NativeDeskMedia::nameOwnerChanged(const QString &name, const QString &oldOwner, const QString &newOwner)
{
    if (!name.startsWith(s_mprisPrefix)) {
        return;
    }
    if (!oldOwner.isEmpty()) {
        m_players.remove(oldOwner);
        if (m_lastActive == oldOwner) {
            m_lastActive.clear();
        }
    }
    if (!newOwner.isEmpty()) {
        addPlayer(name, newOwner);
    }
    report();
}

void NativeDeskMedia::addPlayer(const QString &name, const QString &owner)
{
    m_players.insert(owner, Player{name, QString()});
    QDBusMessage get = QDBusMessage::createMethodCall(owner, s_mprisPath, s_properties, QStringLiteral("Get"));
    get << s_mprisPlayer << QStringLiteral("PlaybackStatus");
    auto *watcher = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(get), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, owner](QDBusPendingCallWatcher *w) {
        w->deleteLater();
        QDBusPendingReply<QDBusVariant> reply = *w;
        if (!reply.isError()) {
            setStatus(owner, reply.value().variant().toString());
        }
    });
    report();
}

void NativeDeskMedia::propertiesChanged(const QString &interface, const QVariantMap &changed, const QStringList &invalidated, const QDBusMessage &message)
{
    Q_UNUSED(invalidated)
    if (interface != s_mprisPlayer) {
        return;
    }
    const auto status = changed.constFind(QStringLiteral("PlaybackStatus"));
    if (status != changed.constEnd()) {
        setStatus(message.service(), status->toString());
    }
}

void NativeDeskMedia::setStatus(const QString &owner, const QString &status)
{
    auto it = m_players.find(owner);
    if (it == m_players.end()) {
        return;
    }
    if (status == QLatin1String("Playing") && it->status != status) {
        m_lastActive = owner;
    }
    it->status = status;
    report();
}

// The player a key is for: the one playing (the last to start, if several),
// else the last one that played, else any.
QString NativeDeskMedia::target() const
{
    if (m_players.value(m_lastActive).status == QLatin1String("Playing")) {
        return m_lastActive;
    }
    for (auto it = m_players.cbegin(); it != m_players.cend(); ++it) {
        if (it->status == QLatin1String("Playing")) {
            return it.key();
        }
    }
    if (m_players.contains(m_lastActive)) {
        return m_lastActive;
    }
    return m_players.isEmpty() ? QString() : m_players.cbegin().key();
}

bool NativeDeskMedia::key(int code)
{
    const QString owner = target();
    if (owner.isEmpty()) {
        return false;
    }
    switch (code) {
    case 79:
    case 85:
        call(owner, QStringLiteral("PlayPause"));
        break;
    case 126:
        call(owner, QStringLiteral("Play"));
        break;
    case 127:
        call(owner, QStringLiteral("Pause"));
        break;
    case 86:
        call(owner, QStringLiteral("Stop"));
        break;
    case 87:
        call(owner, QStringLiteral("Next"));
        break;
    case 88:
        call(owner, QStringLiteral("Previous"));
        break;
    case 89:
    case 90: // ten seconds back or forward (MPRIS counts microseconds)
        call(owner, QStringLiteral("Seek"), {QVariant::fromValue<qlonglong>(code == 90 ? 10000000LL : -10000000LL)});
        break;
    default:
        return false;
    }
    return true;
}

void NativeDeskMedia::call(const QString &owner, const QString &method, const QVariantList &args)
{
    QDBusMessage m = QDBusMessage::createMethodCall(owner, s_mprisPath, s_mprisPlayer, method);
    m.setArguments(args);
    QDBusConnection::sessionBus().asyncCall(m);
}

void NativeDeskMedia::report()
{
    uint32_t state = m_players.isEmpty() ? NDESK_PLAYING_NONE : NDESK_PLAYING_PAUSED;
    for (const Player &p : std::as_const(m_players)) {
        if (p.status == QLatin1String("Playing")) {
            state = NDESK_PLAYING_PLAYING;
            break;
        }
    }
    if (state != m_reported) {
        m_reported = state;
        m_state(state);
    }
}

} // namespace KWin

#include "moc_nativedesk_bridge.cpp"

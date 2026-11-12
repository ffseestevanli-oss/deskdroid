/*
    DeskDroid: what the desktop shares with the phone around KWin's nativedesk
    backend.

    - The clipboard: text copied in a desktop app goes to Android's clipboard,
      and text copied in an Android app can be pasted in desktop apps.
    - Media keys: the phone's play/pause, next, previous and stop (a Bluetooth
      earpiece, a remote, a keyboard's media keys) go to the desktop's media
      players over MPRIS, the D-Bus interface Plasma's own media controls use.
      Desktop apps keep playing their own sound: nothing here goes through
      Android's media framework.

    SPDX-License-Identifier: GPL-2.0-or-later
*/
#pragma once

#include "wayland/abstract_data_source.h"

#include <QDBusMessage>
#include <QHash>
#include <QObject>
#include <QPointer>
#include <QSocketNotifier>

#include <functional>
#include <memory>

namespace KWin
{

class NativeDeskBackend;

// The phone's clipboard as the desktop's selection. Its text isn't copied
// over until an app pastes: then the paste's pipe goes to the phone
// (NDESK_CLIP_PASTE), which writes the text straight into it.
class NativeDeskPhoneClipboard : public AbstractDataSource
{
    Q_OBJECT

public:
    explicit NativeDeskPhoneClipboard(std::function<void(int fd)> paste);

    void requestData(const QString &mimeType, qint32 fd) override;
    void cancel() override;
    QStringList mimeTypes() const override;

private:
    std::function<void(int fd)> m_paste;
};

class NativeDeskClipboard : public QObject
{
    Q_OBJECT

public:
    // copied: a desktop app copied text, readable from fd (passed on, then closed here).
    // paste: an app pastes the phone's text into fd (the same).
    NativeDeskClipboard(std::function<void(int fd)> copied, std::function<void(int fd)> paste);
    ~NativeDeskClipboard() override;

    // Once the Wayland seat exists.
    void start();
    // The phone's clipboard changed (NDESK_CLIP_PHONE).
    void phoneChanged();

private:
    void selectionChanged(AbstractDataSource *source);

    std::function<void(int)> m_copied;
    std::function<void(int)> m_paste;
    std::unique_ptr<NativeDeskPhoneClipboard> m_phone;
    bool m_started = false;
};

// MPRIS players on the session bus, for the phone's media keys.
class NativeDeskMedia : public QObject
{
    Q_OBJECT

public:
    // state: NDESK_PLAYING_*, whenever it changes.
    explicit NativeDeskMedia(std::function<void(uint32_t state)> state);

    void start();
    // An Android media key code went down. False if no player took it, so
    // the key goes to the focused window as a keyboard's media key instead.
    bool key(int androidKeyCode);
    bool hasPlayers() const { return !m_players.isEmpty(); }

    static bool isMediaKey(int androidKeyCode);

private Q_SLOTS:
    void nameOwnerChanged(const QString &name, const QString &oldOwner, const QString &newOwner);
    void propertiesChanged(const QString &interface, const QVariantMap &changed, const QStringList &invalidated, const QDBusMessage &message);

private:
    struct Player
    {
        QString name; // org.mpris.MediaPlayer2.<app>
        QString status; // Playing, Paused, Stopped
    };

    void addPlayer(const QString &name, const QString &owner);
    void setStatus(const QString &owner, const QString &status);
    void call(const QString &owner, const QString &method, const QVariantList &args = {});
    QString target() const;
    void report();

    std::function<void(uint32_t)> m_state;
    QHash<QString, Player> m_players; // by unique bus name (the owner)
    QString m_lastActive; // the player that started playing last
    uint32_t m_reported = 0;
};

} // namespace KWin

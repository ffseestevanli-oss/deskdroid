// DeskDroid: stand-in for libnotificationmanager's Settings, with the
// defaults: badges shown, Do Not Disturb off.
#pragma once

#include <QDateTime>
#include <QObject>
#include <QStringList>

namespace NotificationManager
{
class Settings : public QObject
{
    Q_OBJECT
public:
    explicit Settings(QObject *parent = nullptr)
        : QObject(parent)
    {
    }
    QStringList badgeBlacklistedApplications() const
    {
        return {};
    }
    bool badgesInTaskManager() const
    {
        return true;
    }
    bool notificationsInhibitedByApplication() const
    {
        return false;
    }
    QDateTime notificationsInhibitedUntil() const
    {
        return {};
    }
Q_SIGNALS:
    void settingsChanged();
};
}

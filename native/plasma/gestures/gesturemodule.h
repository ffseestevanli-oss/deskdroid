// DeskDroid: System Settings › Gestures. Each page (Edge Swipes, Taps) is a
// GestureModule with its own gestures; both save into $HOME/gestures.json,
// which the app reads (app/src/main/java/io/deskdroid/app/Gestures.kt):
//   {"bottom_left": "keyboard", "bottom_right": "dd_menu", ..., "three_finger_tap": "touch_mode",
//    "mode_indicator": true}
// Gestures map to actions; switches (SwitchInfo) are on/off features shown as
// checkboxes under them. The ids and the defaults here match Gestures.kt.
#pragma once

#include <KPluginMetaData>
#include <KQuickConfigModule>

#include <QDir>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSaveFile>
#include <QVariantList>
#include <QVariantMap>

#include <utility>

struct GestureInfo {
    QString id;
    QString label;
    QString hint;
    QString defaultAction;
};

struct SwitchInfo {
    QString id;
    QString label;
    QString hint;
    bool defaultOn;
};

class GestureModule : public KQuickConfigModule
{
    Q_OBJECT
    Q_PROPERTY(QString intro MEMBER m_intro CONSTANT)
    Q_PROPERTY(QVariantList gestures MEMBER m_gestureList CONSTANT)
    Q_PROPERTY(QVariantList actions MEMBER m_actionList CONSTANT)
    Q_PROPERTY(QVariantMap assigned READ assigned NOTIFY assignedChanged)
    Q_PROPERTY(QVariantList switches MEMBER m_switchList CONSTANT)
    Q_PROPERTY(QVariantMap switched READ switched NOTIFY assignedChanged)

public:
    GestureModule(QObject *parent, const KPluginMetaData &data, const QString &intro, const QList<GestureInfo> &gestures,
                  const QList<SwitchInfo> &switches = {})
        : KQuickConfigModule(parent, data)
        , m_intro(intro)
        , m_gestures(gestures)
        , m_switches(switches)
    {
        for (const SwitchInfo &s : switches) {
            m_switchList << QVariantMap{{QStringLiteral("id"), s.id}, {QStringLiteral("label"), s.label}, {QStringLiteral("hint"), s.hint}};
        }
        setButtons(Default | Apply);
        for (const GestureInfo &g : gestures) {
            m_gestureList << QVariantMap{{QStringLiteral("id"), g.id}, {QStringLiteral("label"), g.label}, {QStringLiteral("hint"), g.hint}};
        }
        const QList<QPair<QString, QString>> actions = {
            {QStringLiteral("none"), QStringLiteral("Do nothing")},
            {QStringLiteral("dd_menu"), QStringLiteral("Open the DD menu")},
            {QStringLiteral("keyboard"), QStringLiteral("Show or hide the keyboard")},
            {QStringLiteral("touch_mode"), QStringLiteral("Switch between Touchpad and Direct touch")},
            {QStringLiteral("start_menu"), QStringLiteral("Open the start menu")},
            {QStringLiteral("overview"), QStringLiteral("Overview")},
            {QStringLiteral("show_desktop"), QStringLiteral("Show the desktop")},
            {QStringLiteral("switch_window"), QStringLiteral("Switch to the previous window")},
            {QStringLiteral("back"), QStringLiteral("Back (Escape)")},
        };
        for (const auto &a : actions) {
            m_actionList << QVariantMap{{QStringLiteral("id"), a.first}, {QStringLiteral("label"), a.second}};
            m_actionIds << a.first;
        }
    }

    QVariantMap assigned() const
    {
        QVariantMap m;
        for (auto it = m_assigned.cbegin(); it != m_assigned.cend(); ++it) {
            m.insert(it.key(), it.value());
        }
        return m;
    }

    QVariantMap switched() const
    {
        QVariantMap m;
        for (auto it = m_on.cbegin(); it != m_on.cend(); ++it) {
            m.insert(it.key(), it.value());
        }
        return m;
    }

    Q_INVOKABLE void setSwitch(const QString &id, bool on)
    {
        if (!m_on.contains(id) || m_on.value(id) == on) {
            return;
        }
        m_on[id] = on;
        changed();
    }

    Q_INVOKABLE void assign(const QString &gesture, const QString &action)
    {
        if (!m_assigned.contains(gesture) || !m_actionIds.contains(action) || m_assigned.value(gesture) == action) {
            return;
        }
        m_assigned[gesture] = action;
        changed();
    }

    void load() override
    {
        const QJsonObject o = readFile();
        m_assigned.clear();
        for (const GestureInfo &g : std::as_const(m_gestures)) {
            const QString a = o.value(g.id).toString();
            m_assigned[g.id] = m_actionIds.contains(a) ? a : g.defaultAction;
        }
        m_on.clear();
        for (const SwitchInfo &s : std::as_const(m_switches)) {
            const QJsonValue v = o.value(s.id);
            m_on[s.id] = v.isBool() ? v.toBool() : s.defaultOn;
        }
        m_saved = m_assigned;
        m_savedOn = m_on;
        changed();
    }

    void save() override
    {
        // The other page's gestures stay as that page saved them.
        QJsonObject o = readFile();
        for (auto it = m_assigned.cbegin(); it != m_assigned.cend(); ++it) {
            o.insert(it.key(), it.value());
        }
        for (auto it = m_on.cbegin(); it != m_on.cend(); ++it) {
            o.insert(it.key(), it.value());
        }
        QSaveFile f(path());
        if (f.open(QIODevice::WriteOnly)) {
            f.write(QJsonDocument(o).toJson(QJsonDocument::Indented));
            if (f.commit()) {
                m_saved = m_assigned;
                m_savedOn = m_on;
            }
        }
        changed();
    }

    void defaults() override
    {
        for (const GestureInfo &g : std::as_const(m_gestures)) {
            m_assigned[g.id] = g.defaultAction;
        }
        for (const SwitchInfo &s : std::as_const(m_switches)) {
            m_on[s.id] = s.defaultOn;
        }
        changed();
    }

Q_SIGNALS:
    void assignedChanged();

private:
    static QString path()
    {
        return QDir::homePath() + QStringLiteral("/gestures.json");
    }

    static QJsonObject readFile()
    {
        QFile f(path());
        if (!f.open(QIODevice::ReadOnly)) {
            return {};
        }
        return QJsonDocument::fromJson(f.readAll()).object();
    }

    void changed()
    {
        bool isDefault = true;
        for (const GestureInfo &g : std::as_const(m_gestures)) {
            isDefault = isDefault && m_assigned.value(g.id) == g.defaultAction;
        }
        for (const SwitchInfo &s : std::as_const(m_switches)) {
            isDefault = isDefault && m_on.value(s.id) == s.defaultOn;
        }
        setNeedsSave(m_assigned != m_saved || m_on != m_savedOn);
        setRepresentsDefaults(isDefault);
        Q_EMIT assignedChanged();
    }

    QString m_intro;
    QList<GestureInfo> m_gestures;
    QVariantList m_gestureList;
    QVariantList m_actionList;
    QStringList m_actionIds;
    QMap<QString, QString> m_assigned;
    QMap<QString, QString> m_saved;
    QList<SwitchInfo> m_switches;
    QVariantList m_switchList;
    QMap<QString, bool> m_on;
    QMap<QString, bool> m_savedOn;
};

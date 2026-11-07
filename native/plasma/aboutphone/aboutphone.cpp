// DeskDroid: About This Phone. DeskDroid writes $HOME/phone-info.json at each
// desktop start (NativeDesk.writePhoneInfo):
//   {"title": "...", "subtitle": "...", "sections": [{"title": "...", "rows": [["label", "value"], ...]}]}
#include <KPluginFactory>
#include <KQuickConfigModule>

#include <QDir>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QVariantList>

class AboutPhone : public KQuickConfigModule
{
    Q_OBJECT
    Q_PROPERTY(QString title MEMBER m_title CONSTANT)
    Q_PROPERTY(QString subtitle MEMBER m_subtitle CONSTANT)
    Q_PROPERTY(QVariantList sections MEMBER m_sections CONSTANT)

public:
    AboutPhone(QObject *parent, const KPluginMetaData &data)
        : KQuickConfigModule(parent, data)
    {
        setButtons(NoAdditionalButton);
        QFile f(QDir::homePath() + QStringLiteral("/phone-info.json"));
        if (!f.open(QIODevice::ReadOnly)) {
            m_title = QStringLiteral("This phone");
            m_subtitle = QStringLiteral("Restart the desktop to read the phone's details.");
            return;
        }
        const QJsonObject o = QJsonDocument::fromJson(f.readAll()).object();
        m_title = o.value(QStringLiteral("title")).toString();
        m_subtitle = o.value(QStringLiteral("subtitle")).toString();
        m_sections = o.value(QStringLiteral("sections")).toArray().toVariantList();
    }

private:
    QString m_title;
    QString m_subtitle;
    QVariantList m_sections;
};

K_PLUGIN_CLASS_WITH_JSON(AboutPhone, "kcm_aboutphone.json")

#include "aboutphone.moc"

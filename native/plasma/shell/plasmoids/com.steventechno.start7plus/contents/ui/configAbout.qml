import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    ColumnLayout {
        spacing: Kirigami.Units.largeSpacing

        Item { Layout.fillHeight: true }

        Kirigami.Icon {
            Layout.alignment: Qt.AlignHCenter
            source: "start-here-kde"
            implicitWidth: Kirigami.Units.iconSizes.huge
            implicitHeight: Kirigami.Units.iconSizes.huge
        }

        Kirigami.Heading {
            Layout.alignment: Qt.AlignHCenter
            text: i18n("Start 7 Plus")
        }

        QQC2.Label {
            Layout.alignment: Qt.AlignHCenter
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: i18n("Authored by Claude Sonnet 5.5 - Brought to you by Steventechno")
        }

        Item { Layout.fillHeight: true }
    }
}

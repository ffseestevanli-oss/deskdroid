// DeskDroid: About This Phone (aboutphone.cpp reads the details).
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    id: root

    ColumnLayout {
        spacing: Kirigami.Units.largeSpacing

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.largeSpacing
            Kirigami.Icon {
                source: "smartphone"
                implicitWidth: Kirigami.Units.iconSizes.huge
                implicitHeight: implicitWidth
            }
            ColumnLayout {
                spacing: 0
                Kirigami.Heading {
                    text: kcm.title
                    level: 1
                }
                QQC2.Label {
                    text: kcm.subtitle
                    opacity: 0.7
                    visible: text.length > 0
                }
            }
        }

        Repeater {
            model: kcm.sections
            delegate: Kirigami.FormLayout {
                required property var modelData
                Layout.fillWidth: true

                Kirigami.Separator {
                    Kirigami.FormData.isSection: true
                    Kirigami.FormData.label: modelData.title
                }
                Repeater {
                    model: modelData.rows
                    delegate: QQC2.Label {
                        required property var modelData
                        Kirigami.FormData.label: modelData[0] + ":"
                        text: modelData[1]
                        textFormat: Text.PlainText
                        wrapMode: Text.Wrap
                        Layout.maximumWidth: Kirigami.Units.gridUnit * 24
                    }
                }
            }
        }

        QQC2.Button {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: Kirigami.Units.largeSpacing
            icon.name: "edit-copy"
            text: i18nc("@action:button", "Copy to Clipboard")
            onClicked: {
                var t = kcm.title + "\n";
                for (var i = 0; i < kcm.sections.length; i++) {
                    var s = kcm.sections[i];
                    t += "\n" + s.title + "\n";
                    for (var j = 0; j < s.rows.length; j++) t += s.rows[j][0] + ": " + s.rows[j][1] + "\n";
                }
                clip.text = t;
                clip.selectAll();
                clip.copy();
            }
        }
        TextEdit { id: clip; visible: false }
    }
}

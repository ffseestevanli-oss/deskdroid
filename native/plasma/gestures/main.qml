// DeskDroid: a System Settings › Gestures page (gesturemodule.h): a row per
// gesture with the action it does.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    id: root

    ColumnLayout {
        spacing: Kirigami.Units.largeSpacing

        QQC2.Label {
            Layout.fillWidth: true
            Layout.topMargin: Kirigami.Units.largeSpacing
            text: kcm.intro
            wrapMode: Text.WordWrap
        }

        Kirigami.FormLayout {
            Layout.fillWidth: true

            Repeater {
                model: kcm.gestures
                delegate: ColumnLayout {
                    id: row
                    required property var modelData
                    Kirigami.FormData.label: modelData.label + ":"
                    spacing: Kirigami.Units.smallSpacing

                    QQC2.ComboBox {
                        id: combo
                        model: kcm.actions
                        textRole: "label"
                        valueRole: "id"
                        onActivated: kcm.assign(row.modelData.id, currentValue)
                        function sync() {
                            currentIndex = indexOfValue(kcm.assigned[row.modelData.id])
                        }
                        Component.onCompleted: sync()
                        Connections {
                            target: kcm
                            function onAssignedChanged() { combo.sync() }
                        }
                    }
                    QQC2.Label {
                        Layout.maximumWidth: Kirigami.Units.gridUnit * 22
                        Layout.bottomMargin: Kirigami.Units.smallSpacing
                        text: row.modelData.hint
                        visible: text.length > 0
                        wrapMode: Text.WordWrap
                        opacity: 0.7
                        font: Kirigami.Theme.smallFont
                    }
                }
            }
        }
    }
}

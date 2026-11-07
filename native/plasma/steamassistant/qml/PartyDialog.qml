// A question in the party look: a title, the text, and a row of buttons.
// choices: [{ text, accent, primary, run }]; Cancel is always there.
import QtQuick
import QtQuick.Controls as QQC2
import "."

QQC2.Popup {
    id: dialog
    property string title: ""
    property string text: ""
    property var choices: []
    parent: QQC2.Overlay.overlay
    modal: true
    focus: true
    anchors.centerIn: parent
    width: Math.min(parent ? parent.width - 32 : 560, 560)
    padding: 24
    closePolicy: QQC2.Popup.CloseOnEscape | QQC2.Popup.CloseOnPressOutside

    QQC2.Overlay.modal: Rectangle { color: Qt.rgba(0.03, 0.03, 0.05, 0.75) }
    background: Chamfer {
        cut: 18
        fillColor: Party.surface
        rainbowStroke: true
        strokeWidth: 2
    }
    implicitHeight: body.implicitHeight + topPadding + bottomPadding
    contentItem: Column {
        id: body
        spacing: 14
        RainbowText {
            heading: dialog.title
            size: 22
            width: dialog.availableWidth
        }
        Text {
            text: dialog.text
            font.family: Party.body; font.pixelSize: 15
            color: Party.textSoft
            wrapMode: Text.WordWrap
            lineHeight: 1.2
            width: dialog.availableWidth
        }
        Flow {
            width: dialog.availableWidth
            spacing: 10
            Repeater {
                model: dialog.choices
                PartyButton {
                    text: modelData.text
                    primary: modelData.primary === true
                    accent: modelData.accent || Party.pink
                    onClicked: { dialog.close(); modelData.run() }
                }
            }
            PartyButton {
                text: "Cancel"
                onClicked: dialog.close()
            }
        }
    }
}

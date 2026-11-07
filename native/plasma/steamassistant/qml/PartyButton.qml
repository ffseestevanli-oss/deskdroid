// The party buttons: rainbow-filled with dark Orbitron text (primary), or an
// outline in one color.
import QtQuick
import QtQuick.Controls as QQC2
import "."

QQC2.AbstractButton {
    id: root
    property bool primary: false
    property color accent: Party.border
    property color textColor: primary ? Party.bg : Party.text
    // A small one, for rows in a list.
    property bool compact: false
    property real cut: primary ? 16 : compact ? 7 : 10
    implicitHeight: primary ? 56 : compact ? 34 : 44
    implicitWidth: Math.max(primary ? 220 : compact ? 0 : 140, label.implicitWidth + (compact ? 28 : 48))
    focusPolicy: Qt.StrongFocus
    hoverEnabled: true
    opacity: enabled ? 1 : 0.4

    background: Item {
        Chamfer {
            anchors.fill: parent
            cut: root.cut
            rainbowFill: root.primary
            fillColor: root.primary ? "transparent" : (root.hovered ? Party.surface : Party.surfaceDim)
            strokeColor: root.primary ? "transparent" : (root.hovered || root.visualFocus ? Qt.lighter(root.accent, 1.3) : root.accent)
            strokeWidth: root.primary ? 0 : 1.5
        }
        // Pressed and hovered: a light wash over the rainbow.
        Rectangle {
            anchors.fill: parent
            visible: root.primary
            color: "white"
            opacity: root.down ? 0.25 : root.hovered ? 0.12 : 0
        }
        Rectangle {
            anchors.fill: parent
            anchors.margins: -3
            visible: root.visualFocus
            color: "transparent"
            border.color: Party.cyan
            border.width: 2
        }
    }
    contentItem: Text {
        id: label
        text: root.primary ? root.text.toUpperCase() : root.text
        font.family: root.primary ? Party.heading : Party.body
        font.weight: root.primary ? Font.Black : Font.Bold
        font.pixelSize: root.primary ? 16 : root.compact ? 13 : 15
        font.letterSpacing: root.primary ? 1.6 : 0.3
        color: root.textColor
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }
}

// A grid tile, like the phone app's control grid (Ui.tile): a dark square
// with an icon, a title and a line under it, and an accent bar at the bottom.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "."

QQC2.AbstractButton {
    id: root
    property string iconName: ""
    property string subtitle: ""
    property color accent: Party.pink
    // Shown instead of the subtitle while the tile can't be used.
    property string lockedText: ""
    implicitWidth: 220
    implicitHeight: 132
    hoverEnabled: true
    focusPolicy: Qt.StrongFocus

    background: Item {
        Chamfer {
            anchors.fill: parent
            cut: 14
            cutTopLeft: false
            fillColor: root.down ? Party.cardOn : root.hovered && root.enabled ? Party.surface : Party.card
            strokeColor: root.hovered && root.enabled || root.visualFocus ? root.accent : Party.borderSoft
            strokeWidth: 1.5
            accent: root.enabled ? root.accent : Party.border
            accentWidth: 3
        }
    }
    contentItem: ColumnLayout {
        spacing: 6
        opacity: root.enabled ? 1 : 0.45
        Kirigami.Icon {
            source: root.iconName
            Layout.preferredWidth: 30
            Layout.preferredHeight: 30
            color: root.accent
            isMask: false
        }
        Item { Layout.fillHeight: true }
        Text {
            text: root.text
            font.family: Party.body
            font.weight: Font.Bold
            font.pixelSize: 16
            color: Party.text
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }
        Text {
            text: root.enabled || root.lockedText === "" ? root.subtitle : root.lockedText
            font.family: Party.body
            font.pixelSize: 13
            color: Party.muted
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
            Layout.fillWidth: true
        }
    }
    padding: 16
    bottomPadding: 18
}

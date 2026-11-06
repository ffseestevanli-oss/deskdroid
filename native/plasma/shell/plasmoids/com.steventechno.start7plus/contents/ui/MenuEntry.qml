import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

// One row of a Win7Menu (or a thin separator line)
QQC2.AbstractButton {
    id: entry
    property bool separator: false
    signal triggered()

    width: parent ? parent.width : implicitWidth
    implicitWidth: separator ? 0 : row.implicitWidth + Kirigami.Units.largeSpacing * 2
    implicitHeight: separator ? Kirigami.Units.smallSpacing * 2 + 1 : Math.max(Kirigami.Units.iconSizes.small, label.implicitHeight) + Kirigami.Units.smallSpacing * 2
    hoverEnabled: true
    onClicked: if (!separator) triggered()

    background: Rectangle {
        visible: !entry.separator && entry.enabled && (entry.hovered || entry.down)
        radius: 3
        color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.35)
        border.width: 1
        border.color: Kirigami.Theme.highlightColor
    }
    contentItem: Item {
        Rectangle {
            visible: entry.separator
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1
            color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.25)
        }
        RowLayout {
            id: row
            visible: !entry.separator
            anchors.fill: parent
            anchors.leftMargin: Kirigami.Units.largeSpacing
            anchors.rightMargin: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.smallSpacing
            Kirigami.Icon {
                source: entry.icon.name
                visible: entry.icon.name !== ""
                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                Layout.preferredHeight: Kirigami.Units.iconSizes.small
                opacity: entry.enabled ? 1 : 0.5
            }
            QQC2.Label {
                id: label
                text: entry.text
                Layout.fillWidth: true
                opacity: entry.enabled ? 1 : 0.5
                elide: Text.ElideRight
            }
        }
    }
}

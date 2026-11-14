import QtQuick
import QtQuick.Layouts

// One effect: title, its switch, its controls (put inside).
Item {
    id: card
    property string title
    property string subtitle
    property string key: ""          // "<effect>.enable", or "" for no switch
    property bool on: key === "" ? true : (viper.revision, viper.get(key)) !== 0
    property string note: ""
    default property alias content: body.data
    implicitHeight: col.implicitHeight + 28
    Layout.fillWidth: true

    Chamfer { anchors.fill: parent; fill: card.on && card.key !== "" ? Theme.cardOn : Theme.card; stroke: card.on && card.key !== "" ? "#4A2A4D" : Theme.border }
    Rainbow { visible: card.on && card.key !== ""; x: Theme.cut; width: parent.width - Theme.cut - 1; y: 1 }

    ColumnLayout {
        id: col
        x: 16; y: 14; width: parent.width - 32
        spacing: 10
        RowLayout {
            Layout.fillWidth: true
            ColumnLayout {
                spacing: 0
                Layout.fillWidth: true
                Text { text: card.title.toUpperCase(); color: Theme.text; font.family: Theme.heading; font.pixelSize: 13; font.letterSpacing: 1; Layout.fillWidth: true; elide: Text.ElideRight }
                Text { visible: card.subtitle !== ""; text: card.subtitle; color: Theme.dim; font.family: Theme.body; font.pixelSize: 12; Layout.fillWidth: true; wrapMode: Text.WordWrap }
            }
            DDSwitch {
                visible: card.key !== ""
                checked: card.on
                onToggled: on => viper.set(card.key, on ? 1 : 0)
            }
        }
        ColumnLayout { id: body; Layout.fillWidth: true; spacing: 10 }
        Text { visible: card.note !== ""; text: card.note; color: Theme.dim; font.family: Theme.body; font.pixelSize: 12; font.italic: true; wrapMode: Text.WordWrap; Layout.fillWidth: true }
    }
}

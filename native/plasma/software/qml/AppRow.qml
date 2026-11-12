// One app in the catalog: icon, name, what it is, version and size, and
// Install / Update / Open / Remove, with the download's progress.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "."

Item {
    id: row
    property var app: ({})
    property var progress: undefined   // undefined: not busy; -1: busy, no estimate
    readonly property bool installed: app.installed !== null && app.installed !== undefined
    readonly property bool current: installed && (app.local || app.installed === app.version)
    readonly property bool working: progress !== undefined
    readonly property color accent: !installed ? Party.cyan : current ? Party.green : Party.yellow
    implicitHeight: layout.implicitHeight + 28

    function size(bytes) {
        if (!bytes) return ""
        return bytes >= 1e9 ? (bytes / 1e9).toFixed(1) + " GB" : Math.max(0.1, bytes / 1e6).toFixed(1) + " MB"
    }

    Chamfer {
        anchors.fill: parent
        cut: 12
        cutTopLeft: false
        fillColor: hover.hovered ? Party.surface : Party.card
        strokeColor: hover.hovered ? row.accent : Party.borderSoft
        strokeWidth: 1.5
    }
    Rectangle { width: 3; height: parent.height; color: row.accent }
    HoverHandler { id: hover }

    RowLayout {
        id: layout
        anchors.fill: parent
        anchors.margins: 14
        anchors.leftMargin: 20
        spacing: 16

        Item {
            Layout.preferredWidth: 56
            Layout.preferredHeight: 56
            Image {
                id: img
                anchors.fill: parent
                source: row.app.icon ? "file://" + row.app.icon : ""
                sourceSize: Qt.size(112, 112)
                fillMode: Image.PreserveAspectFit
                smooth: true
                visible: status === Image.Ready
            }
            Kirigami.Icon {
                anchors.fill: parent
                visible: !img.visible
                source: row.app.id || "package-x-generic"
                fallback: "package-x-generic"
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            Text {
                text: row.app.name || row.app.id || ""
                font.family: Party.body; font.weight: Font.Bold; font.pixelSize: 17
                color: Party.text
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
            Text {
                visible: text !== ""
                text: row.app.summary || ""
                font.family: Party.body; font.pixelSize: 14
                color: Party.muted
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
            Text {
                text: {
                    const bits = []
                    if (row.app.version) bits.push(row.app.version)
                    if (row.app.size) bits.push(row.size(row.app.size))
                    if (row.installed && !row.current) bits.push("installed: " + (row.app.installed || "older"))
                    else if (row.installed) bits.push("installed")
                    return bits.join("  ·  ")
                }
                font.family: Party.body; font.pixelSize: 12
                color: row.installed && !row.current ? Party.yellow : Party.dim
                Layout.fillWidth: true
            }
            RainbowBar {
                visible: row.working
                fraction: row.progress >= 0 ? row.progress : 0
                indeterminate: !(row.progress >= 0)
                implicitHeight: 18
                segments: 24
                Layout.fillWidth: true
                Layout.maximumWidth: 420
                Layout.topMargin: 6
            }
        }
        Text {
            visible: row.working
            text: row.progress >= 0 ? Math.round(row.progress * 100) + "%" : (row.installed && row.current ? "Removing…" : "Working…")
            font.family: Party.heading; font.weight: Font.Black; font.pixelSize: 14
            color: Party.text
        }
        PartyButton {
            visible: !row.working && row.installed && row.current
            compact: true
            text: "Open"
            accent: Party.green
            onClicked: backend.launch(row.app.id)
        }
        PartyButton {
            visible: !row.working && (!row.installed || !row.current)
            compact: true
            text: row.installed ? "Update" : "Install"
            accent: row.installed ? Party.yellow : Party.cyan
            onClicked: backend.install(row.app.id)
        }
        PartyButton {
            visible: !row.working && row.installed
            compact: true
            text: "Remove"
            accent: Party.red
            onClicked: confirm.open()
        }
    }

    PartyDialog {
        id: confirm
        title: "Remove " + (row.app.name || row.app.id) + "?"
        text: "Its menu entry goes too. Files you made with it stay."
        choices: [{ text: "Remove", accent: Party.red, run: () => backend.remove(row.app.id) }]
    }
}

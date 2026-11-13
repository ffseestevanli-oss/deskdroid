// One app from all of Flathub (FlathubCatalog.kt's search): icon, name, what
// it is, which build Agora would install (ARM64, or x86-64 through FEX), and
// Install / Open / Remove with the flatpak command. A click opens its page.
// Compact: one line, for the desktop's long lists. Why an install failed
// shows under the app.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "."

Item {
    id: row
    property var hit: ({})
    property bool compact: false
    readonly property string failure: backend.failures["flatpak:" + hit.id] || ""
    readonly property var installedAs: backend.flatpaks[hit.id]
    readonly property bool installed: installedAs !== undefined
    readonly property var progress: backend.busy["flatpak:" + hit.id]
    readonly property bool working: progress !== undefined
    // "" (this machine's own build), "x86_64" (through FEX) or "none".
    readonly property string arch: backend.archFor(hit.arches || [])
    readonly property color accent: installed ? Party.green : arch === "none" ? Party.dim : arch === "" ? Party.cyan : Party.orange
    implicitHeight: layout.implicitHeight + (compact ? 12 : 28)

    Chamfer {
        anchors.fill: parent
        cut: row.compact ? 7 : 12
        cutTopLeft: false
        fillColor: hover.hovered ? Party.surface : Party.card
        strokeColor: hover.hovered ? row.accent : Party.borderSoft
        strokeWidth: 1.5
    }
    Rectangle { width: 3; height: parent.height; color: row.accent }
    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: applicationWindow().showFlathubApp(row.hit) }

    RowLayout {
        id: layout
        anchors.fill: parent
        anchors.margins: row.compact ? 6 : 14
        anchors.leftMargin: row.compact ? 12 : 20
        spacing: row.compact ? 10 : 16

        Item {
            Layout.preferredWidth: row.compact ? 32 : 56
            Layout.preferredHeight: row.compact ? 32 : 56
            Layout.alignment: Qt.AlignTop
            Image {
                id: img
                anchors.fill: parent
                source: row.hit.icon ? "file://" + row.hit.icon : ""
                sourceSize: Qt.size(112, 112)
                fillMode: Image.PreserveAspectFit
                smooth: true
                visible: status === Image.Ready
            }
            Kirigami.Icon {
                anchors.fill: parent
                visible: !img.visible
                source: row.hit.id || "application-x-executable"
                fallback: "application-x-executable"
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Text {
                    text: row.hit.name || row.hit.id || ""
                    font.family: Party.body; font.weight: Font.Bold; font.pixelSize: row.compact ? 15 : 17
                    color: Party.text
                    elide: Text.ElideRight
                    Layout.maximumWidth: row.compact ? 260 : implicitWidth
                }
                // Compact: what it is, on the same line.
                Text {
                    visible: row.compact
                    text: row.hit.summary || ""
                    font.family: Party.body; font.pixelSize: 13
                    color: Party.muted
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
                Item { visible: !row.compact; Layout.fillWidth: true }
                ArchBadge { visible: row.compact; arches: row.hit.arches || []; installedArch: row.installed ? row.installedAs.arch : "" }
            }
            Text {
                visible: !row.compact && text !== ""
                text: row.hit.summary || ""
                font.family: Party.body; font.pixelSize: 14
                color: Party.muted
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
            Flow {
                visible: !row.compact
                Layout.fillWidth: true
                spacing: 10
                ArchBadge { arches: row.hit.arches || []; installedArch: row.installed ? row.installedAs.arch : "" }
                Text {
                    text: {
                        const bits = []
                        if (row.hit.developer) bits.push(row.hit.developer + (row.hit.verified ? " ✓" : ""))
                        if (row.installed) bits.push("installed" + (row.installedAs.version ? " " + row.installedAs.version : ""))
                        return bits.join("  ·  ")
                    }
                    visible: text !== ""
                    font.family: Party.body; font.pixelSize: 12
                    color: Party.dim
                }
            }
            Text {
                visible: row.failure !== "" && !row.working
                text: "Couldn't install: " + row.failure
                font.family: Party.body; font.pixelSize: 12
                color: Party.red
                wrapMode: Text.WordWrap
                maximumLineCount: 3
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
            RainbowBar {
                visible: row.working
                fraction: row.progress >= 0 ? row.progress : 0
                indeterminate: !(row.progress >= 0)
                implicitHeight: row.compact ? 10 : 18
                segments: 24
                Layout.fillWidth: true
                Layout.maximumWidth: 420
                Layout.topMargin: 6
            }
        }
        Text {
            visible: row.working
            text: row.progress >= 0 ? Math.round(row.progress * 100) + "%" : (row.installed ? "Working…" : "Installing…")
            font.family: Party.heading; font.weight: Font.Black; font.pixelSize: 14
            color: Party.text
        }
        PartyButton {
            visible: !row.working && row.installed
            compact: true
            implicitHeight: row.compact ? 28 : 34
            text: "Open"
            accent: Party.green
            onClicked: backend.launchFlatpak(row.hit.id)
        }
        PartyButton {
            visible: !row.working && !row.installed && row.arch !== "none"
            enabled: backend.flatpakAvailable
            compact: true
            implicitHeight: row.compact ? 28 : 34
            text: row.failure !== "" ? "Try again" : "Install"
            accent: row.arch === "" ? Party.cyan : Party.orange
            onClicked: backend.installFlatpak(row.hit.id, row.arch)
        }
        PartyButton {
            visible: !row.working && row.installed
            compact: true
            implicitHeight: row.compact ? 28 : 34
            text: "Remove"
            accent: Party.red
            onClicked: confirm.open()
        }
    }

    PartyDialog {
        id: confirm
        title: "Remove " + (row.hit.name || row.hit.id) + "?"
        text: "Its menu entry goes too. Its settings and files stay in ~/.var/app/" + row.hit.id + "."
        choices: [{ text: "Remove", accent: Party.red, run: () => backend.removeFlatpak(row.hit.id) }]
    }
}

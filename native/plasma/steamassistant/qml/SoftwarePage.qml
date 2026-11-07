// Manage Software (Add/Remove Programs): Steam's games, and the Windows
// programs installed in DeskDroid's own prefix.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "."

PartyPage {
    id: page
    title: "Manage Software"
    glows: [[0.0, 0.1, Party.yellow], [1.0, 0.9, Party.pink]]
    property var games: backend.games()

    function size(bytes) {
        if (!bytes) return ""
        const gb = bytes / 1e9
        return gb >= 1 ? gb.toFixed(1) + " GB" : Math.max(1, Math.round(bytes / 1e6)) + " MB"
    }

    ColumnLayout {
        spacing: 14
        width: Math.min(page.width - page.leftPadding - page.rightPadding, 900)
        x: Math.max(0, (page.width - page.leftPadding - page.rightPadding - width) / 2)

        BackHeader { title: page.title }

        Text {
            text: "—  WINDOWS PROGRAMS  —"
            font.family: Party.heading; font.weight: Font.Black; font.pixelSize: 14; font.letterSpacing: 3
            color: Party.green
        }
        Text {
            text: "Programs you installed with \"Run a Windows application\" live in DeskDroid's Windows folder. Wine's own Add/Remove Programs lists and removes them."
            font.family: Party.body; font.pixelSize: 15
            color: Party.textSoft
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }
        Flow {
            Layout.fillWidth: true
            spacing: 12
            PartyButton {
                text: "Add/Remove Programs"
                accent: Party.green
                enabled: backend.fexReady
                onClicked: backend.wineTool("uninstaller")
            }
            PartyButton {
                text: "Browse the Windows folder"
                onClicked: backend.openFolder(backend.steamDir().replace(/\/Steam$/, "") + "/deskdroid-wine/default/pfx/drive_c")
            }
        }

        Text {
            text: "—  STEAM LIBRARY  —"
            font.family: Party.heading; font.weight: Font.Black; font.pixelSize: 14; font.letterSpacing: 3
            color: Party.pink
            Layout.topMargin: 12
        }
        Text {
            visible: page.games.length === 0
            text: backend.steamReady ? "No games installed yet. Install them from Steam's library." : "Steam isn't installed."
            font.family: Party.body; font.pixelSize: 15
            color: Party.muted
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }
        Repeater {
            model: page.games
            Item {
                Layout.fillWidth: true
                implicitHeight: row.implicitHeight + 24
                Chamfer { anchors.fill: parent; cut: 10; cutTopLeft: false; fillColor: Party.surface }
                Rectangle { width: 3; height: parent.height; color: modelData.tool ? Party.purple : Party.yellow }
                RowLayout {
                    id: row
                    anchors.fill: parent
                    anchors.margins: 12
                    anchors.leftMargin: 18
                    spacing: 10
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Text {
                            text: modelData.name
                            font.family: Party.body; font.weight: Font.Bold; font.pixelSize: 16
                            color: Party.text
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        Text {
                            text: (modelData.tool ? "Tool" : "Game") + "  ·  " + modelData.appid + (modelData.size ? "  ·  " + page.size(modelData.size) : "")
                            font.family: Party.body; font.pixelSize: 12
                            color: Party.dim
                            Layout.fillWidth: true
                        }
                    }
                    PartyButton {
                        visible: !modelData.tool
                        compact: true
                        text: "Play"
                        onClicked: backend.launchSteam("steam://rungameid/" + modelData.appid)
                    }
                    PartyButton {
                        compact: true
                        text: "Uninstall"
                        // Steam asks first and does the removing.
                        onClicked: backend.launchSteam("steam://uninstall/" + modelData.appid)
                    }
                }
            }
        }
        PartyButton {
            text: "Refresh"
            onClicked: page.games = backend.games()
        }
    }
}

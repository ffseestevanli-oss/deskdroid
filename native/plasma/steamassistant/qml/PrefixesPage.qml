// Manage Proton: the Wine prefixes Steam's games and DeskDroid's Windows apps use.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "."

PartyPage {
    id: page
    title: "Manage Proton"
    glows: [[0.0, 0.1, Party.purple], [1.0, 0.9, Party.cyan]]
    property var prefixes: backend.prefixes()

    function reload() { prefixes = backend.prefixes() }

    PartyDialog {
        id: deleteDialog
        property var prefix: ({})
        title: "Delete this prefix?"
        text: "Deletes " + (prefix.name || "") + "'s Windows folder, with the settings and saves kept there. A new one is made the next time it runs."
        choices: [{ text: "Delete", accent: Party.red, run: function () {
            if (!backend.removeFolder(deleteDialog.prefix.path))
                applicationWindow().showPassiveNotification("Couldn't delete it")
            page.reload()
        } }]
    }

    ColumnLayout {
        spacing: 14
        width: Math.min(page.width - page.leftPadding - page.rightPadding, 900)
        x: Math.max(0, (page.width - page.leftPadding - page.rightPadding - width) / 2)

        BackHeader { title: page.title }

        Text {
            text: "Proton runs Windows games and apps with Wine, through FEX-Emu. Each game gets a Windows folder of its own (a prefix); DeskDroid's own Windows apps share one."
            font.family: Party.body; font.pixelSize: 15
            color: Party.textSoft
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }
        Text {
            visible: !backend.hasProton()
            text: "No Proton yet: in Steam, open Library › Tools and install Proton (the newest, or Experimental)."
            font.family: Party.body; font.weight: Font.Bold; font.pixelSize: 15
            color: Party.yellow
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }
        Flow {
            Layout.fillWidth: true
            spacing: 12
            PartyButton {
                text: "Wine settings (Windows apps)"
                accent: Party.purple
                onClicked: backend.wineTool("winecfg")
            }
            PartyButton {
                text: "Refresh"
                onClicked: page.reload()
            }
        }
        Text {
            visible: page.prefixes.length === 0
            text: "No prefixes yet. They appear after a Windows game or app has run once."
            font.family: Party.body; font.pixelSize: 15
            color: Party.muted
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
            Layout.topMargin: 10
        }
        Repeater {
            model: page.prefixes
            Item {
                Layout.fillWidth: true
                implicitHeight: row.implicitHeight + 24
                Chamfer { anchors.fill: parent; cut: 10; cutTopLeft: false; fillColor: Party.surface }
                Rectangle { width: 3; height: parent.height; color: modelData.kind === "steam" ? Party.pink : Party.cyan }
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
                            text: (modelData.kind === "steam" ? "Steam game " + modelData.appid : "DeskDroid") + "  ·  " + modelData.path
                            font.family: Party.body; font.pixelSize: 12
                            color: Party.dim
                            elide: Text.ElideMiddle
                            Layout.fillWidth: true
                        }
                    }
                    PartyButton {
                        compact: true
                        text: "Open"
                        onClicked: backend.openFolder(modelData.path + "/pfx/drive_c")
                    }
                    PartyButton {
                        compact: true
                        text: "Configure"
                        onClicked: backend.wineTool("winecfg", modelData.path)
                    }
                    PartyButton {
                        compact: true
                        text: "Delete"
                        onClicked: { deleteDialog.prefix = modelData; deleteDialog.open() }
                    }
                }
            }
        }
    }
}

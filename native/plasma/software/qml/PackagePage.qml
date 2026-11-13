// An .adpk opened in Software (a double-click on one in Dolphin, or "Install
// from a file…"): what it is, and Install, Update or Reinstall.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "."

PartyPage {
    id: page
    title: "Install a package"
    glows: [[0.1, 0.1, Party.purple], [0.9, 0.9, Party.green]]
    property string path: ""
    readonly property var pkg: backend.package
    readonly property bool ready: pkg.id !== undefined
    readonly property bool invalid: pkg.invalid === true
    readonly property bool installedBefore: ready && pkg.installed !== null && pkg.installed !== undefined
    readonly property var progress: backend.busy["file:" + path]
    readonly property bool working: progress !== undefined
    readonly property bool done: pkg.done === true
    readonly property string fileName: path.split("/").pop()
    readonly property string verb: !installedBefore ? "Install" : pkg.installed === pkg.version ? "Reinstall" : "Update"

    ColumnLayout {
        spacing: 18
        width: Math.min(page.width - page.leftPadding - page.rightPadding, 760)
        x: Math.max(0, (page.width - page.leftPadding - page.rightPadding - width) / 2)

        PartyButton {
            text: "‹  All apps"
            compact: true
            onClicked: applicationWindow().showBrowse()
        }
        Text {
            text: "—  DESKDROID PACKAGE  —"
            font.family: Party.heading; font.weight: Font.Black; font.pixelSize: 14; font.letterSpacing: 3
            color: Party.purple
        }

        Item {
            Layout.fillWidth: true
            implicitHeight: card.implicitHeight + 48
            Chamfer {
                anchors.fill: parent
                cut: 18
                fillColor: Party.surface
                rainbowStroke: true
                strokeWidth: 2
            }
            ColumnLayout {
                id: card
                anchors.fill: parent
                anchors.margins: 24
                spacing: 14
                RowLayout {
                    spacing: 18
                    Layout.fillWidth: true
                    Item {
                        Layout.preferredWidth: 96
                        Layout.preferredHeight: 96
                        Image {
                            id: icon
                            anchors.fill: parent
                            source: page.pkg.icon ? "file://" + page.pkg.icon : ""
                            sourceSize: Qt.size(192, 192)
                            fillMode: Image.PreserveAspectFit
                            visible: status === Image.Ready
                        }
                        Kirigami.Icon {
                            anchors.fill: parent
                            visible: !icon.visible
                            source: "package-x-generic"
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        RainbowText {
                            heading: page.ready ? page.pkg.name : page.invalid ? "Can't open this file" : "Reading the package…"
                            size: 28
                            Layout.fillWidth: true
                        }
                        Text {
                            visible: text !== ""
                            text: page.ready ? (page.pkg.summary || "") : ""
                            font.family: Party.body; font.pixelSize: 16
                            color: Party.textSoft
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }
                        Text {
                            text: {
                                if (!page.ready) return page.fileName
                                const bits = []
                                if (page.pkg.version) bits.push("Version " + page.pkg.version)
                                if (page.installedBefore) bits.push("installed: " + (page.pkg.installed || "unknown version"))
                                bits.push(page.fileName)
                                return bits.join("  ·  ")
                            }
                            font.family: Party.body; font.pixelSize: 13
                            color: Party.dim
                            wrapMode: Text.WrapAnywhere
                            Layout.fillWidth: true
                        }
                    }
                }
                RainbowBar {
                    visible: !page.ready && !page.invalid && !backend.offline || page.working
                    indeterminate: !(page.progress >= 0)
                    fraction: page.progress >= 0 ? page.progress : 0
                    Layout.fillWidth: true
                }
                Text {
                    visible: text !== ""
                    text: backend.offline ? "DeskDroid's app isn't answering, so nothing can be installed right now."
                        : page.invalid ? backend.error
                        : page.done ? page.pkg.name + " is installed. It's in the menu now."
                        : page.working ? "Installing " + page.pkg.name + "…"
                        : page.ready ? "From a file, not from the Agora catalog: install packages only from people you trust."
                        : ""
                    font.family: Party.body; font.pixelSize: 15
                    color: page.invalid || backend.offline ? Party.orange : page.done ? Party.green : Party.muted
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }
                Kirigami.InlineMessage {
                    Layout.fillWidth: true
                    visible: page.ready && !page.working && backend.error !== ""
                    type: Kirigami.MessageType.Error
                    text: backend.error
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: 12
                    PartyButton {
                        visible: page.ready && !page.done
                        primary: true
                        enabled: !page.working
                        text: page.verb
                        onClicked: backend.installPackage(page.path)
                    }
                    PartyButton {
                        visible: page.done
                        primary: true
                        text: "Open " + (page.pkg.name || "")
                        onClicked: backend.launch(page.pkg.id)
                    }
                    PartyButton {
                        text: page.done || page.invalid ? "Close" : "Cancel"
                        enabled: !page.working
                        onClicked: Qt.quit()
                    }
                }
            }
        }
    }
}

// A Flatpak file opened in Agora (a double-click in Dolphin, a download from
// a website, or "Install from a file…"): a .flatpakref (one app, from its
// repository), a .flatpakrepo (a repository to add) or a .flatpak bundle (an
// app in one file). What it is, and Install / Add with the flatpak command.
// An app its repository only builds for x86-64 installs that build, which
// runs through FEX.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "."

PartyPage {
    id: page
    title: "Install from Flatpak"
    glows: [[0.1, 0.1, Party.green], [0.9, 0.9, Party.purple]]
    property string path: ""
    readonly property var f: backend.flatpakFile
    readonly property bool ready: f.path === path && !f.invalid
    readonly property bool invalid: f.invalid === true
    readonly property bool repo: f.kind === "repo"
    readonly property var progress: backend.busy["file:" + path]
    readonly property bool working: progress !== undefined
    readonly property bool done: f.done === true
    readonly property string fileName: path.split("/").pop()
    readonly property string name: f.title || f.name || fileName

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
            text: page.repo ? "—  FLATPAK REPOSITORY  —" : f.kind === "bundle" ? "—  FLATPAK BUNDLE  —" : "—  FLATPAK APP  —"
            font.family: Party.heading; font.weight: Font.Black; font.pixelSize: 14; font.letterSpacing: 3
            color: Party.green
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
                            source: page.f.icon || ""
                            sourceSize: Qt.size(192, 192)
                            fillMode: Image.PreserveAspectFit
                            visible: status === Image.Ready
                        }
                        Kirigami.Icon {
                            anchors.fill: parent
                            visible: !icon.visible
                            source: page.f.name || (page.repo ? "application-vnd.flatpak.repo" : "application-vnd.flatpak.ref")
                            fallback: "application-vnd.flatpak"
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        RainbowText {
                            heading: page.invalid ? "Can't open this file" : page.ready ? page.name : "Reading the file…"
                            size: 28
                            Layout.fillWidth: true
                        }
                        Text {
                            visible: text !== ""
                            text: page.ready ? (page.f.summary || "") : ""
                            font.family: Party.body; font.pixelSize: 16
                            color: Party.textSoft
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }
                        Text {
                            text: {
                                const bits = []
                                if (page.f.name && page.f.name !== page.name) bits.push(page.f.name)
                                if (page.f.branch) bits.push("branch " + page.f.branch)
                                if (page.f.url) bits.push(page.f.url.replace(/^https?:\/\//, "").replace(/\/$/, ""))
                                if (page.f.installed) bits.push("installed")
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
                    visible: page.working
                    indeterminate: !(page.progress >= 0)
                    fraction: page.progress >= 0 ? page.progress : 0
                    Layout.fillWidth: true
                }
                Text {
                    visible: text !== ""
                    text: !backend.flatpakAvailable ? "The flatpak command isn't on this desktop, so Agora can't install this. Update DeskDroid."
                        : page.invalid ? backend.error
                        : page.done ? (page.repo ? page.name + " is added. Its apps install with the flatpak command now."
                                                 : page.name + " is installed. It's in the menu now.")
                        : page.working ? (page.repo ? "Adding " : "Installing ") + page.name + "… The first install of a runtime takes a while."
                        : page.ready ? (page.repo ? "A repository other than Flathub: add only ones from people you trust."
                                                  : "From " + (page.f.url ? page.f.url.replace(/^https?:\/\//, "").split("/")[0] : "a file")
                                                    + ". Agora installs the ARM64 build, or the x86-64 one (through FEX) when that's the only one. Install apps only from people you trust.")
                        : ""
                    font.family: Party.body; font.pixelSize: 15
                    color: page.invalid || !backend.flatpakAvailable ? Party.orange : page.done ? Party.green : Party.muted
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }
                Text {
                    visible: page.ready && (page.f.description || "") !== ""
                    text: page.f.description || ""
                    font.family: Party.body; font.pixelSize: 14
                    color: Party.textSoft
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
                        visible: page.ready && !page.done && !(page.f.installed && !page.repo)
                        primary: true
                        enabled: !page.working && backend.flatpakAvailable
                        text: page.repo ? "Add repository" : "Install"
                        onClicked: backend.installFlatpakFile(page.path)
                    }
                    PartyButton {
                        visible: !page.repo && page.ready && (page.done || page.f.installed) && page.f.name
                        primary: true
                        text: "Open " + page.name
                        onClicked: backend.launchFlatpak(page.f.name)
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

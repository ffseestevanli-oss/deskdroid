// A Flathub app's page, over the catalog: what it is (Flathub's AppStream
// description), who makes it, which build runs here, and Install / Open /
// Remove with the flatpak command.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "."

PartyPage {
    id: page
    title: hit.name || "Flathub"
    glows: [[0.1, 0.1, Party.green], [0.9, 0.9, page.arch === "" ? Party.cyan : Party.orange]]
    property var hit: ({})
    readonly property var installedAs: backend.flatpaks[hit.id]
    readonly property bool installed: installedAs !== undefined
    readonly property var progress: backend.busy["flatpak:" + hit.id]
    readonly property bool working: progress !== undefined
    readonly property string arch: backend.archFor(hit.arches || [])

    ColumnLayout {
        spacing: 18
        width: Math.min(page.width - page.leftPadding - page.rightPadding, 820)
        x: Math.max(0, (page.width - page.leftPadding - page.rightPadding - width) / 2)

        PartyButton {
            text: "‹  Flathub"
            compact: true
            onClicked: applicationWindow().back()
        }
        Text {
            text: "—  FROM FLATHUB  —"
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
                        Layout.alignment: Qt.AlignTop
                        Image {
                            id: icon
                            anchors.fill: parent
                            source: page.hit.icon ? "file://" + page.hit.icon : ""
                            sourceSize: Qt.size(192, 192)
                            fillMode: Image.PreserveAspectFit
                            visible: status === Image.Ready
                        }
                        Kirigami.Icon {
                            anchors.fill: parent
                            visible: !icon.visible
                            source: page.hit.id || "application-x-executable"
                            fallback: "application-x-executable"
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        RainbowText { heading: page.hit.name || page.hit.id || ""; size: 28; Layout.fillWidth: true }
                        Text {
                            visible: text !== ""
                            text: page.hit.summary || ""
                            font.family: Party.body; font.pixelSize: 16
                            color: Party.textSoft
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }
                        Flow {
                            Layout.fillWidth: true
                            spacing: 10
                            ArchBadge { arches: page.hit.arches || []; installedArch: page.installed ? page.installedAs.arch : "" }
                            Text {
                                text: {
                                    const bits = []
                                    if (page.hit.developer) bits.push(page.hit.developer + (page.hit.verified ? " ✓ verified" : ""))
                                    if (page.hit.license) bits.push(page.hit.license.startsWith("LicenseRef-proprietary") ? "Proprietary" : page.hit.license)
                                    if (page.hit.installs) bits.push(page.hit.installs.toLocaleString(Qt.locale(), "f", 0) + " installs last month")
                                    if (page.installed) bits.push("installed" + (page.installedAs.version ? " " + page.installedAs.version : ""))
                                    return bits.join("  ·  ")
                                }
                                font.family: Party.body; font.pixelSize: 13
                                color: Party.dim
                                wrapMode: Text.WordWrap
                            }
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
                    text: page.working ? (page.installed ? "Working on " : "Installing ") + (page.hit.name || page.hit.id) + "… The first install of a runtime takes a while."
                        : page.arch === "none" ? "Flathub has no build of this app for this device (only " + (page.hit.arches || []).join(", ") + ")."
                        : page.arch === "x86_64" ? "Flathub only builds this app for x86-64 PCs. DeskDroid runs it through FEX, which translates it as it runs: it works, more slowly than an ARM64 app. FEX is set up in the Steam Installation Assistant."
                        : "Flathub's own ARM64 build, unchanged. ddmask runs it on the phone; Agora installs the runtime it needs with it."
                    font.family: Party.body; font.pixelSize: 14
                    color: page.arch === "none" ? Party.orange : Party.muted
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }
                Text {
                    visible: !backend.flatpakAvailable
                    text: "The flatpak command isn't on this desktop, so Agora can't install Flathub apps here. Update DeskDroid."
                    font.family: Party.body; font.pixelSize: 14
                    color: Party.orange
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }
                Kirigami.InlineMessage {
                    Layout.fillWidth: true
                    readonly property string failure: backend.failures["flatpak:" + page.hit.id] || ""
                    visible: !page.working && failure !== ""
                    type: Kirigami.MessageType.Error
                    text: "Couldn't install " + (page.hit.name || page.hit.id) + ": " + failure
                        + "\nWhat flatpak said is in the saved log (\"Save log to Downloads\" in the DeskDroid app)."
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: 12
                    PartyButton {
                        visible: !page.installed && page.arch !== "none"
                        primary: true
                        enabled: !page.working && backend.flatpakAvailable
                        text: page.arch === "x86_64" ? "Install (x86-64)" : "Install"
                        onClicked: backend.installFlatpak(page.hit.id, page.arch)
                    }
                    PartyButton {
                        visible: page.installed
                        primary: true
                        enabled: !page.working
                        text: "Open"
                        onClicked: backend.launchFlatpak(page.hit.id)
                    }
                    PartyButton {
                        visible: page.installed
                        enabled: !page.working
                        text: "Remove"
                        accent: Party.red
                        onClicked: confirm.open()
                    }
                    PartyButton {
                        text: "On flathub.org"
                        accent: Party.green
                        onClicked: Qt.openUrlExternally("https://flathub.org/apps/" + page.hit.id)
                    }
                }
            }
        }

        Text {
            visible: (page.hit.description || "") !== ""
            text: "—  ABOUT  —"
            font.family: Party.heading; font.weight: Font.Black; font.pixelSize: 14; font.letterSpacing: 3
            color: Party.cyan
        }
        Text {
            visible: text !== ""
            text: page.hit.description || ""
            font.family: Party.body; font.pixelSize: 15
            color: Party.textSoft
            wrapMode: Text.WordWrap
            lineHeight: 1.15
            Layout.fillWidth: true
        }
    }

    PartyDialog {
        id: confirm
        title: "Remove " + (page.hit.name || page.hit.id) + "?"
        text: "Its menu entry goes too. Its settings and files stay in ~/.var/app/" + page.hit.id + "."
        choices: [{ text: "Remove", accent: Party.red, run: () => backend.removeFlatpak(page.hit.id) }]
    }
}

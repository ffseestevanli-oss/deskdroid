// Software's main page, in tabs: DeskDroid Repo (apps built for DeskDroid),
// Flathub (Flathub's own ARM64 builds, run through ddmask), Dependencies
// (the runtimes Flathub apps need) and About. Each list is A to Z, with a
// search field and an "installed only" switch.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "."

PartyPage {
    id: page
    title: "Agora"
    glows: [[0.05, 0.05, tab.accent], [0.95, 0.95, Party.pink]]
    property string filter: ""
    property bool installedOnly: false
    property string current: "deskdroid"

    readonly property var tabs: [
        { id: "deskdroid", label: "DeskDroid Repo", accent: Party.cyan,
          intro: "Apps built for DeskDroid: KDE apps, DeskDroid's own, and themes. They run at full speed with the phone's GPU." },
        { id: "flathub", label: "Flathub", accent: Party.green,
          intro: "Flathub's own ARM64 builds, unchanged. ddmask translates them as they run, so nothing is recompiled. Each needs a runtime from Dependencies, which Agora installs with it." },
        { id: "dependencies", label: "Dependencies", accent: Party.purple,
          intro: "Runtimes: the shared libraries Flathub apps run on (KDE, GNOME, Freedesktop, Mesa for graphics). Agora installs them when an app needs them; you rarely need to install one yourself." },
        { id: "about", label: "About", accent: Party.yellow, intro: "" },
    ]
    readonly property var tab: tabs.find(t => t.id === current) || tabs[0]

    function isInstalled(a) { return a.installed !== null && a.installed !== undefined }
    function sectionOf(a) { return a.section || "deskdroid" }
    function inTab(id) { return backend.apps.filter(a => sectionOf(a) === id) }
    function updatesIn(list) { return list.filter(a => isInstalled(a) && !a.local && a.installed !== a.version).length }

    readonly property var names: {
        const m = {}
        for (const a of backend.apps) m[a.id] = a.name
        return m
    }
    readonly property var shown: inTab(current).filter(a => {
        if (page.installedOnly && !isInstalled(a)) return false
        const f = page.filter.trim().toLowerCase()
        return f === "" || (a.name + " " + a.summary + " " + a.id).toLowerCase().indexOf(f) >= 0
    })

    ColumnLayout {
        spacing: 16
        width: Math.min(page.width - page.leftPadding - page.rightPadding, 980)
        x: Math.max(0, (page.width - page.leftPadding - page.rightPadding - width) / 2)

        RowLayout {
            Layout.fillWidth: true
            spacing: 16
            Image {
                source: "qrc:/icon.svg"
                sourceSize: Qt.size(112, 112)
                Layout.preferredWidth: 56
                Layout.preferredHeight: 56
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                RainbowText { heading: "Agora"; size: 38; Layout.fillWidth: true }
                Text {
                    text: "Find, install and update apps for DeskDroid."
                    font.family: Party.body; font.pixelSize: 15
                    color: Party.textSoft
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }
            }
        }

        // The tabs.
        Flow {
            Layout.fillWidth: true
            spacing: 8
            Repeater {
                model: page.tabs
                QQC2.AbstractButton {
                    id: tabButton
                    readonly property bool active: page.current === modelData.id
                    readonly property var list: modelData.id === "about" ? [] : page.inTab(modelData.id)
                    readonly property int updates: page.updatesIn(list)
                    implicitHeight: 48
                    implicitWidth: tabLabel.implicitWidth + 40
                    hoverEnabled: true
                    focusPolicy: Qt.StrongFocus
                    onClicked: page.current = modelData.id
                    background: Item {
                        Chamfer {
                            anchors.fill: parent
                            cut: 10
                            cutTopLeft: false
                            fillColor: tabButton.active ? Party.cardOn : tabButton.hovered ? Party.surface : Party.surfaceDim
                            strokeColor: tabButton.active || tabButton.hovered || tabButton.visualFocus ? modelData.accent : Party.border
                            strokeWidth: 1.5
                        }
                        Rectangle {
                            visible: tabButton.active
                            anchors.bottom: parent.bottom
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.margins: 6
                            height: 3
                            color: modelData.accent
                        }
                    }
                    contentItem: Text {
                        id: tabLabel
                        text: modelData.label
                            + (tabButton.list.length ? "  " + tabButton.list.length : "")
                            + (tabButton.updates ? "  ·  " + tabButton.updates + " ↑" : "")
                        font.family: Party.heading
                        font.weight: Font.Black
                        font.pixelSize: 13
                        font.letterSpacing: 1.2
                        color: tabButton.active ? modelData.accent : Party.textSoft
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }
        }

        // What the tab is.
        Text {
            visible: page.tab.intro !== ""
            text: page.tab.intro
            font.family: Party.body; font.pixelSize: 14
            color: Party.muted
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }

        // Search and actions (not on About).
        Flow {
            visible: page.current !== "about"
            Layout.fillWidth: true
            spacing: 10
            QQC2.TextField {
                id: search
                width: Math.min(360, page.width - 80)
                height: 44
                placeholderText: "Search " + page.tab.label
                font.family: Party.body
                font.pixelSize: 15
                color: Party.text
                leftPadding: 14
                onTextChanged: page.filter = text
                background: Chamfer {
                    cut: 10
                    fillColor: Party.surfaceDim
                    strokeColor: search.activeFocus ? page.tab.accent : Party.border
                    strokeWidth: 1.5
                }
            }
            PartyButton {
                text: page.installedOnly ? "Installed only" : "Everything"
                accent: page.installedOnly ? Party.green : Party.border
                onClicked: page.installedOnly = !page.installedOnly
            }
            PartyButton {
                text: "Install from a file…"
                accent: Party.purple
                onClicked: applicationWindow().chooseFile()
            }
            PartyButton {
                text: "Refresh"
                onClicked: backend.refresh()
            }
        }

        // Problems and states.
        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: backend.error !== ""
            type: Kirigami.MessageType.Error
            text: backend.error
            showCloseButton: true
        }
        Text {
            visible: backend.offline || backend.catalogError !== "" || (backend.loading && backend.apps.length === 0)
            text: backend.offline
                ? "DeskDroid's app isn't answering. Agora needs the DeskDroid app running behind the desktop; try again in a moment."
                : backend.catalogError !== ""
                    ? "Couldn't reach the Agora catalog (" + backend.catalogError + "). Check the phone's internet connection, then Refresh." + (backend.apps.length ? " Showing what was there last time." : "")
                    : "Loading the catalog…"
            font.family: Party.body; font.pixelSize: 15
            color: backend.offline || backend.catalogError !== "" ? Party.orange : Party.muted
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }
        RainbowBar {
            visible: backend.loading && backend.apps.length === 0
            indeterminate: true
            Layout.fillWidth: true
        }

        // The list.
        Text {
            visible: page.current !== "about" && page.updatesIn(page.inTab(page.current)) > 0
            readonly property int n: page.updatesIn(page.inTab(page.current))
            text: "—  " + n + (n === 1 ? " UPDATE" : " UPDATES") + " READY  —"
            font.family: Party.heading; font.weight: Font.Black; font.pixelSize: 14; font.letterSpacing: 3
            color: Party.yellow
        }
        Text {
            visible: page.current !== "about" && backend.apps.length > 0 && page.shown.length === 0
            text: page.filter !== "" ? "Nothing in " + page.tab.label + " matches \"" + page.filter + "\"."
                : page.installedOnly ? "Nothing from " + page.tab.label + " is installed yet."
                : page.current === "flathub" ? "No Flathub apps in this catalog yet."
                : "Nothing here yet."
            font.family: Party.body; font.pixelSize: 15
            color: Party.muted
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }
        Repeater {
            model: page.current === "about" ? [] : page.shown
            AppRow {
                Layout.fillWidth: true
                app: modelData
                names: page.names
                progress: backend.busy[modelData.id]
            }
        }

        // About.
        AboutPane {
            visible: page.current === "about"
            Layout.fillWidth: true
            counts: ({
                deskdroid: page.inTab("deskdroid").length,
                flathub: page.inTab("flathub").length,
                dependencies: page.inTab("dependencies").length,
                installed: backend.apps.filter(a => page.isInstalled(a)).length,
            })
        }
    }
}

// Software's main page, in tabs: DeskDroid Repo (apps built for DeskDroid),
// Flathub (all of Flathub, through its API, installed with the flatpak
// command; ARM64 builds run through ddmask, x86-64-only ones through FEX;
// the packages DeskDroid tested come first), Dependencies
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
          intro: "All of Flathub, unchanged. Apps with an ARM64 build run through ddmask at full speed; apps Flathub only builds for x86-64 run through FEX, more slowly. Agora installs the runtime each one needs with it." },
        { id: "dependencies", label: "Dependencies", accent: Party.purple,
          intro: "Runtimes: the shared libraries Flathub apps run on (KDE, GNOME, Freedesktop, Mesa for graphics). Agora installs them when an app needs them; you rarely need to install one yourself." },
        { id: "about", label: "About", accent: Party.yellow, intro: "" },
    ]
    readonly property var tab: tabs.find(t => t.id === current) || tabs[0]

    // All of Flathub (backend.flathub, FlathubCatalog.kt): Flathub's own
    // main categories, searched as the search field changes.
    readonly property var categories: [
        { id: "", label: "Popular" }, { id: "AudioVideo", label: "Audio & Video" },
        { id: "Development", label: "Developer" }, { id: "Education", label: "Education" },
        { id: "Game", label: "Games" }, { id: "Graphics", label: "Graphics" },
        { id: "Network", label: "Internet" }, { id: "Office", label: "Office" },
        { id: "Science", label: "Science" }, { id: "System", label: "System" },
        { id: "Utility", label: "Utilities" },
    ]
    property string category: ""
    readonly property var flathub: backend.flathub
    readonly property var flathubResults: flathub.results || []
    readonly property var flathubShown: {
        if (!page.installedOnly) return flathubResults
        // Installed only: every Flathub app the flatpak command installed,
        // with what the last search knew about it.
        const known = {}
        for (const h of flathubResults) known[h.id] = h
        return Object.keys(backend.flatpaks).sort().map(id => known[id] || { id: id, name: id, summary: "", arches: [backend.flatpaks[id].arch] })
            .filter(h => {
                const f = page.filter.trim().toLowerCase()
                return f === "" || (h.name + " " + h.summary + " " + h.id).toLowerCase().indexOf(f) >= 0
            })
    }
    function searchFlathub(more) {
        const pageNo = more ? (flathub.page || 1) + 1 : 1
        backend.searchFlathub(page.filter.trim(), page.category, pageNo)
    }
    // Asked again when the tab opens with a search Flathub hasn't answered.
    onCurrentChanged: if (current === "flathub" && (flathubResults.length === 0 || (flathub.query || "") !== filter.trim()
                                                    || (flathub.category || "") !== category) && !flathub.loading) searchFlathub(false)
    onCategoryChanged: searchFlathub(false)
    Timer {
        id: searchDelay
        interval: 450
        onTriggered: if (page.current === "flathub") page.searchFlathub(false)
    }
    onFilterChanged: searchDelay.restart()

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
                visible: page.current === "flathub" && Object.keys(backend.flatpaks).length > 0
                text: backend.busy["flatpak:*"] !== undefined ? "Updating…" : "Update Flathub apps"
                enabled: backend.busy["flatpak:*"] === undefined
                accent: Party.yellow
                onClicked: backend.updateFlatpaks()
            }
            PartyButton {
                text: "Refresh"
                onClicked: { backend.refresh(); backend.refreshFlatpaks(); if (page.current === "flathub") page.searchFlathub(false) }
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
            visible: page.current !== "about" && page.current !== "flathub" && backend.apps.length > 0 && page.shown.length === 0
            text: page.filter !== "" ? "Nothing in " + page.tab.label + " matches \"" + page.filter + "\"."
                : page.installedOnly ? "Nothing from " + page.tab.label + " is installed yet."
                : page.current === "flathub" ? "No Flathub apps in this catalog yet."
                : "Nothing here yet."
            font.family: Party.body; font.pixelSize: 15
            color: Party.muted
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }
        // Flathub: the packages DeskDroid tested, first.
        Text {
            visible: page.current === "flathub" && page.shown.length > 0
            text: "—  TESTED ON DESKDROID  —"
            font.family: Party.heading; font.weight: Font.Black; font.pixelSize: 14; font.letterSpacing: 3
            color: Party.green
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

        // Flathub: all of it.
        ColumnLayout {
            visible: page.current === "flathub"
            Layout.fillWidth: true
            Layout.topMargin: 8
            spacing: 14
            Text {
                text: page.installedOnly ? "—  INSTALLED FROM FLATHUB  —"
                    : page.filter.trim() !== "" ? "—  ALL OF FLATHUB: \"" + page.filter.trim().toUpperCase() + "\"  —"
                    : "—  ALL OF FLATHUB  —"
                font.family: Party.heading; font.weight: Font.Black; font.pixelSize: 14; font.letterSpacing: 3
                color: Party.cyan
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
            Flow {
                visible: !page.installedOnly
                Layout.fillWidth: true
                spacing: 8
                Repeater {
                    model: page.categories
                    PartyButton {
                        compact: true
                        text: modelData.label
                        accent: page.category === modelData.id ? Party.green : Party.border
                        textColor: page.category === modelData.id ? Party.green : Party.text
                        onClicked: page.category = modelData.id
                    }
                }
            }
            Text {
                visible: !backend.flatpakAvailable
                text: "The flatpak command isn't on this desktop: you can look around, but installing from Flathub needs a newer DeskDroid."
                font.family: Party.body; font.pixelSize: 14
                color: Party.orange
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }
            Text {
                visible: text !== ""
                text: page.installedOnly ? (page.flathubShown.length === 0 ? "Nothing from Flathub is installed yet." : "")
                    : (page.flathub.error || "") !== "" ? "Couldn't reach Flathub (" + page.flathub.error + "). Check the phone's internet connection, then Refresh."
                    : backend.offline ? "DeskDroid's app isn't answering, so Flathub can't be searched right now."
                    : page.flathub.loading && page.flathubResults.length === 0 ? "Asking Flathub…"
                    : !page.flathub.loading && page.flathubResults.length === 0 && page.filter.trim() !== "" ? "Nothing on Flathub matches \"" + page.filter.trim() + "\"."
                    : ""
                font.family: Party.body; font.pixelSize: 15
                color: (page.flathub.error || "") !== "" || backend.offline ? Party.orange : Party.muted
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }
            RainbowBar {
                visible: !page.installedOnly && page.flathub.loading === true
                indeterminate: true
                Layout.fillWidth: true
            }
            Repeater {
                model: page.current === "flathub" ? page.flathubShown : []
                FlathubRow {
                    Layout.fillWidth: true
                    hit: modelData
                }
            }
            PartyButton {
                visible: !page.installedOnly && !page.flathub.loading && page.flathubResults.length > 0
                    && page.flathubResults.length < (page.flathub.total || 0)
                Layout.alignment: Qt.AlignHCenter
                text: "Show more  (" + page.flathubResults.length + " of " + page.flathub.total + ")"
                accent: Party.cyan
                onClicked: page.searchFlathub(true)
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

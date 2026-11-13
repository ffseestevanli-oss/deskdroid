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

    // All of Flathub (backend.flathub, FlathubCatalog.kt). The tab opens on
    // a grid of categories; picking one, or searching, lists apps. "native"
    // and "fex" are Agora's own: apps with an ARM64 build, and apps Flathub
    // only builds for x86-64 (FEX runs those).
    readonly property var categories: [
        { id: "popular", label: "Popular", subtitle: "What people install most", icon: "starred-symbolic", accent: Party.pink },
        { id: "native", label: "Runs natively", subtitle: "ARM64 builds, at full speed", icon: "cpu", accent: Party.green },
        { id: "fex", label: "Through FEX", subtitle: "x86-64 only, translated as they run", icon: "application-x-executable", accent: Party.orange },
        { id: "AudioVideo", label: "Audio & Video", subtitle: "Players, editors, music", icon: "applications-multimedia", accent: Party.cyan },
        { id: "Development", label: "Developer Tools", subtitle: "Editors, IDEs, git", icon: "applications-development", accent: Party.purple },
        { id: "Education", label: "Education", subtitle: "Learn, teach, study", icon: "applications-education", accent: Party.yellow },
        { id: "Game", label: "Games", subtitle: "Play, and game launchers", icon: "applications-games", accent: Party.red },
        { id: "Graphics", label: "Graphics", subtitle: "Draw, paint, photos, 3D", icon: "applications-graphics", accent: Party.pink },
        { id: "Network", label: "Internet", subtitle: "Browsers, chat, mail", icon: "applications-internet", accent: Party.cyan },
        { id: "Office", label: "Office", subtitle: "Documents, notes, finance", icon: "applications-office", accent: Party.green },
        { id: "Science", label: "Science", subtitle: "Maths, astronomy, data", icon: "applications-science", accent: Party.purple },
        { id: "System", label: "System", subtitle: "Monitors and tools", icon: "applications-system", accent: Party.yellow },
        { id: "Utility", label: "Utilities", subtitle: "Small helpers", icon: "applications-utilities", accent: Party.orange },
    ]
    property string category: ""      // "" : the grid
    readonly property var categoryInfo: categories.find(c => c.id === category) || null
    // The list: compact rows (the desktop's default) or the big cards.
    property bool compactList: true
    readonly property bool flathubListing: category !== "" || filter.trim() !== "" || installedOnly
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
    // Native apps first, then FEX ones, then those with no build for here.
    function byBuild(kind) { return flathubShown.filter(h => backend.archFor(h.arches || []) === kind) }
    readonly property var flathubSections: [
        { kind: "", label: "RUNS NATIVELY  ·  ARM64", accent: Party.green, list: byBuild("") },
        { kind: "x86_64", label: "THROUGH FEX  ·  X86-64 ONLY", accent: Party.orange, list: byBuild("x86_64") },
        { kind: "none", label: "NO BUILD FOR THIS DEVICE", accent: Party.dim, list: byBuild("none") },
    ]
    function requestCategory() { return category === "popular" ? "" : category }
    function searchFlathub(more) {
        if (!flathubListing || installedOnly) return
        backend.searchFlathub(page.filter.trim(), requestCategory(), more ? (flathub.next || 2) : 1)
    }
    function flathubStale() {
        return flathubResults.length === 0 || (flathub.query || "") !== filter.trim() || (flathub.category || "") !== requestCategory()
    }
    // Asked again when the tab opens with a search Flathub hasn't answered.
    onCurrentChanged: if (current === "flathub" && flathubListing && flathubStale() && !flathub.loading) searchFlathub(false)
    onCategoryChanged: searchFlathub(false)
    onInstalledOnlyChanged: if (!installedOnly && current === "flathub" && flathubStale()) searchFlathub(false)
    Timer {
        id: searchDelay
        interval: 450
        onTriggered: if (page.current === "flathub" && page.flathubStale()) page.searchFlathub(false)
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
                            + (tabButton.list.length && modelData.id !== "flathub" ? "  " + tabButton.list.length : "")
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
            visible: page.current === "flathub" && page.shown.length > 0 && page.category === ""
            text: "—  TESTED ON DESKDROID  —"
            font.family: Party.heading; font.weight: Font.Black; font.pixelSize: 14; font.letterSpacing: 3
            color: Party.green
        }
        Repeater {
            model: page.current === "about" || (page.current === "flathub" && page.category !== "") ? [] : page.shown
            AppRow {
                Layout.fillWidth: true
                app: modelData
                names: page.names
                progress: backend.busy[modelData.id]
            }
        }

        // Flathub: the category grid, or a list.
        ColumnLayout {
            visible: page.current === "flathub"
            Layout.fillWidth: true
            spacing: 14

            Text {
                visible: !backend.flatpakAvailable
                text: "The flatpak command isn't on this desktop: you can look around, but installing from Flathub needs a newer DeskDroid."
                font.family: Party.body; font.pixelSize: 14
                color: Party.orange
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

            // The grid.
            Text {
                visible: !page.flathubListing
                text: "—  BROWSE FLATHUB  —"
                font.family: Party.heading; font.weight: Font.Black; font.pixelSize: 14; font.letterSpacing: 3
                color: Party.cyan
            }
            GridLayout {
                id: grid
                visible: !page.flathubListing
                Layout.fillWidth: true
                columns: Math.max(2, Math.floor((width + columnSpacing) / (210 + columnSpacing)))
                columnSpacing: 12
                rowSpacing: 12
                Repeater {
                    model: page.categories
                    Tile {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 210
                        implicitHeight: 118
                        text: modelData.label
                        subtitle: modelData.subtitle
                        iconName: modelData.icon
                        accent: modelData.accent
                        onClicked: page.category = modelData.id
                    }
                }
            }

            // The list: where it is, and how to show it.
            Flow {
                visible: page.flathubListing
                Layout.fillWidth: true
                spacing: 10
                PartyButton {
                    compact: true
                    text: "‹  Categories"
                    onClicked: { page.category = ""; search.text = ""; page.installedOnly = false }
                }
                Text {
                    height: 34
                    verticalAlignment: Text.AlignVCenter
                    text: page.installedOnly ? "INSTALLED FROM FLATHUB"
                        : (page.categoryInfo ? page.categoryInfo.label.toUpperCase() : "ALL OF FLATHUB")
                          + (page.filter.trim() !== "" ? "  ·  \"" + page.filter.trim().toUpperCase() + "\"" : "")
                    font.family: Party.heading; font.weight: Font.Black; font.pixelSize: 14; font.letterSpacing: 2
                    color: page.categoryInfo ? page.categoryInfo.accent : Party.cyan
                }
                Item { width: 12; height: 1 }
                PartyButton {
                    compact: true
                    text: page.compactList ? "▤  Compact" : "▦  Large"
                    accent: Party.border
                    onClicked: page.compactList = !page.compactList
                }
            }
            Text {
                visible: page.flathubListing && text !== ""
                text: page.installedOnly ? (page.flathubShown.length === 0 ? "Nothing from Flathub is installed yet." : "")
                    : (page.flathub.error || "") !== "" ? "Couldn't reach Flathub (" + page.flathub.error + "). Check the phone's internet connection, then Refresh."
                    : backend.offline ? "DeskDroid's app isn't answering, so Flathub can't be searched right now."
                    : page.flathub.loading && (page.flathubResults.length === 0 || page.flathubStale()) ? (page.category === "fex" ? "Picking out the x86-64-only apps…" : "Asking Flathub…")
                    : !page.flathub.loading && page.flathubResults.length === 0 ? "Nothing here matches" + (page.filter.trim() !== "" ? " \"" + page.filter.trim() + "\"." : ".")
                    : ""
                font.family: Party.body; font.pixelSize: 15
                color: (page.flathub.error || "") !== "" || backend.offline ? Party.orange : Party.muted
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }
            RainbowBar {
                visible: page.flathubListing && !page.installedOnly && page.flathub.loading === true
                indeterminate: true
                Layout.fillWidth: true
            }
            Repeater {
                model: page.current === "flathub" && page.flathubListing && !(page.flathub.loading && page.flathubStale()) ? page.flathubSections : []
                ColumnLayout {
                    visible: modelData.list.length > 0
                    Layout.fillWidth: true
                    spacing: page.compactList ? 6 : 12
                    Text {
                        // One heading is enough in a category that is one kind.
                        visible: page.category !== "native" && page.category !== "fex"
                        Layout.topMargin: 6
                        text: "—  " + modelData.label + "  ·  " + modelData.list.length + "  —"
                        font.family: Party.heading; font.weight: Font.Black; font.pixelSize: 13; font.letterSpacing: 2
                        color: modelData.accent
                    }
                    Repeater {
                        model: modelData.list
                        FlathubRow {
                            Layout.fillWidth: true
                            hit: modelData
                            compact: page.compactList
                        }
                    }
                }
            }
            PartyButton {
                visible: page.flathubListing && !page.installedOnly && !page.flathub.loading && (page.flathub.next || 0) > 0
                Layout.alignment: Qt.AlignHCenter
                text: "Show more" + ((page.flathub.total || 0) > 0 ? "  (" + page.flathubResults.length + " of " + page.flathub.total + ")" : "")
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

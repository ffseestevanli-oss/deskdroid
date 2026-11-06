import QtQuick
import QtQuick.Dialogs
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.plasma.private.kicker as Kicker

PlasmoidItem {
    id: root

    property string fullName: ""
    property string systemAvatar: ""

    // Don't auto-close the popup while the file chooser is open
    property bool dialogOpen: false
    property bool folderDialogOpen: false
    property bool dragInProgress: false
    hideOnWindowDeactivate: !(dialogOpen || folderDialogOpen || dragInProgress)
    preferredRepresentation: compactRepresentation
    Plasmoid.icon: "start-here-kde"
    toolTipMainText: i18n("Start 7 Plus")

    // ---- DeskDroid (Plasma on Android): no Python and no /bin/sh there, so
    // DeskDroid's Kicker ProcessRunner lists the app menu (KDE's categories, as
    // Kickoff shows them), starts apps, opens files and runs commands. On Linux
    // it has none of these and the widget uses its scripts as before.
    Kicker.ProcessRunner { id: runner }
    readonly property bool nativeRunner: typeof runner.appMenu === "function"

    // A command meant for sh, done without one: power and session buttons go
    // to Plasma's session management, a plain command runs as it is.
    function runNative(cmd) {
        var c = cmd.trim()
        if (/promptShutDown|promptReboot|promptLogout|systemctl (poweroff|reboot)/.test(c)) { runner.session("logout"); return }
        if (/lock-session/.test(c)) { runner.session("lock"); return }
        if (/systemctl suspend/.test(c)) { runner.session("suspend"); return }
        if (/systemctl hibernate/.test(c)) { runner.session("hibernate"); return }
        if (/for t in konsole/.test(c)) { runner.runCommand("konsole"); return }
        c = c.split("||")[0].trim()     // "plasma-systemmonitor || ksysguard": the first one
        if (/[;&|<>$`'"()]/.test(c) || /^(if|setsid)\b/.test(c)) {
            console.warn("Start 7 Plus: needs a shell, not run here:", cmd)
            return
        }
        runner.runCommand(c)
    }
    function run(cmd) {
        if (nativeRunner) runNative(cmd)
        else exec.connectSource(cmd)
    }

    // ---- Models (Kicker's private API, same one Kicker/Kickoff use) ----
    // All Programs: scanned from .desktop files by contents/code/apps.py
    // (system, user and Flatpak apps), grouped into folders.
    property var categories: []
    property var appIndex: ({})
    property var appByName: ({})

    function indexApps(cats) {
        var byId = {}, byName = {}
        for (var i = 0; i < cats.length; ++i) {
            for (var j = 0; j < cats[i].apps.length; ++j) {
                var a = cats[i].apps[j]
                byId[a.id] = a
                byName[a.name] = a
            }
        }
        appIndex = byId
        appByName = byName
    }
    readonly property string appsScript: Qt.resolvedUrl("../code/apps.py").toString().replace("file://", "")

    function loadApps() {
        if (nativeRunner) {
            var cats = runner.appMenu()
            indexApps(cats)
            categories = cats
            trySeedPins()
            return
        }
        appsSource.disconnectSource(appsSource.cmd)
        appsSource.connectSource(appsSource.cmd)
    }

    Plasma5Support.DataSource {
        id: appsSource
        readonly property string cmd: 'python3 "' + root.appsScript + '"'
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => {
            try {
                var parsed = JSON.parse(data["stdout"])
                root.indexApps(parsed)
                root.categories = parsed
                root.trySeedPins()
            } catch (e) {
                console.warn("Start 7 Plus: could not parse app list:", e, data["stderr"])
            }
            disconnectSource(sourceName)
        }
    }

    Component.onCompleted: {
        if (nativeRunner) {
            defaultBrowserId = runner.defaultBrowser()
            browserChecked = true
            var user = runner.userInfo()
            fullName = user[0] || ""
            systemAvatar = user[1] || ""
            distroName = "DeskDroid"
            distroPretty = "DeskDroid"
        }
        loadApps()
    }

    // ---- Default pins (first run only): the default browser plus a few essentials ----
    property string defaultBrowserId: ""
    property bool browserChecked: false

    Plasma5Support.DataSource {
        id: browserSource
        engine: "executable"
        connectedSources: root.nativeRunner ? [] : ["xdg-settings get default-web-browser"]
        onNewData: (sourceName, data) => {
            root.defaultBrowserId = (data["stdout"] || "").trim()
            root.browserChecked = true
            root.trySeedPins()
            disconnectSource(sourceName)
        }
    }

    function firstInstalled(list) {
        for (var i = 0; i < list.length; ++i) {
            if (appIndex[list[i]]) return list[i]
        }
        return ""
    }
    function trySeedPins() {
        if (Plasmoid.configuration.pinsSeeded || !browserChecked) return
        if (Object.keys(appIndex).length === 0) return
        var cur = Plasmoid.configuration.pinnedIds
        if (cur && cur.length > 0) { Plasmoid.configuration.pinsSeeded = true; return }
        var picks = [
            firstInstalled([defaultBrowserId, "org.deskdroid.firefox.desktop", "firefox.desktop", "org.mozilla.firefox.desktop", "one.ablaze.floorp.desktop",
                            "floorp.desktop", "chromium.desktop", "org.chromium.Chromium.desktop", "google-chrome.desktop",
                            "brave-browser.desktop", "com.brave.Browser.desktop", "vivaldi-stable.desktop", "librewolf.desktop"]),
            firstInstalled(["org.kde.dolphin.desktop", "org.gnome.Nautilus.desktop", "thunar.desktop", "nemo.desktop", "pcmanfm.desktop"]),
            firstInstalled(["org.kde.konsole.desktop", "org.gnome.Ptyxis.desktop", "org.gnome.Terminal.desktop", "xfce4-terminal.desktop", "xterm.desktop"]),
            firstInstalled(["systemsettings.desktop", "org.kde.systemsettings.desktop", "org.gnome.Settings.desktop"])
        ]
        var ids = []
        for (var i = 0; i < picks.length; ++i) {
            if (picks[i] !== "" && ids.indexOf(picks[i]) < 0) ids.push(picks[i])
        }
        if (ids.length > 0) Plasmoid.configuration.pinnedIds = ids
        Plasmoid.configuration.pinsSeeded = true
    }

    // Recent apps: RecentUsageModel's properties differ between Plasma versions, so instead
    // ask a second RootModel for its "Recent Applications" group and use that submodel.
    property var recentApps: null

    function pickRecent() {
        for (var i = 0; i < recentHolder.count; ++i) {
            var icon = recentHolder.data(recentHolder.index(i, 0), Qt.DecorationRole)
            if (String(icon) === "view-history") {
                recentApps = recentHolder.modelForRow(i)
                return
            }
        }
        if (recentHolder.count > 0) recentApps = recentHolder.modelForRow(0)
    }

    Kicker.RootModel {
        id: recentHolder
        autoPopulate: false
        appletInterface: root
        flat: false
        showSeparators: false
        showTopLevelItems: false
        showAllApps: false
        showAllAppsCategorized: false
        showRecentApps: true
        showRecentDocs: false
        showPowerSession: false
        onCountChanged: root.pickRecent()
        Component.onCompleted: { refresh(); root.pickRecent() }
    }

    // ---- File search in the home folder (contents/code/search.py) ----
    property var fileSearchResult: ({ query: "", files: [] })
    readonly property string searchScript: Qt.resolvedUrl("../code/search.py").toString().replace("file://", "")

    function searchFiles(query) {
        if (nativeRunner) { fileSearchResult = runner.searchFiles(query); return }
        var q = "'" + query.replace(/'/g, "'\\''") + "'"
        searchSource.connectSource('python3 "' + root.searchScript + '" ' + q)
    }

    Plasma5Support.DataSource {
        id: searchSource
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => {
            try {
                root.fileSearchResult = JSON.parse(data["stdout"])
            } catch (e) {
                console.warn("Start 7 Plus: file search failed:", e, data["stderr"])
            }
            disconnectSource(sourceName)
        }
    }

    // ---- Run shell commands ----
    Plasma5Support.DataSource {
        id: exec
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => disconnectSource(sourceName)
    }

    readonly property string userInfoScript: Qt.resolvedUrl("../code/userinfo.py").toString().replace("file://", "")
    Plasma5Support.DataSource {
        id: nameSource
        engine: "executable"
        connectedSources: root.nativeRunner ? [] : ['python3 "' + root.userInfoScript + '"']
        onNewData: (sourceName, data) => {
            var lines = (data["stdout"] || "").split("\n")
            root.fullName = (lines[0] || "").trim()
            root.systemAvatar = (lines[1] || "").trim()
            disconnectSource(sourceName)
        }
    }

    // ---- SteamOS / Bazzite: is there a "Return to Gaming Mode" switch? ----
    property bool gamingModeAvailable: false
    Plasma5Support.DataSource {
        id: gamingSource
        engine: "executable"
        connectedSources: root.nativeRunner ? [] : ["command -v steamos-session-select"]
        onNewData: (sourceName, data) => {
            root.gamingModeAvailable = (data["stdout"] || "").trim() !== ""
            disconnectSource(sourceName)
        }
    }

    // ---- Distro name (for the Win 9x banner) ----
    property string distroName: ""
    property string distroPretty: ""
    readonly property string distroScript: Qt.resolvedUrl("../code/distro.py").toString().replace("file://", "")
    Plasma5Support.DataSource {
        id: distroSource
        engine: "executable"
        connectedSources: root.nativeRunner ? [] : ['python3 "' + root.distroScript + '"']
        onNewData: (sourceName, data) => {
            var lines = (data["stdout"] || "").split("\n")
            root.distroName = (lines[0] || "").trim()
            root.distroPretty = (lines[1] || "").trim()
            disconnectSource(sourceName)
        }
    }

    compactRepresentation: Orb {
        active: root.expanded
        onToggled: root.expanded = !root.expanded
    }

    fullRepresentation: StartMenu {
        open: root.expanded
        onFileDialogActiveChanged: root.folderDialogOpen = fileDialogActive
        categories: root.categories
        fileSearchResult: root.fileSearchResult
        onSearchFilesRequested: query => root.searchFiles(query)
        appIndex: root.appIndex
        appByName: root.appByName
        onAboutToShow: root.loadApps()
        recentModel: root.recentApps
        fullName: root.fullName
        distroName: root.distroName
        gamingModeAvailable: root.gamingModeAvailable
        distroPretty: root.distroPretty
        systemAvatar: root.systemAvatar
        onDraggingChanged: root.dragInProgress = dragging
        onLaunched: root.expanded = false
        onRunCommand: cmd => root.run(cmd)
        runner: root.nativeRunner ? runner : null
        onChangeAvatar: {
            root.dialogOpen = true
            avatarDialog.open()
        }
    }

    FileDialog {
        id: avatarDialog
        title: i18n("Choose a profile picture")
        fileMode: FileDialog.OpenFile
        nameFilters: [i18n("Images (*.png *.jpg *.jpeg *.bmp *.webp *.gif *.svg)")]
        onAccepted: {
            Plasmoid.configuration.avatarPath = selectedFile.toString()
            Plasmoid.configuration.avatarMode = "custom"
            root.dialogOpen = false
        }
        onRejected: root.dialogOpen = false
    }
}

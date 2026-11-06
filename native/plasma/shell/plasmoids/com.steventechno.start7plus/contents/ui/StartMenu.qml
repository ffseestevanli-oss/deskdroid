import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import QtQuick.Dialogs
import QtCore
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

Item {
    id: menu

    // Provided by main.qml
    property bool open: false
    property var categories: []
    property var appIndex: ({})     // desktop-file id -> {id, name, icon, path}
    property var appByName: ({})    // app name -> same object (fallback lookup)
    property var recentModel
    // DeskDroid: Kicker's ProcessRunner when it can start apps and open files
    // itself (no sh or kioclient6 on Android); null on Linux.
    property var runner: null
    property var fileSearchResult: ({ query: "", files: [] })
    property bool fileSearching: false
    property string fullName: ""
    property string distroName: ""
    property bool gamingModeAvailable: false
    property string distroPretty: ""
    readonly property bool classic: Plasmoid.configuration.menuLayout === "classic"
    property alias searchBoxText: searchField.text

    property bool showAll: false
    property var expandedMap: ({})  // which All Programs folders are expanded
    property var ctxApp: null       // app the context menu was opened for
    property int ctxFolderIndex: -1
    property int ctxItemIndex: -1
    property int faceTry: 0
    property string navKey: ""        // keyboard-selected item
    property string navPane: "left"   // "left" | "right"
    property string lastLeftKey: ""
    property bool fileDialogActive: false
    readonly property int maxPinned: 8
    readonly property int maxRecents: Math.max(1, Plasmoid.configuration.recentCount)
    property string systemAvatar: ""
    property bool dragging: false

    signal launched()
    signal aboutToShow()
    signal runCommand(string cmd)
    signal changeAvatar()
    signal searchFilesRequested(string query)

    // Win 7 layout: fixed width, resizable height. Classic layout: sized by its content (grows for flyouts).
    readonly property real fixedWidth: Kirigami.Units.gridUnit * 27
    readonly property real wantWidth: (classic && classicLoader.item) ? classicLoader.item.requiredWidth : fixedWidth
    readonly property real classicHeight: (classic && classicLoader.item) ? classicLoader.item.requiredHeight : 0
    Layout.minimumWidth: wantWidth
    Layout.maximumWidth: wantWidth
    Layout.preferredWidth: wantWidth
    Layout.minimumHeight: classic ? classicHeight : Math.max(Kirigami.Units.gridUnit * 26, rightPane.implicitHeight + Kirigami.Units.smallSpacing * 2)
    // normal size every time it opens: the standard height unless the built-in places need more
    Layout.preferredHeight: classic ? classicHeight : Math.max(Kirigami.Units.gridUnit * 32, Layout.minimumHeight)
    // While closed (and for a moment after opening) the height is pinned to the normal size,
    // so Plasma can't restore an old dragged-out size. Afterwards it can be resized freely.
    property bool pinHeight: true
    Layout.maximumHeight: (classic || pinHeight) ? Layout.preferredHeight : Kirigami.Units.gridUnit * 70
    Timer {
        id: unpinTimer
        interval: 250
        onTriggered: menu.pinHeight = false
    }

    // Reset to the Recents view every time the menu is opened or closed
    function reset() {
        searchField.text = ""
        showAll = false
        expandedMap = ({})
        navKey = ""
        navPane = "left"
        lastLeftKey = ""
        if (classic && classicLoader.item) classicLoader.item.resetView()
        else if (open) Qt.callLater(function () { searchField.forceActiveFocus() })
    }
    onOpenChanged: {
        if (open) { pinHeight = true; unpinTimer.restart() }
        else { unpinTimer.stop(); pinHeight = true }
        if (!open) {
            powerMenu.close()
            appMenu.close()
            folderMenu.close()
            folderItemMenu.close()
            categoryMenu.close()
            computerMenu.close()
            placesMenu.close()
        }
        reset()
        if (open) aboutToShow()
    }

    // ------------------------------------------------------------------ search (programs + files in home)
    readonly property string queryText: searchField.text.trim()

    function fileUrl(path) {
        return "file://" + path.split("/").map(encodeURIComponent).join("/")
    }

    onFileSearchResultChanged: {
        if (fileSearchResult && fileSearchResult.query === queryText) fileSearching = false
    }

    Timer {
        id: searchTimer
        interval: 300
        onTriggered: {
            var q = menu.queryText
            if (q.length >= 2 && Plasmoid.configuration.searchFiles) {
                menu.fileSearching = true
                menu.searchFilesRequested(q)
            } else {
                menu.fileSearching = false
            }
        }
    }

    readonly property var searchResults: {
        var out = []
        var q = queryText.toLowerCase()
        if (q === "") return out
        var terms = q.split(/\s+/)

        var matches = []
        for (var id in appIndex) {
            var a = appIndex[id]
            var hay = (a.name + " " + (a.kw || "") + " " + id).toLowerCase()
            var ok = true
            for (var t = 0; t < terms.length; ++t) {
                if (hay.indexOf(terms[t]) < 0) { ok = false; break }
            }
            if (!ok) continue
            var n = a.name.toLowerCase()
            var rank = n.indexOf(q) === 0 ? 0 : (n.indexOf(" " + q) >= 0 ? 1 : (n.indexOf(q) >= 0 ? 2 : 3))
            matches.push({ app: a, rank: rank })
        }
        matches.sort(function (x, y) {
            return x.rank !== y.rank ? x.rank - y.rank : x.app.name.localeCompare(y.app.name)
        })
        var k = 0
        if (matches.length > 0) {
            out.push({ type: "header", text: i18n("Programs") })
            for (var i = 0; i < matches.length && i < 12; ++i) out.push({ type: "app", app: matches[i].app, nav: k++ })
        }

        var files = (fileSearchResult && fileSearchResult.query === queryText) ? fileSearchResult.files : []
        if (files.length > 0) {
            out.push({ type: "header", text: i18n("Files") })
            for (var f = 0; f < files.length; ++f) out.push({ type: "file", file: files[f], nav: k++ })
        }
        return out
    }

    function activateResult(r) {
        if (r.type === "app") {
            launchApp(r.app)
        } else if (r.type === "file") {
            menu.openUrl(fileUrl(r.file.path))
            launched()
        }
    }

    // ------------------------------------------------------------------ keyboard navigation
    onQueryTextChanged: {
        navPane = "left"
        navKey = queryText !== "" ? "s:0" : ""    // first search result is highlighted
    }

    function visibleRecentCount() {
        if (!Plasmoid.configuration.showRecents) return 0
        return Math.min(recentList.count, maxRecents)
    }

    // Everything the arrow keys can step through in the current view
    function navItems() {
        var out = []
        if (navPane === "right") {
            out.push({ key: "u", kind: "user" })
            for (var i = 0; i < visiblePlaces.length; ++i) {
                if (!visiblePlaces[i].sep) out.push({ key: "pl:" + i, kind: "place", place: visiblePlaces[i] })
            }
            out.push({ key: "shutdown", kind: "shutdown" })
            return out
        }
        if (queryText !== "") {
            for (var r = 0; r < searchResults.length; ++r) {
                if (searchResults[r].type !== "header") out.push({ key: "s:" + searchResults[r].nav, kind: "result", result: searchResults[r] })
            }
            return out
        }
        if (showAll) {
            for (var e = 0; e < allEntries.length; ++e) {
                var en = allEntries[e]
                if (en.type === "sep") continue
                var expandable = en.type === "cat" || en.type === "folder"
                out.push({ key: en.key, kind: "head", entry: en, expandable: expandable })
                if (expandable && expandedMap[en.key]) {
                    for (var j = 0; j < en.apps.length; ++j) {
                        out.push({ key: en.key + "/" + j, kind: "child", entry: en, item: en.apps[j], parentKey: en.key })
                    }
                }
            }
            out.push({ key: "back", kind: "back" })
            return out
        }
        for (var p = 0; p < pinnedApps.length; ++p) out.push({ key: "p:" + p, kind: "pinned", app: pinnedApps[p] })
        var rc = visibleRecentCount()
        for (var q = 0; q < rc; ++q) out.push({ key: "r:" + q, kind: "recent", index: q })
        out.push({ key: "allbtn", kind: "allbtn" })
        return out
    }

    function currentNavItem() {
        var items = navItems()
        for (var i = 0; i < items.length; ++i) {
            if (items[i].key === navKey) return items[i]
        }
        return null
    }

    function navMove(delta) {
        var items = navItems()
        if (items.length === 0) return
        var idx = -1
        for (var i = 0; i < items.length; ++i) {
            if (items[i].key === navKey) { idx = i; break }
        }
        if (idx < 0) idx = delta > 0 ? 0 : items.length - 1
        else idx = Math.max(0, Math.min(items.length - 1, idx + delta))
        navKey = items[idx].key
        Qt.callLater(ensureNavVisible)
    }

    function navRight() {
        if (navPane === "right") return
        var it = currentNavItem()
        if (it && it.kind === "head" && it.expandable && showAll && queryText === "") {
            if (!expandedMap[it.key]) { toggleOpen(it.key); return }
            if (it.entry.apps.length > 0) { navKey = it.key + "/0"; Qt.callLater(ensureNavVisible); return }
        }
        lastLeftKey = navKey
        navPane = "right"
        navKey = "u"
    }

    function navLeft() {
        if (navPane === "right") {
            navPane = "left"
            navKey = lastLeftKey
            return
        }
        var it = currentNavItem()
        if (!it || !showAll) return
        if (it.kind === "child") {
            navKey = it.parentKey
            toggleOpen(it.parentKey)
        } else if (it.kind === "head" && it.expandable && expandedMap[it.key]) {
            toggleOpen(it.key)
        }
    }

    function activatePlace(p) {
        if (p.appPath) { launchApp({ path: p.appPath }); return }
        if (p.cmd) runCommand(p.cmd)
        else if (p.url) menu.openUrl(p.url)
        launched()
    }
    function openUsers() {
        runCommand("systemsettings kcm_users")
        launched()
    }

    function navActivate() {
        var it = currentNavItem()
        if (!it && queryText !== "") {
            var items = navItems()
            if (items.length > 0) it = items[0]
        }
        if (!it) return
        switch (it.kind) {
        case "result":   activateResult(it.result); break
        case "pinned":   launchApp(it.app); break
        case "recent":   recentModel.trigger(it.index, "", null); launched(); break
        case "allbtn":   showAll = true; navKey = allEntries.length > 0 ? allEntries[0].key : "back"; break
        case "back":     showAll = false; navKey = "allbtn"; break
        case "head":
            if (it.entry.type === "new") openNameDialog("new", -1)
            else toggleOpen(it.key)
            break
        case "child":    launchEntry(it.item); break
        case "user":     openUsers(); break
        case "place":    activatePlace(it.place); break
        case "shutdown": shutDown(); break
        }
    }

    // Keep the keyboard-selected row inside the visible part of a list
    function reveal(flick, item) {
        if (!flick || !item) return
        var p = item.mapToItem(flick.contentItem, 0, 0)
        if (p.y < flick.contentY) flick.contentY = p.y
        else if (p.y + item.height > flick.contentY + flick.height) flick.contentY = p.y + item.height - flick.height
    }

    function ensureNavVisible() {
        if (navPane === "right") {
            if (navKey.indexOf("pl:") === 0) placesList.positionViewAtIndex(parseInt(navKey.substring(3)), ListView.Contain)
            else if (navKey === "u") placesList.positionViewAtBeginning()
            else if (navKey === "shutdown") placesList.positionViewAtEnd()
            return
        }
        if (navPane !== "left") return
        if (queryText === "" && !showAll && navKey.indexOf("r:") === 0) {
            recentList.positionViewAtIndex(parseInt(navKey.substring(2)), ListView.Contain)
            return
        }
        if (queryText !== "") {
            for (var i = 0; i < searchResults.length; ++i) {
                if (searchResults[i].type !== "header" && "s:" + searchResults[i].nav === navKey) {
                    resultsList.positionViewAtIndex(i, ListView.Contain)
                    return
                }
            }
        } else if (showAll) {
            var pk = navKey.split("/")[0]
            for (var e = 0; e < allEntries.length; ++e) {
                if (allEntries[e].key === pk) {
                    allList.positionViewAtIndex(e, ListView.Contain)
                    return
                }
            }
        }
    }

    // ------------------------------------------------------------------ pinning
    readonly property var pinnedApps: {
        var ids = Plasmoid.configuration.pinnedIds
        var out = []
        if (!ids) return out
        for (var i = 0; i < ids.length && out.length < maxPinned; ++i) {
            var a = appIndex[ids[i]]
            if (a) out.push(a)
        }
        return out
    }

    function isPinned(app) {
        if (!app) return false
        var ids = Plasmoid.configuration.pinnedIds
        if (!ids) return false
        for (var i = 0; i < ids.length; ++i) {
            if (ids[i] === app.id) return true
        }
        return false
    }

    function togglePin(app) {
        if (!app) return
        var cur = Plasmoid.configuration.pinnedIds
        var ids = []
        for (var i = 0; i < cur.length; ++i) {
            if (cur[i] !== app.id) ids.push(cur[i])
        }
        if (ids.length === cur.length) {          // wasn't pinned -> pin it
            if (ids.length >= maxPinned) return
            ids.push(app.id)
        }
        Plasmoid.configuration.pinnedIds = ids
    }

    // Find our own app record for an item coming from Kicker's models
    function lookupApp(favId, name) {
        var id = String(favId === undefined || favId === null ? "" : favId)
        id = id.replace(/^[A-Za-z]+:\/*/, "")
        var slash = id.lastIndexOf("/")
        if (slash >= 0) id = id.substring(slash + 1)
        if (appIndex[id]) return appIndex[id]
        if (appIndex[id + ".desktop"]) return appIndex[id + ".desktop"]
        if (name && appByName[name]) return appByName[name]
        return null
    }

    // Power: hard (instant) by default, soft (KDE confirmation prompt) when enabled in settings
    readonly property string promptCmd: "dbus-send --session --type=method_call --dest=org.kde.LogoutPrompt /LogoutPrompt org.kde.LogoutPrompt."
    function shutDown() {
        runCommand(Plasmoid.configuration.softShutdown ? promptCmd + "promptShutDown" : "systemctl poweroff")
        launched()
    }
    function returnToGamingMode() {
        runCommand("setsid -f steamos-session-select gamescope >/dev/null 2>&1 </dev/null")
        launched()
    }
    function restart() {
        runCommand(Plasmoid.configuration.softShutdown ? promptCmd + "promptReboot" : "systemctl reboot")
        launched()
    }

    function openUrl(url) {
        if (runner) runner.openUrl(String(url))
        else Qt.openUrlExternally(url)
    }

    function launchApp(app) {
        if (runner) {
            runner.runApp(app.path || app.id)
            launched()
            return
        }
        // kioclient6 goes through the same launcher job Kickoff uses (clean environment, proper
        // startup handling); gio is only the fallback. Fixes apps like Upscayl misbehaving.
        // Fully detach the app (own session, output to /dev/null). Otherwise apps that log to the
        // console (Electron apps like Upscayl) crash with EPIPE once our command's pipe closes.
        runCommand('setsid -f sh -c \'if command -v kioclient6 >/dev/null 2>&1; then kioclient6 exec "$0"; else gio launch "$0"; fi\' "' + app.path + '" >/dev/null 2>&1 </dev/null')
        launched()
    }

    function dragUrlFor(app) {
        return (app && app.path) ? fileUrl(app.path) : ""
    }

    // Launch an entry of a custom folder (program or any file)
    function launchEntry(item) {
        if (item.kind === "file") {
            menu.openUrl(item.path)
            launched()
        } else {
            launchApp(item)
        }
    }

    function toggleOpen(key) {
        var m = {}
        for (var k in expandedMap) m[k] = expandedMap[k]
        m[key] = !m[key]
        expandedMap = m
    }

    // ------------------------------------------------------------------ custom folders (All Programs)
    function parseFolders(json) {
        try {
            var a = JSON.parse(json || "[]")
            return Array.isArray(a) ? a : []
        } catch (e) {
            return []
        }
    }
    readonly property var folders: parseFolders(Plasmoid.configuration.customFolders)

    function cloneFolders() { return JSON.parse(JSON.stringify(folders)) }
    function saveFolders(arr) { Plasmoid.configuration.customFolders = JSON.stringify(arr) }

    function createFolder(name) {
        var a = cloneFolders()
        a.push({ name: name, items: [] })
        saveFolders(a)
    }
    function renameFolder(i, name) {
        var a = cloneFolders()
        if (i < 0 || i >= a.length) return
        a[i].name = name
        saveFolders(a)
    }
    function deleteFolder(i) {
        var a = cloneFolders()
        if (i < 0 || i >= a.length) return
        a.splice(i, 1)
        saveFolders(a)
        expandedMap = ({})
    }
    function sameItem(x, y) {
        return x.kind === y.kind && (x.kind === "app" ? x.id === y.id : x.path === y.path)
    }
    function addItemsToFolder(i, items) {
        var a = cloneFolders()
        if (i < 0 || i >= a.length) return
        for (var n = 0; n < items.length; ++n) {
            var dup = false
            for (var j = 0; j < a[i].items.length; ++j) {
                if (sameItem(a[i].items[j], items[n])) { dup = true; break }
            }
            if (!dup) a[i].items.push(items[n])
        }
        saveFolders(a)
    }
    function removeItemFromFolder(i, j) {
        var a = cloneFolders()
        if (i < 0 || i >= a.length || j < 0 || j >= a[i].items.length) return
        a[i].items.splice(j, 1)
        saveFolders(a)
    }
    function appToItem(app) {
        return { kind: "app", id: app.id, name: app.name, icon: app.icon, path: app.path }
    }
    function fileUrlToItem(url) {
        var u = String(url)
        var base = decodeURIComponent(u.substring(u.lastIndexOf("/") + 1)).replace(/^applications:/, "")
        if (u.toLowerCase().endsWith(".desktop")) {
            var a = appIndex[base]
            return {
                kind: "app", id: base,
                name: a ? a.name : base.replace(/\.desktop$/i, ""),
                icon: a ? a.icon : "application-x-executable",
                path: a ? a.path : decodeURIComponent(u.replace("file://", ""))
            }
        }
        return { kind: "file", name: base, path: u, icon: "" }
    }

    function dropOnFolder(index, urls) {
        var items = []
        for (var i = 0; i < urls.length; ++i) items.push(fileUrlToItem(urls[i]))
        if (items.length > 0) addItemsToFolder(index, items)
    }

    function resolveItems(items, folderIndex) {
        var out = []
        for (var j = 0; j < items.length; ++j) {
            var it = items[j]
            var o = { kind: it.kind, name: it.name, icon: it.icon || "text-x-generic",
                      path: it.path, id: it.id, itemIndex: j, folderIndex: folderIndex }
            if (it.kind === "app" && it.id && appIndex[it.id]) {
                var a = appIndex[it.id]
                o.name = a.name
                o.icon = a.icon
                o.path = a.path
            }
            if (it.kind === "file" && /\.(png|jpe?g|gif|bmp|webp|svg)$/i.test(it.path)) o.icon = it.path
            out.push(o)
        }
        return out
    }

    // Everything shown in All Programs: categories, a separator, then the user's folders
    readonly property var allEntries: {
        var out = []
        var cats = Plasmoid.configuration.showCategories ? categories : []
        for (var i = 0; i < cats.length; ++i) {
            out.push({ type: "cat", key: "cat:" + cats[i].name, name: cats[i].name, icon: cats[i].icon, apps: cats[i].apps })
        }
        var fl = folders
        if (cats.length > 0 && fl.length > 0) out.push({ type: "sep", key: "sep" })
        for (var f = 0; f < fl.length; ++f) {
            out.push({ type: "folder", key: "folder:" + f, folderIndex: f, name: fl[f].name, icon: "folder",
                       apps: resolveItems(fl[f].items || [], f) })
        }
        out.push({ type: "new", key: "new", name: i18n("New Folder…"), icon: "folder-new" })
        return out
    }

    function openNameDialog(mode, index) {
        nameDialog.mode = mode
        nameDialog.folderIndex = index
        nameField.text = (mode === "rename" && index >= 0 && index < folders.length) ? folders[index].name : ""
        nameDialog.open()
    }
    function commitName(mode, index, text) {
        var name = text.trim()
        if (mode === "new") {
            createFolder(name !== "" ? name : i18n("New folder"))
        } else if (name !== "") {
            renameFolder(index, name)
        }
    }
    function addFilesTo(index) {
        folderFileDialog.targetFolder = index
        fileDialogActive = true
        folderFileDialog.open()
    }

    // ------------------------------------------------------------------ context menus
    function openContext(app, sourceItem, x, y) {
        ctxApp = app
        appMenu.popup(sourceItem, x, y)
    }
    function openFolderContext(entry, sourceItem, x, y) {
        if (entry.type === "folder") {
            ctxFolderIndex = entry.folderIndex
            folderMenu.popup(sourceItem, x, y)
        } else {
            categoryMenu.popup(sourceItem, x, y)
        }
    }
    function openItemContext(entry, item, sourceItem, x, y) {
        if (entry.type === "folder") {
            ctxFolderIndex = entry.folderIndex
            ctxItemIndex = item.itemIndex
            ctxApp = (item.kind === "app" && item.id && appIndex[item.id]) ? appIndex[item.id] : null
            folderItemMenu.popup(sourceItem, x, y)
        } else {
            openContext(item, sourceItem, x, y)
        }
    }

    // right-click on a program: pin / add to folder
    Win7Menu {
        id: appMenu
        host: menu
        MenuEntry {
            readonly property bool pinned: menu.isPinned(menu.ctxApp)
            readonly property bool full: !pinned && menu.pinnedApps.length >= menu.maxPinned
            text: pinned ? i18n("Unpin from Start")
                         : (full ? i18n("Pin to Start (limit of %1 reached)", menu.maxPinned) : i18n("Pin to Start"))
            icon.name: pinned ? "window-unpin" : "window-pin"
            enabled: menu.ctxApp !== null && !full
            onTriggered: menu.togglePin(menu.ctxApp)
        }
        MenuEntry {
            text: menu.folders.length > 0 ? i18n("Add to folder…") : i18n("Add to folder… (create a folder first)")
            icon.name: "folder-new"
            enabled: menu.ctxApp !== null && menu.folders.length > 0
            onTriggered: folderPickDialog.open()
        }
    }

    // right-click on an entry inside a custom folder
    Win7Menu {
        id: folderItemMenu
        host: menu
        MenuEntry {
            text: i18n("Remove from folder")
            icon.name: "list-remove"
            onTriggered: menu.removeItemFromFolder(menu.ctxFolderIndex, menu.ctxItemIndex)
        }
        MenuEntry {
            readonly property bool pinned: menu.isPinned(menu.ctxApp)
            readonly property bool full: !pinned && menu.pinnedApps.length >= menu.maxPinned
            text: pinned ? i18n("Unpin from Start") : i18n("Pin to Start")
            icon.name: pinned ? "window-unpin" : "window-pin"
            enabled: menu.ctxApp !== null && !full
            onTriggered: menu.togglePin(menu.ctxApp)
        }
    }

    // right-click on one of your own folders
    Win7Menu {
        id: folderMenu
        host: menu
        MenuEntry {
            text: i18n("Add file or program…")
            icon.name: "document-open"
            onTriggered: menu.addFilesTo(menu.ctxFolderIndex)
        }
        MenuEntry {
            text: i18n("Rename…")
            icon.name: "edit-rename"
            onTriggered: menu.openNameDialog("rename", menu.ctxFolderIndex)
        }
        MenuEntry {
            text: i18n("New folder…")
            icon.name: "folder-new"
            onTriggered: menu.openNameDialog("new", -1)
        }
        MenuEntry {
            text: i18n("Delete folder")
            icon.name: "edit-delete"
            onTriggered: menu.deleteFolder(menu.ctxFolderIndex)
        }
    }

    // right-click on "Computer": handy system tools
    Win7Menu {
        id: computerMenu
        host: menu
        MenuEntry {
            text: i18n("Open")
            icon.name: "document-open-folder"
            onTriggered: {
                menu.openUrl(menu.pathOr(Plasmoid.configuration.pathComputer, menu.homeUrl))
                menu.launched()
            }
        }
        MenuEntry {
            text: i18n("System Settings")
            icon.name: "preferences-system"
            onTriggered: { menu.runCommand("systemsettings"); menu.launched() }
        }
        MenuEntry {
            text: i18n("System Monitor")
            icon.name: "utilities-system-monitor"
            onTriggered: { menu.runCommand("plasma-systemmonitor || ksysguard"); menu.launched() }
        }
        MenuEntry { separator: true }
        MenuEntry {
            text: i18n("Disks")
            icon.name: "drive-harddisk"
            onTriggered: {
                // GNOME Disks (native or Flatpak) if present, otherwise KDE Partition Manager
                menu.runCommand("if command -v gnome-disks >/dev/null 2>&1; then gnome-disks; elif flatpak info org.gnome.DiskUtility >/dev/null 2>&1; then flatpak run org.gnome.DiskUtility; else partitionmanager; fi")
                menu.launched()
            }
        }
        MenuEntry { separator: true }
        MenuEntry {
            text: i18n("Power management")
            icon.name: "preferences-system-power-management"
            onTriggered: { menu.runCommand("systemsettings kcm_powerdevilprofilesconfig"); menu.launched() }
        }
        MenuEntry {
            text: i18n("Default applications")
            icon.name: "preferences-desktop-default-applications"
            onTriggered: { menu.runCommand("systemsettings kcm_componentchooser"); menu.launched() }
        }
        MenuEntry {
            text: i18n("About this system")
            icon.name: "help-about"
            onTriggered: { menu.runCommand("systemsettings kcm_about-distro"); menu.launched() }
        }
    }

    // right-click on a built-in category
    Win7Menu {
        id: categoryMenu
        host: menu
        MenuEntry {
            text: i18n("New folder…")
            icon.name: "folder-new"
            onTriggered: menu.openNameDialog("new", -1)
        }
    }

    // ------------------------------------------------------------------ dialogs
    QQC2.Dialog {
        id: nameDialog
        property string mode: "new"
        property int folderIndex: -1
        modal: true
        width: Math.min(menu.width - Kirigami.Units.gridUnit * 2, Kirigami.Units.gridUnit * 18)
        x: Math.round((menu.width - width) / 2)
        y: Math.round(menu.height / 4)
        title: mode === "new" ? i18n("New folder") : i18n("Rename folder")
        standardButtons: QQC2.Dialog.Ok | QQC2.Dialog.Cancel
        onOpened: { nameField.forceActiveFocus(); nameField.selectAll() }
        onAccepted: menu.commitName(mode, folderIndex, nameField.text)

        contentItem: PlasmaComponents.TextField {
            id: nameField
            placeholderText: i18n("Folder name")
            onAccepted: nameDialog.accept()
        }
    }

    QQC2.Dialog {
        id: folderPickDialog
        modal: true
        width: Math.min(menu.width - Kirigami.Units.gridUnit * 2, Kirigami.Units.gridUnit * 16)
        x: Math.round((menu.width - width) / 2)
        y: Math.round(menu.height / 4)
        title: i18n("Add to folder")
        standardButtons: QQC2.Dialog.Cancel

        contentItem: ListView {
            implicitHeight: Math.min(contentHeight, Kirigami.Units.gridUnit * 12)
            clip: true
            model: menu.folders
            delegate: QQC2.ItemDelegate {
                width: ListView.view.width
                text: modelData.name
                icon.name: "folder"
                onClicked: {
                    if (menu.ctxApp) menu.addItemsToFolder(index, [menu.appToItem(menu.ctxApp)])
                    folderPickDialog.close()
                }
            }
        }
    }

    FileDialog {
        id: folderFileDialog
        property int targetFolder: -1
        title: i18n("Add files or programs to the folder")
        fileMode: FileDialog.OpenFiles
        onAccepted: {
            var items = []
            for (var i = 0; i < selectedFiles.length; ++i) items.push(menu.fileUrlToItem(selectedFiles[i]))
            menu.addItemsToFolder(targetFolder, items)
            menu.fileDialogActive = false
        }
        onRejected: menu.fileDialogActive = false
    }

    // ------------------------------------------------------------------ right pane entries
    function iconOr(custom, fallback) {
        return (custom && custom !== "") ? custom : fallback
    }
    function pathOr(custom, fallback) {
        return (custom && custom !== "") ? custom : fallback
    }

    readonly property var places: [
        { group: 0, enabled: Plasmoid.configuration.showDocuments, name: i18n("Documents"),  icon: iconOr(Plasmoid.configuration.iconDocuments, "folder-documents"), url: pathOr(Plasmoid.configuration.pathDocuments, StandardPaths.writableLocation(StandardPaths.DocumentsLocation)) },
        { group: 0, enabled: Plasmoid.configuration.showPictures,  name: i18n("Pictures"),   icon: iconOr(Plasmoid.configuration.iconPictures, "folder-pictures"),   url: pathOr(Plasmoid.configuration.pathPictures, StandardPaths.writableLocation(StandardPaths.PicturesLocation)) },
        { group: 0, enabled: Plasmoid.configuration.showMusic,     name: i18n("Music"),      icon: iconOr(Plasmoid.configuration.iconMusic, "folder-music"),         url: pathOr(Plasmoid.configuration.pathMusic, StandardPaths.writableLocation(StandardPaths.MusicLocation)) },
        { group: 0, enabled: Plasmoid.configuration.showVideos,    name: i18n("Videos"),     icon: iconOr(Plasmoid.configuration.iconVideos, "folder-videos"),       url: pathOr(Plasmoid.configuration.pathVideos, StandardPaths.writableLocation(StandardPaths.MoviesLocation)) },
        { group: 0, enabled: Plasmoid.configuration.showDownloads, name: i18n("Downloads"),  icon: iconOr(Plasmoid.configuration.iconDownloads, "folder-download"),  url: pathOr(Plasmoid.configuration.pathDownloads, StandardPaths.writableLocation(StandardPaths.DownloadLocation)) },
        { group: 1, enabled: Plasmoid.configuration.showNetwork,   name: i18n("Network"),    icon: iconOr(Plasmoid.configuration.iconNetwork, "network-workgroup"),  url: pathOr(Plasmoid.configuration.pathNetwork, "remote:///") },
        { group: 1, enabled: Plasmoid.configuration.showComputer,  kind: "computer", name: i18n("Computer"),   icon: iconOr(Plasmoid.configuration.iconComputer, "computer"),          url: pathOr(Plasmoid.configuration.pathComputer, StandardPaths.writableLocation(StandardPaths.HomeLocation)) },
        { group: 1, enabled: Plasmoid.configuration.showTrash,     name: i18n("Trash"),      icon: iconOr(Plasmoid.configuration.iconTrash, "user-trash"),           url: pathOr(Plasmoid.configuration.pathTrash, "trash:///") },
        { group: 2, enabled: Plasmoid.configuration.showSettings,  name: i18n("System Settings"),      icon: iconOr(Plasmoid.configuration.iconSettings, "preferences-system"), cmd: "systemsettings" },
        { group: 2, enabled: Plasmoid.configuration.showDevices,   name: i18n("Printers"), icon: iconOr(Plasmoid.configuration.iconDevices, "printer"), cmd: "systemsettings kcm_printer_manager" },
        { group: 2, enabled: Plasmoid.configuration.showDefaults,  name: i18n("Default Programs"),     icon: iconOr(Plasmoid.configuration.iconDefaults, "preferences-desktop-default-applications"), cmd: "systemsettings kcm_componentchooser" },
        { group: 2, enabled: Plasmoid.configuration.showHelp,      name: i18n("Help and Support"),     icon: iconOr(Plasmoid.configuration.iconHelp, "help-browser"), cmd: "khelpcenter" }
    ]

    // ------------------------------------------------------------------ your own places
    readonly property bool customPlacesOn: Plasmoid.configuration.useCustomPlaces

    function toUrl(target) {
        var t = String(target || "").trim()
        if (t === "") return ""
        if (t.indexOf("~/") === 0 || t === "~") return homeUrl + t.substring(1)
        if (t.charAt(0) === "/") return "file://" + t.split("/").map(encodeURIComponent).join("/")
        if (/^[A-Za-z][A-Za-z0-9+.-]*:/.test(t)) return t     // file://, https://, trash:/, remote:/ ...
        return "https://" + t
    }

    readonly property var customPlaceList: {
        var arr = []
        try { arr = JSON.parse(Plasmoid.configuration.customPlaces || "[]") } catch (e) { arr = [] }
        if (!Array.isArray(arr)) return []
        var defaults = { folder: "folder", file: "text-x-generic", link: "internet-web-browser", command: "system-run", app: "system-run" }
        var out = []
        for (var i = 0; i < arr.length; ++i) {
            var e = arr[i]
            if (e.sep) { out.push({ sep: true }); continue }
            var o = { name: e.name || e.target || "", icon: iconOr(e.icon, defaults[e.kind] || "folder") }
            if (e.kind === "command") o.cmd = e.target
            else if (e.kind === "app") o.appPath = decodeURIComponent(String(e.target || "").replace(/^file:\/\//, ""))
            else o.url = toUrl(e.target)
            out.push(o)
        }
        return out
    }

    // Only enabled places, with a separator between non-empty groups
    readonly property var visiblePlaces: customPlacesOn ? customPlaceList : builtinVisiblePlaces
    readonly property var builtinVisiblePlaces: {
        var groups = [[], [], []]
        for (var i = 0; i < places.length; ++i) {
            if (places[i].enabled) groups[places[i].group].push(places[i])
        }
        var out = []
        for (var g = 0; g < groups.length; ++g) {
            if (groups[g].length > 0) {
                if (out.length > 0) out.push({ sep: true })
                out = out.concat(groups[g])
            }
        }
        return out
    }

    // ------------------------------------------------------------------ edit your places from the menu
    property int ctxPlaceIndex: -1

    function placesArray() {
        var a = []
        try { a = JSON.parse(Plasmoid.configuration.customPlaces || "[]") } catch (e) { a = [] }
        return Array.isArray(a) ? a : []
    }
    function savePlaces(a) { Plasmoid.configuration.customPlaces = JSON.stringify(a) }
    function lastSegment(url) {
        var u = String(url).replace(/\/+$/, "")
        return decodeURIComponent(u.substring(u.lastIndexOf("/") + 1))
    }
    readonly property int placesLimit: 16
    readonly property bool placesAtLimit: !Plasmoid.configuration.placesLimitUnlocked && placesArray().length >= placesLimit
    function addCustomPlace(entry) {
        var a = placesArray()
        if (!Plasmoid.configuration.placesLimitUnlocked && a.length >= placesLimit) return
        a.push(entry)
        savePlaces(a)
    }
    function removeCustomPlace(i) {
        var a = placesArray()
        if (i >= 0 && i < a.length) { a.splice(i, 1); savePlaces(a) }
    }
    function moveCustomPlace(i, d) {
        var a = placesArray(), j = i + d
        if (i < 0 || j < 0 || i >= a.length || j >= a.length) return
        var t = a[i]; a[i] = a[j]; a[j] = t
        savePlaces(a)
    }
    function openPlacesMenu(index, sourceItem, x, y) {
        ctxPlaceIndex = index
        placesMenu.popup(sourceItem, x, y)
    }

    readonly property var appPickList: {
        var arr = []
        for (var id in appIndex) arr.push(appIndex[id])
        arr.sort(function (a, b) { return a.name.localeCompare(b.name) })
        return arr
    }

    Win7Menu {
        id: placesMenu
        host: menu
        MenuEntry {
            text: i18n("Link a folder…")
            enabled: !menu.placesAtLimit
            icon.name: "folder-new"
            onTriggered: { menu.fileDialogActive = true; placeFolderDialog.open() }
        }
        MenuEntry {
            text: i18n("Link an app…")
            enabled: !menu.placesAtLimit
            icon.name: "application-x-executable"
            onTriggered: { appPickFilter.text = ""; appPickDialog.open() }
        }
        MenuEntry {
            text: i18n("Add separator")
            enabled: !menu.placesAtLimit
            icon.name: "view-split-top-bottom"
            onTriggered: menu.addCustomPlace({ sep: true })
        }
        MenuEntry { separator: true; visible: menu.ctxPlaceIndex >= 0; height: visible ? implicitHeight : 0 }
        MenuEntry {
            visible: menu.ctxPlaceIndex >= 0
            height: visible ? implicitHeight : 0
            text: i18n("Move up")
            icon.name: "go-up"
            enabled: menu.ctxPlaceIndex > 0
            onTriggered: menu.moveCustomPlace(menu.ctxPlaceIndex, -1)
        }
        MenuEntry {
            visible: menu.ctxPlaceIndex >= 0
            height: visible ? implicitHeight : 0
            text: i18n("Move down")
            icon.name: "go-down"
            enabled: menu.ctxPlaceIndex >= 0 && menu.ctxPlaceIndex < menu.visiblePlaces.length - 1
            onTriggered: menu.moveCustomPlace(menu.ctxPlaceIndex, 1)
        }
        MenuEntry {
            visible: menu.ctxPlaceIndex >= 0
            height: visible ? implicitHeight : 0
            text: i18n("Remove from places")
            icon.name: "list-remove"
            onTriggered: menu.removeCustomPlace(menu.ctxPlaceIndex)
        }
    }

    FolderDialog {
        id: placeFolderDialog
        title: i18n("Choose a folder to link")
        onAccepted: {
            var u = selectedFolder.toString()
            menu.addCustomPlace({ kind: "folder", name: menu.lastSegment(u), target: u, icon: "" })
            menu.fileDialogActive = false
        }
        onRejected: menu.fileDialogActive = false
    }

    QQC2.Dialog {
        id: appPickDialog
        modal: true
        width: menu.width - Kirigami.Units.gridUnit * 2
        height: Math.min(menu.height - Kirigami.Units.gridUnit * 4, Kirigami.Units.gridUnit * 22)
        x: Math.round((menu.width - width) / 2)
        y: Math.round((menu.height - height) / 2)
        title: i18n("Link an app")
        standardButtons: QQC2.Dialog.Cancel

        contentItem: ColumnLayout {
            spacing: Kirigami.Units.smallSpacing
            PlasmaComponents.TextField {
                id: appPickFilter
                Layout.fillWidth: true
                placeholderText: i18n("Search apps")
                clearButtonShown: true
            }
            ListView {
                id: appPickView
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                QQC2.ScrollBar.vertical: QQC2.ScrollBar {}
                model: {
                    var f = appPickFilter.text.trim().toLowerCase()
                    if (f === "") return menu.appPickList
                    return menu.appPickList.filter(function (a) { return a.name.toLowerCase().indexOf(f) >= 0 })
                }
                delegate: QQC2.ItemDelegate {
                    width: ListView.view.width
                    text: modelData.name
                    icon.name: String(modelData.icon).indexOf("/") < 0 ? modelData.icon : ""
                    icon.source: String(modelData.icon).indexOf("/") >= 0 ? modelData.icon : ""
                    onClicked: {
                        menu.addCustomPlace({ kind: "app", name: modelData.name, target: modelData.path, icon: modelData.icon })
                        appPickDialog.close()
                    }
                }
            }
        }
    }

    // ------------------------------------------------------------------ profile picture
    readonly property string homeUrl: StandardPaths.writableLocation(StandardPaths.HomeLocation)
    readonly property bool useCustomAvatar: Plasmoid.configuration.avatarMode === "custom" && Plasmoid.configuration.avatarPath !== ""
    readonly property string avatarSource: useCustomAvatar
        ? Plasmoid.configuration.avatarPath
        : (systemAvatar !== "" ? "file://" + systemAvatar : homeUrl + (faceTry === 0 ? "/.face.icon" : "/.face"))

    // ------------------------------------------------------------------ rounded corners
    // Rounds the corners on the edges AWAY from the panel (panel on top -> bottom corners, etc.)
    readonly property int panelEdge: Plasmoid.location
    readonly property real cornerR: Plasmoid.configuration.roundCorners ? Plasmoid.configuration.cornerRadius : 0
    readonly property bool roundTopCorners: panelEdge === PlasmaCore.Types.BottomEdge
    readonly property bool roundBottomCorners: panelEdge === PlasmaCore.Types.TopEdge
        || (panelEdge !== PlasmaCore.Types.BottomEdge && panelEdge !== PlasmaCore.Types.LeftEdge && panelEdge !== PlasmaCore.Types.RightEdge)
    readonly property bool roundLeftCorners: panelEdge === PlasmaCore.Types.RightEdge
    readonly property bool roundRightCorners: panelEdge === PlasmaCore.Types.LeftEdge

    // Shared animation phase for the animated accent styles (all accent pieces stay in sync)
    property real accentPhase: 0
    readonly property bool accentOn: Plasmoid.configuration.roundCorners
    readonly property string accentArea: Plasmoid.configuration.accentArea
    readonly property bool accentAnimated: accentOn && (Plasmoid.configuration.accentStyle === "rgbfade" || Plasmoid.configuration.accentStyle === "flow")
    NumberAnimation on accentPhase {
        from: 0
        to: 1
        duration: Math.max(1, Plasmoid.configuration.accentSpeed) * 1000
        loops: Animation.Infinite
        running: menu.accentAnimated && menu.open
    }

    // Tinted area behind everything: right pane / whole menu (not used for "outer border only")
    AccentBorder {
        anchors.fill: parent
        z: -1
        mode: "fill"
        visible: menu.accentOn && menu.accentArea !== "outer"
        fillOpacity: Plasmoid.configuration.accentFill / 100
        phase: menu.accentPhase
        style: Plasmoid.configuration.accentStyle
        color1: Plasmoid.configuration.accentColor1
        color2: Plasmoid.configuration.accentColor2
        speed: Plasmoid.configuration.accentSpeed
        tl: (menu.roundTopCorners || menu.roundLeftCorners) ? menu.cornerR : 0
        tr: (menu.roundTopCorners || menu.roundRightCorners) ? menu.cornerR : 0
        bl: (menu.roundBottomCorners || menu.roundLeftCorners) ? menu.cornerR : 0
        br: (menu.roundBottomCorners || menu.roundRightCorners) ? menu.cornerR : 0
    }

    // Accent border around the whole menu (also rounds the corners away from the panel)
    AccentBorder {
        anchors.fill: parent
        z: 100
        mode: "ring"
        visible: menu.accentOn && menu.accentArea === "outer"
        phase: menu.accentPhase
        style: Plasmoid.configuration.accentStyle
        color1: Plasmoid.configuration.accentColor1
        color2: Plasmoid.configuration.accentColor2
        thickness: Plasmoid.configuration.accentWidth
        speed: Plasmoid.configuration.accentSpeed
        tl: (menu.roundTopCorners || menu.roundLeftCorners) ? menu.cornerR : 0
        tr: (menu.roundTopCorners || menu.roundRightCorners) ? menu.cornerR : 0
        bl: (menu.roundBottomCorners || menu.roundLeftCorners) ? menu.cornerR : 0
        br: (menu.roundBottomCorners || menu.roundRightCorners) ? menu.cornerR : 0
    }

    Component {
        id: classicComp
        ClassicLayout { m: menu }
    }
    Loader {
        id: classicLoader
        anchors.fill: parent
        active: menu.classic
        sourceComponent: classicComp
    }

    RowLayout {
        visible: !menu.classic
        anchors.fill: parent
        anchors.margins: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing

        // =========================== LEFT PANE (system theme) ===========================
        Rectangle {
            id: leftPane
            Layout.fillHeight: true
            Layout.preferredWidth: Kirigami.Units.gridUnit * 15
            radius: 4

            Kirigami.Theme.colorSet: Kirigami.Theme.View
            Kirigami.Theme.inherit: false

            color: Kirigami.Theme.backgroundColor
            readonly property bool accented: menu.accentOn && menu.accentArea !== "outer"
            border.width: 1
            border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.25)

            // "Whole menu": tint the left pane too (sits under the items)
            AccentBorder {
                anchors.fill: parent
                mode: "fill"
                visible: leftPane.accented && menu.accentArea === "menu"
                fillOpacity: Plasmoid.configuration.accentFill / 100
                phase: menu.accentPhase
                style: Plasmoid.configuration.accentStyle
                color1: Plasmoid.configuration.accentColor1
                color2: Plasmoid.configuration.accentColor2
                tl: 4; tr: 4; bl: 4; br: 4
            }
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 2
                spacing: 0

                StackLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    currentIndex: searchField.text.length > 0 ? 2 : (menu.showAll ? 1 : 0)

                    // ---- 0: Pinned (top, only when something is pinned) + Recent programs ----
                    ColumnLayout {
                        spacing: 0

                        Column {
                            id: pinnedColumn
                            Layout.fillWidth: true
                            visible: menu.pinnedApps.length > 0

                            Repeater {
                                model: menu.pinnedApps
                                delegate: Win7Item {
                                    id: pinnedItem
                                    width: pinnedColumn.width
                                    highlighted: menu.navKey === "p:" + index
                                    iconSize: Kirigami.Units.iconSizes.medium
                                    text: modelData.name
                                    iconSource: modelData.icon
                                    dragUrl: menu.dragUrlFor(modelData)
                                    onDragStarted: menu.dragging = true
                                    onDragEnded: menu.dragging = false
                                    onClicked: menu.launchApp(modelData)
                                    onRightClicked: (mx, my) => menu.openContext(modelData, pinnedItem, mx, my)
                                }
                            }
                        }

                        Rectangle { // margin separator between pinned and recent
                            Layout.fillWidth: true
                            Layout.leftMargin: Kirigami.Units.largeSpacing
                            Layout.rightMargin: Kirigami.Units.largeSpacing
                            Layout.topMargin: 2
                            Layout.bottomMargin: 2
                            Layout.preferredHeight: 1
                            visible: menu.pinnedApps.length > 0 && Plasmoid.configuration.showRecents
                            color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.2)
                        }

                        Item { // recent programs
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            visible: Plasmoid.configuration.showRecents

                            ListView {
                                id: recentList
                                anchors.fill: parent
                                clip: true
                                interactive: true
                                boundsBehavior: Flickable.StopAtBounds
                                model: menu.recentModel
                                QQC2.ScrollBar.vertical: QQC2.ScrollBar {}
                                readonly property real barPad: contentHeight > height ? Kirigami.Units.gridUnit : 0
                                delegate: Win7Item {
                                    id: recentItem
                                    readonly property var appRec: menu.lookupApp(model.favoriteId, model.display)
                                    visible: index < menu.maxRecents
                                    height: visible ? implicitHeight : 0
                                    width: ListView.view.width - recentList.barPad
                                    dragUrl: menu.dragUrlFor(appRec)
                                    onDragStarted: menu.dragging = true
                                    onDragEnded: menu.dragging = false
                                    highlighted: menu.navKey === "r:" + index
                                    iconSize: Kirigami.Units.iconSizes.medium
                                    text: model.display
                                    iconSource: model.decoration
                                    onClicked: {
                                        menu.recentModel.trigger(index, "", null)
                                        menu.launched()
                                    }
                                    onRightClicked: (mx, my) => menu.openContext(menu.lookupApp(model.favoriteId, model.display), recentItem, mx, my)
                                }
                            }
                            PlasmaComponents.Label {
                                anchors.centerIn: parent
                                visible: recentList.count === 0 && menu.pinnedApps.length === 0
                                opacity: 0.6
                                text: i18n("No recent programs")
                            }
                        }

                        Item { // recents turned off: keep the pane filled and hint at pinning
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            visible: !Plasmoid.configuration.showRecents

                            PlasmaComponents.Label {
                                anchors.centerIn: parent
                                width: parent.width - Kirigami.Units.gridUnit * 2
                                visible: menu.pinnedApps.length === 0
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.WordWrap
                                opacity: 0.6
                                text: i18n("Right-click a program in All Programs and choose “Pin to Start”.")
                            }
                        }
                    }

                    // ---- 1: All Programs (categories, then your own folders) ----
                    Item {
                        ListView {
                            id: allList
                            anchors.fill: parent
                            clip: true
                            // leave room for the scrollbar so it doesn't cover the arrows
                            readonly property real barPad: contentHeight > height ? Kirigami.Units.gridUnit : 0
                            model: menu.allEntries
                            boundsBehavior: Flickable.StopAtBounds
                            QQC2.ScrollBar.vertical: QQC2.ScrollBar {}

                            delegate: Item {
                                id: row
                                property var entry: modelData
                                readonly property bool isOpen: !!menu.expandedMap[entry.key]
                                readonly property bool expandable: entry.type === "cat" || entry.type === "folder"

                                width: ListView.view.width - allList.barPad
                                height: col.implicitHeight

                                Column {
                                    id: col
                                    width: parent.width

                                    // separator between built-in categories and your folders
                                    Item {
                                        visible: row.entry.type === "sep"
                                        width: parent.width
                                        height: Kirigami.Units.largeSpacing
                                        Rectangle {
                                            anchors.centerIn: parent
                                            width: parent.width - Kirigami.Units.largeSpacing * 2
                                            height: 1
                                            color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.2)
                                        }
                                    }

                                    Win7Item {
                                        id: header
                                        visible: row.entry.type !== "sep"
                                        width: parent.width
                                        iconSize: Kirigami.Units.iconSizes.smallMedium
                                        text: row.entry.name || ""
                                        iconSource: row.entry.icon || ""
                                        showArrow: row.expandable
                                        arrowOpen: row.isOpen
                                        property bool dropHover: false
                                        highlighted: dropHover || menu.navKey === row.entry.key
                                        onHighlightedChanged: if (highlighted) menu.reveal(allList, header)
                                        Component.onCompleted: if (highlighted) menu.reveal(allList, header)
                                        onClicked: {
                                            if (row.entry.type === "new") {
                                                menu.openNameDialog("new", -1)
                                            } else {
                                                menu.toggleOpen(row.entry.key)
                                            }
                                        }
                                        onRightClicked: (mx, my) => menu.openFolderContext(row.entry, header, mx, my)

                                        DropArea {
                                            anchors.fill: parent
                                            enabled: row.entry.type === "folder"
                                            onEntered: drag => {
                                                drag.accepted = drag.hasUrls
                                                header.dropHover = drag.hasUrls
                                            }
                                            onExited: header.dropHover = false
                                            onDropped: drop => {
                                                header.dropHover = false
                                                menu.dropOnFolder(row.entry.folderIndex, drop.urls)
                                                drop.accept(Qt.CopyAction)
                                            }
                                        }
                                    }

                                    Repeater {
                                        model: row.isOpen ? row.entry.apps : []
                                        delegate: Win7Item {
                                            id: appRow
                                            property var appData: modelData
                                            width: col.width
                                            leftIndent: Kirigami.Units.gridUnit
                                            iconSize: Kirigami.Units.iconSizes.small
                                            text: appData.name
                                            iconSource: appData.icon
                                            highlighted: menu.navKey === row.entry.key + "/" + index
                                            onHighlightedChanged: if (highlighted) menu.reveal(allList, appRow)
                                            Component.onCompleted: if (highlighted) menu.reveal(allList, appRow)
                                            onClicked: menu.launchEntry(appData)
                                            onRightClicked: (mx, my) => menu.openItemContext(row.entry, appData, appRow, mx, my)
                                        }
                                    }

                                    PlasmaComponents.Label {
                                        visible: row.isOpen && row.entry.type === "folder" && row.entry.apps.length === 0
                                        leftPadding: Kirigami.Units.gridUnit * 2
                                        topPadding: Kirigami.Units.smallSpacing
                                        bottomPadding: Kirigami.Units.smallSpacing
                                        opacity: 0.6
                                        text: i18n("(Empty — right-click the folder to add items)")
                                    }
                                }
                            }
                        }
                        PlasmaComponents.Label {
                            anchors.centerIn: parent
                            visible: Plasmoid.configuration.showCategories && menu.categories.length === 0
                            opacity: 0.6
                            text: i18n("Loading programs…")
                        }
                    }

                    // ---- 2: Search results (programs + files in your home folder) ----
                    Item {
                        ListView {
                            id: resultsList
                            anchors.fill: parent
                            clip: true
                            readonly property real barPad: contentHeight > height ? Kirigami.Units.gridUnit : 0
                            model: menu.searchResults
                            boundsBehavior: Flickable.StopAtBounds
                            QQC2.ScrollBar.vertical: QQC2.ScrollBar {}

                            delegate: Item {
                                id: res
                                property var r: modelData
                                width: ListView.view.width - resultsList.barPad
                                height: r.type === "header" ? hdr.implicitHeight + Kirigami.Units.smallSpacing * 2 : resItem.implicitHeight

                                PlasmaComponents.Label {
                                    id: hdr
                                    visible: res.r.type === "header"
                                    x: Kirigami.Units.smallSpacing * 2
                                    y: Kirigami.Units.smallSpacing
                                    font.bold: true
                                    opacity: 0.7
                                    text: res.r.text || ""
                                }

                                Win7Item {
                                    id: resItem
                                    visible: res.r.type !== "header"
                                    width: parent.width
                                    iconSize: Kirigami.Units.iconSizes.smallMedium
                                    text: res.r.type === "app" ? res.r.app.name : (res.r.type === "file" ? res.r.file.name : "")
                                    iconSource: res.r.type === "app" ? res.r.app.icon
                                              : (res.r.type === "file" ? (res.r.file.dir ? "folder" : "text-x-generic") : "")
                                    highlighted: res.r.type !== "header" && menu.navKey === "s:" + res.r.nav
                                    onHighlightedChanged: if (highlighted) menu.reveal(resultsList, resItem)
                                    Component.onCompleted: if (highlighted) menu.reveal(resultsList, resItem)
                                    onClicked: menu.activateResult(res.r)
                                    onRightClicked: (mx, my) => {
                                        if (res.r.type === "app") menu.openContext(res.r.app, resItem, mx, my)
                                    }
                                }
                            }
                        }
                        PlasmaComponents.Label {
                            anchors.centerIn: parent
                            visible: menu.searchResults.length === 0
                            opacity: 0.6
                            text: menu.fileSearching ? i18n("Searching…") : i18n("No results found")
                        }
                    }
                }

                // separator
                Rectangle {
                    Layout.fillWidth: true
                    Layout.leftMargin: Kirigami.Units.largeSpacing
                    Layout.rightMargin: Kirigami.Units.largeSpacing
                    Layout.preferredHeight: 1
                    color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.2)
                }

                // All Programs / Back
                Win7Item {
                    Layout.fillWidth: true
                    Layout.topMargin: 2
                    iconSize: Kirigami.Units.iconSizes.small
                    bold: true
                    text: menu.showAll ? i18n("Back") : i18n("All Programs")
                    iconSource: menu.showAll ? "go-previous" : "go-next"
                    highlighted: menu.navKey === (menu.showAll ? "back" : "allbtn")
                    onClicked: {
                        searchField.text = ""
                        menu.showAll = !menu.showAll
                    }
                }

                // Search box
                PlasmaComponents.TextField {
                    id: searchField
                    Layout.fillWidth: true
                    Layout.margins: Kirigami.Units.smallSpacing + 2
                    placeholderText: i18n("Search programs and files")
                    clearButtonShown: true
                    rightPadding: text === "" ? magnifier.width + Kirigami.Units.smallSpacing * 2 : undefined

                    // magnifying glass on the far right, like the Windows 7 search box
                    PlasmaComponents.Label {
                        id: magnifier
                        visible: searchField.text === ""
                        anchors.right: parent.right
                        anchors.rightMargin: Kirigami.Units.smallSpacing * 2
                        anchors.verticalCenter: parent.verticalCenter
                        text: "🔍"
                        opacity: 0.8
                    }
                    onTextChanged: searchTimer.restart()
                    Keys.onUpPressed: event => { menu.navMove(-1); event.accepted = true }
                    Keys.onDownPressed: event => { menu.navMove(1); event.accepted = true }
                    Keys.onRightPressed: event => {
                        if (text === "") { menu.navRight(); event.accepted = true } else { event.accepted = false }
                    }
                    Keys.onLeftPressed: event => {
                        if (text === "") { menu.navLeft(); event.accepted = true } else { event.accepted = false }
                    }
                    Keys.onReturnPressed: event => { menu.navActivate(); event.accepted = true }
                    Keys.onEnterPressed: event => { menu.navActivate(); event.accepted = true }
                    Keys.onEscapePressed: event => {
                        if (text.length > 0) { text = "" } else { menu.launched() }
                    }
                }
            }
        }

        // =========================== RIGHT PANE (Plasma widget style) ===========================
        ColumnLayout {
            id: rightPane
            Layout.fillHeight: true
            Layout.preferredWidth: Kirigami.Units.gridUnit * 11
            spacing: 0

            // User picture, centred in the pane
            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: Kirigami.Units.smallSpacing
                Layout.bottomMargin: Kirigami.Units.smallSpacing
                Layout.preferredWidth: Kirigami.Units.iconSizes.huge
                Layout.preferredHeight: Kirigami.Units.iconSizes.huge
                radius: 4
                color: "transparent"
                border.width: 2
                border.color: avatarMouse.containsMouse ? Kirigami.Theme.highlightColor : Qt.rgba(1, 1, 1, 0.6)

                Image {
                    id: face
                    anchors.fill: parent
                    anchors.margins: 2
                    source: menu.avatarSource
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: false
                    visible: status === Image.Ready
                    onStatusChanged: {
                        if (status === Image.Error && !menu.useCustomAvatar && menu.faceTry === 0) {
                            menu.faceTry = 1
                        }
                    }
                }
                Kirigami.Icon {
                    anchors.fill: parent
                    anchors.margins: 2
                    source: "user-identity"
                    visible: face.status !== Image.Ready
                }

                MouseArea {
                    id: avatarMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: menu.changeAvatar()
                    QQC2.ToolTip.visible: containsMouse
                    QQC2.ToolTip.delay: 600
                    QQC2.ToolTip.text: i18n("Change your picture")
                }
            }

            // User name: first entry of the list, opens System Settings > Users
            Win7Item {
                Layout.fillWidth: true
                iconSize: Kirigami.Units.iconSizes.smallMedium
                verticalPadding: Kirigami.Units.smallSpacing + 3
                showIcon: Plasmoid.configuration.showPlaceIcons
                text: menu.fullName
                iconSource: "user-identity"
                highlighted: menu.navKey === "u"
                onClicked: menu.openUsers()
            }

            Item { // small gap under the user name
                Layout.fillWidth: true
                Layout.preferredHeight: Kirigami.Units.smallSpacing
            }

            ListView {
                id: placesList
                Layout.fillWidth: true
                Layout.fillHeight: true
                // a long custom list scrolls; it must never make the whole menu taller
                Layout.preferredHeight: menu.customPlacesOn ? Math.min(contentHeight, Kirigami.Units.gridUnit * 10) : contentHeight
                Layout.minimumHeight: menu.customPlacesOn ? Math.min(contentHeight, Kirigami.Units.gridUnit * 6) : contentHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: menu.visiblePlaces
                QQC2.ScrollBar.vertical: QQC2.ScrollBar {}
                readonly property real barPad: contentHeight > height ? Kirigami.Units.gridUnit * 0.8 : 0

                // right-click on empty space: add a folder or an app
                MouseArea {
                    anchors.fill: parent
                    z: -1
                    enabled: menu.customPlacesOn
                    acceptedButtons: Qt.RightButton
                    onClicked: mouse => menu.openPlacesMenu(-1, placesList, mouse.x, mouse.y)
                }
                PlasmaComponents.Label {
                    anchors.centerIn: parent
                    width: parent.width - Kirigami.Units.gridUnit
                    visible: menu.customPlacesOn && placesList.count === 0
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    opacity: 0.6
                    text: i18n("Right-click here to link a folder or an app.")
                }

                delegate: Item {
                    width: ListView.view.width - placesList.barPad
                    height: modelData.sep ? Kirigami.Units.largeSpacing : entry.implicitHeight

                    Rectangle {
                        visible: !!modelData.sep
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: Kirigami.Units.smallSpacing
                        anchors.rightMargin: Kirigami.Units.smallSpacing
                        height: 1
                        color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.25)
                    }
                    MouseArea {  // right-click on a separator
                        visible: !!modelData.sep && menu.customPlacesOn
                        anchors.fill: parent
                        acceptedButtons: Qt.RightButton
                        onClicked: mouse => menu.openPlacesMenu(index, parent, mouse.x, mouse.y)
                    }

                    Win7Item {
                        id: entry
                        visible: !modelData.sep
                        anchors.left: parent.left
                        anchors.right: parent.right
                        iconSize: Kirigami.Units.iconSizes.smallMedium
                        verticalPadding: Kirigami.Units.smallSpacing + 3
                        showIcon: Plasmoid.configuration.showPlaceIcons
                        text: modelData.name || ""
                        iconSource: modelData.icon || ""
                        highlighted: menu.navKey === "pl:" + index
                        onClicked: menu.activatePlace(modelData)
                        onRightClicked: (mx, my) => {
                            if (menu.customPlacesOn) menu.openPlacesMenu(index, entry, mx, my)
                            else if (modelData.kind === "computer") computerMenu.popup(entry, mx, my)
                        }
                    }
                }
            }


            // Shut down split button
            RowLayout {
                Layout.alignment: Qt.AlignLeft
                Layout.margins: Kirigami.Units.smallSpacing
                spacing: 0

                PlasmaComponents.Button {
                    id: shutBtn
                    Layout.fillHeight: true
                    text: i18n("Shut down")
                    icon.name: "system-shutdown"
                    highlighted: menu.navKey === "shutdown"
                    onClicked: menu.shutDown()
                }
                PlasmaComponents.Button {
                    id: powerArrow
                    // same height as Shut down (an icon-only button is otherwise a little shorter)
                    Layout.fillHeight: true
                    Layout.preferredHeight: shutBtn.implicitHeight
                    Layout.minimumHeight: shutBtn.implicitHeight
                    icon.name: "arrow-right"
                    onClicked: powerMenu.popup(powerArrow, powerArrow.width, 0)

                    Win7Menu {
                        id: powerMenu
                        host: menu
                        fixedCorner: true
                        cornerMarginX: Kirigami.Units.smallSpacing * 2
                        cornerMarginY: powerArrow.height + Kirigami.Units.smallSpacing * 3
                        MenuEntry {
                            visible: menu.gamingModeAvailable
                            text: i18n("Return to gaming mode")
                            icon.name: "input-gamepad"
                            onTriggered: menu.returnToGamingMode()
                        }
                        MenuEntry { separator: true; visible: menu.gamingModeAvailable }
                        MenuEntry {
                            text: i18n("Lock")
                            icon.name: "system-lock-screen"
                            onTriggered: { menu.runCommand("loginctl lock-session"); menu.launched() }
                        }
                        MenuEntry {
                            text: i18n("Log off")
                            icon.name: "system-log-out"
                            onTriggered: { menu.runCommand("dbus-send --session --type=method_call --dest=org.kde.LogoutPrompt /LogoutPrompt org.kde.LogoutPrompt.promptLogout"); menu.launched() }
                        }
                        MenuEntry {
                            text: i18n("Restart")
                            icon.name: "system-reboot"
                            onTriggered: menu.restart()
                        }
                        MenuEntry {
                            text: i18n("Sleep")
                            icon.name: "system-suspend"
                            onTriggered: { menu.runCommand("systemctl suspend"); menu.launched() }
                        }
                        MenuEntry {
                            text: i18n("Hibernate")
                            icon.name: "system-suspend-hibernate"
                            onTriggered: { menu.runCommand("systemctl hibernate"); menu.launched() }
                        }
                    }
                }
            }
        }
    }
}

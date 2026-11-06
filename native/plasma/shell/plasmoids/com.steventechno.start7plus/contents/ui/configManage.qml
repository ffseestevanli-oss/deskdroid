import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Dialogs
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.plasma.private.kicker as Kicker

KCM.SimpleKCM {
    id: page

    property var cfg_pinnedIds: []
    property var cfg_pinnedIdsDefault: []
    property string cfg_customFolders: ""
    property string cfg_customFoldersDefault: ""

    readonly property int maxPinned: 8
    property var apps: ({})            // desktop id -> { name, icon, path }
    property int pickFolder: -1

    readonly property var folders: {
        try {
            var a = JSON.parse(page.cfg_customFolders || "[]")
            return Array.isArray(a) ? a : []
        } catch (e) { return [] }
    }
    readonly property var pinned: page.cfg_pinnedIds ? page.cfg_pinnedIds : []

    // ---- app names/icons for the ids we store ----
    // DeskDroid: the app menu from Kicker's ProcessRunner (no Python on Android).
    Kicker.ProcessRunner { id: runner }
    function indexMenu(cats) {
        var m = {}
        for (var i = 0; i < cats.length; ++i)
            for (var j = 0; j < cats[i].apps.length; ++j) m[cats[i].apps[j].id] = cats[i].apps[j]
        page.apps = m
    }
    Component.onCompleted: if (typeof runner.appMenu === "function") indexMenu(runner.appMenu())
    Plasma5Support.DataSource {
        id: scan
        engine: "executable"
        connectedSources: typeof runner.appMenu === "function" ? []
            : ['python3 "' + Qt.resolvedUrl("../code/apps.py").toString().replace("file://", "") + '"']
        onNewData: (sourceName, data) => {
            try {
                var cats = JSON.parse(data["stdout"]), m = {}
                for (var i = 0; i < cats.length; ++i)
                    for (var j = 0; j < cats[i].apps.length; ++j) m[cats[i].apps[j].id] = cats[i].apps[j]
                page.apps = m
            } catch (e) { }
            disconnectSource(sourceName)
        }
    }

    function appName(id) { return page.apps[id] ? page.apps[id].name : id.replace(/\.desktop$/, "") }
    function appIcon(id) { return page.apps[id] ? page.apps[id].icon : "application-x-executable" }

    // ---- pinned ----
    function movePin(i, d) {
        var a = page.pinned.slice(), j = i + d
        if (j < 0 || j >= a.length) return
        var t = a[i]; a[i] = a[j]; a[j] = t
        page.cfg_pinnedIds = a
    }
    function removePin(i) {
        var a = page.pinned.slice()
        a.splice(i, 1)
        page.cfg_pinnedIds = a
    }

    // ---- folders ----
    function saveFolders(a) { page.cfg_customFolders = JSON.stringify(a) }
    function cloned() { return JSON.parse(JSON.stringify(page.folders)) }
    function addFolder() {
        var a = cloned(); a.push({ name: i18n("New folder"), items: [] }); saveFolders(a)
    }
    function renameFolder(i, name) {
        var a = cloned(); if (i < a.length && name.trim() !== "") { a[i].name = name.trim(); saveFolders(a) }
    }
    function deleteFolder(i) { var a = cloned(); a.splice(i, 1); saveFolders(a) }
    function removeItem(i, j) { var a = cloned(); a[i].items.splice(j, 1); saveFolders(a) }
    function addFiles(i, urls) {
        var a = cloned()
        for (var n = 0; n < urls.length; ++n) {
            var u = String(urls[n])
            var base = decodeURIComponent(u.substring(u.lastIndexOf("/") + 1))
            if (u.toLowerCase().endsWith(".desktop")) {
                var ap = page.apps[base]
                a[i].items.push({ kind: "app", id: base, name: ap ? ap.name : base.replace(/\.desktop$/i, ""),
                                  icon: ap ? ap.icon : "application-x-executable",
                                  path: ap ? ap.path : decodeURIComponent(u.replace("file://", "")) })
            } else {
                a[i].items.push({ kind: "file", name: base, path: u, icon: "" })
            }
        }
        saveFolders(a)
    }

    FileDialog {
        id: filePicker
        title: i18n("Add files or programs to the folder")
        fileMode: FileDialog.OpenFiles
        onAccepted: page.addFiles(page.pickFolder, selectedFiles)
    }

    ColumnLayout {
        spacing: Kirigami.Units.smallSpacing

        Kirigami.Heading {
            level: 3
            text: i18n("Pinned programs (%1 of %2)", page.pinned.length, page.maxPinned)
        }
        QQC2.Label {
            visible: page.pinned.length === 0
            opacity: 0.6
            text: i18n("Nothing pinned. Right-click a program in the start menu and choose “Pin to Start”.")
        }
        Repeater {
            model: page.pinned
            delegate: RowLayout {
                Layout.fillWidth: true
                Kirigami.Icon { source: page.appIcon(modelData); Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium; Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium }
                QQC2.Label { Layout.fillWidth: true; Layout.minimumWidth: Kirigami.Units.gridUnit * 10; elide: Text.ElideRight; text: page.appName(modelData) }
                QQC2.ToolButton { icon.name: "go-up"; enabled: index > 0; onClicked: page.movePin(index, -1) }
                QQC2.ToolButton { icon.name: "go-down"; enabled: index < page.pinned.length - 1; onClicked: page.movePin(index, 1) }
                QQC2.ToolButton { icon.name: "list-remove"; onClicked: page.removePin(index) }
            }
        }

        Kirigami.Separator { Layout.fillWidth: true; Layout.topMargin: Kirigami.Units.largeSpacing }

        Kirigami.Heading {
            level: 3
            text: i18n("Your folders in All Programs")
        }
        QQC2.Label {
            visible: page.folders.length === 0
            opacity: 0.6
            text: i18n("No folders yet.")
        }
        Repeater {
            model: page.folders
            delegate: ColumnLayout {
                id: fcol
                property int fi: index
                property var fdata: modelData
                Layout.fillWidth: true
                spacing: 2

                RowLayout {
                    Layout.fillWidth: true
                    Kirigami.Icon { source: "folder"; Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium; Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium }
                    QQC2.TextField {
                        Layout.fillWidth: true
                        Layout.minimumWidth: Kirigami.Units.gridUnit * 10
                        text: fcol.fdata.name
                        onEditingFinished: page.renameFolder(fcol.fi, text)
                    }
                    QQC2.ToolButton {
                        icon.name: "document-open"
                        onClicked: { page.pickFolder = fcol.fi; filePicker.open() }
                        QQC2.ToolTip.visible: hovered
                        QQC2.ToolTip.text: i18n("Add file or program")
                    }
                    QQC2.ToolButton {
                        icon.name: "edit-delete"
                        onClicked: page.deleteFolder(fcol.fi)
                        QQC2.ToolTip.visible: hovered
                        QQC2.ToolTip.text: i18n("Delete folder")
                    }
                }
                Repeater {
                    model: fcol.fdata.items
                    delegate: RowLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: Kirigami.Units.gridUnit * 1.5
                        Kirigami.Icon {
                            source: modelData.kind === "app" ? page.appIcon(modelData.id) : "text-x-generic"
                            Layout.preferredWidth: Kirigami.Units.iconSizes.small
                            Layout.preferredHeight: Kirigami.Units.iconSizes.small
                        }
                        QQC2.Label {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: modelData.kind === "app" ? page.appName(modelData.id) : modelData.name
                        }
                        QQC2.ToolButton {
                            icon.name: "list-remove"
                            onClicked: page.removeItem(fcol.fi, index)
                        }
                    }
                }
            }
        }

        QQC2.Button {
            text: i18n("New folder")
            icon.name: "folder-new"
            onClicked: page.addFolder()
        }
    }
}

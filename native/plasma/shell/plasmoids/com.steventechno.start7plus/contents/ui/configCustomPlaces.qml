import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Dialogs
import QtQuick.Layouts
import QtCore
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    id: page

    property bool cfg_useCustomPlaces: false
    property bool cfg_useCustomPlacesDefault: false
    property string cfg_customPlaces: ""
    property string cfg_customPlacesDefault: ""
    property bool cfg_placesLimitUnlocked: false
    property bool cfg_placesLimitUnlockedDefault: false
    readonly property int limit: 16
    readonly property bool atLimit: !cfg_placesLimitUnlocked && entries.length >= limit

    property int pickIndex: -1

    readonly property var entries: {
        try {
            var a = JSON.parse(page.cfg_customPlaces || "[]")
            return Array.isArray(a) ? a : []
        } catch (e) { return [] }
    }

    function save(a) { page.cfg_customPlaces = JSON.stringify(a) }
    function cloned() { return JSON.parse(JSON.stringify(page.entries)) }

    function setField(i, key, value) {
        var a = cloned()
        if (i < 0 || i >= a.length) return
        a[i][key] = value
        save(a)
    }
    function addPlace() {
        if (atLimit) return
        var a = cloned(); a.push({ kind: "folder", name: "", target: "", icon: "" }); save(a)
    }
    function addSeparator() {
        if (atLimit) return
        var a = cloned(); a.push({ sep: true }); save(a)
    }
    function removeAt(i) { var a = cloned(); a.splice(i, 1); save(a) }
    function move(i, d) {
        var a = cloned(), j = i + d
        if (j < 0 || j >= a.length) return
        var t = a[i]; a[i] = a[j]; a[j] = t
        save(a)
    }
    function lastSegment(url) {
        var u = String(url).replace(/\/+$/, "")
        return decodeURIComponent(u.substring(u.lastIndexOf("/") + 1))
    }
    function fillBuiltIn() {
        var sp = StandardPaths
        var a = [
            { kind: "folder", name: i18n("Documents"), target: sp.writableLocation(sp.DocumentsLocation).toString(), icon: "" },
            { kind: "folder", name: i18n("Pictures"),  target: sp.writableLocation(sp.PicturesLocation).toString(), icon: "" },
            { kind: "folder", name: i18n("Music"),     target: sp.writableLocation(sp.MusicLocation).toString(), icon: "" },
            { kind: "folder", name: i18n("Videos"),    target: sp.writableLocation(sp.MoviesLocation).toString(), icon: "" },
            { kind: "folder", name: i18n("Downloads"), target: sp.writableLocation(sp.DownloadLocation).toString(), icon: "" },
            { sep: true },
            { kind: "folder", name: i18n("Computer"),  target: sp.writableLocation(sp.HomeLocation).toString(), icon: "computer" },
            { kind: "link",   name: i18n("Network"),   target: "remote:///", icon: "network-workgroup" },
            { kind: "link",   name: i18n("Trash"),     target: "trash:///", icon: "user-trash" },
            { sep: true },
            { kind: "command", name: i18n("System Settings"), target: "systemsettings", icon: "preferences-system" },
            { kind: "command", name: i18n("Help and Support"), target: "khelpcenter", icon: "help-browser" }
        ]
        save(a)
    }

    FolderDialog {
        id: folderPicker
        title: i18n("Choose a folder")
        onAccepted: {
            var u = selectedFolder.toString()
            page.setField(page.pickIndex, "target", u)
            if (!page.entries[page.pickIndex].name) page.setField(page.pickIndex, "name", page.lastSegment(u))
        }
    }
    FileDialog {
        id: filePicker
        title: i18n("Choose a file or program")
        fileMode: FileDialog.OpenFile
        onAccepted: {
            var u = selectedFile.toString()
            page.setField(page.pickIndex, "target", u)
            if (!page.entries[page.pickIndex].name) page.setField(page.pickIndex, "name", page.lastSegment(u))
        }
    }
    FileDialog {
        id: iconPicker
        title: i18n("Choose an icon image")
        fileMode: FileDialog.OpenFile
        nameFilters: [i18n("Images (*.png *.jpg *.jpeg *.bmp *.webp *.gif *.svg)")]
        onAccepted: page.setField(page.pickIndex, "icon", selectedFile.toString())
    }

    ColumnLayout {
        spacing: Kirigami.Units.smallSpacing

        QQC2.CheckBox {
            text: i18n("Set your own places")
            checked: page.cfg_useCustomPlaces
            onToggled: page.cfg_useCustomPlaces = checked
        }
        QQC2.Label {
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 36
            wrapMode: Text.WordWrap
            opacity: 0.7
            text: i18n("Replace the built-in places on the right pane with your own list. Add as many as you like: a scrollbar appears in the menu when they don't all fit. The Places tab is ignored while this is on.")
        }

        RowLayout {
            enabled: page.cfg_useCustomPlaces
            QQC2.Label {
                text: page.cfg_placesLimitUnlocked
                      ? i18n("%1 places (no limit)", page.entries.length)
                      : i18n("%1 of %2 places", page.entries.length, page.limit)
            }
            QQC2.Button {
                icon.name: page.cfg_placesLimitUnlocked ? "object-locked" : "object-unlocked"
                text: page.cfg_placesLimitUnlocked ? i18n("Restore the limit") : i18n("Remove limit")
                onClicked: page.cfg_placesLimitUnlocked = !page.cfg_placesLimitUnlocked
            }
        }
        QQC2.Label {
            visible: !page.cfg_placesLimitUnlocked
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 36
            wrapMode: Text.WordWrap
            opacity: 0.7
            text: i18n("Places are limited to %1 to keep the menu working properly.", page.limit)
        }
        QQC2.Label {
            visible: page.cfg_placesLimitUnlocked
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 36
            wrapMode: Text.WordWrap
            color: Kirigami.Theme.negativeTextColor
            text: i18n("Warning: This may break stuff! Use at your own expense.")
        }

        RowLayout {
            enabled: page.cfg_useCustomPlaces
            QQC2.Button { text: i18n("Add place"); icon.name: "list-add"; enabled: !page.atLimit; onClicked: page.addPlace() }
            QQC2.Button { text: i18n("Add separator"); icon.name: "view-split-top-bottom"; enabled: !page.atLimit; onClicked: page.addSeparator() }
            QQC2.Button {
                text: i18n("Fill with built-in places")
                icon.name: "document-import"
                onClicked: page.fillBuiltIn()
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: i18n("Replaces your list with the standard places so you can edit them")
            }
        }

        QQC2.Label {
            visible: page.cfg_useCustomPlaces && page.entries.length === 0
            opacity: 0.6
            text: i18n("Your list is empty. Add a place, or fill it with the built-in places to start from.")
        }

        Repeater {
            model: page.entries
            delegate: ColumnLayout {
                id: row
                property int ri: index
                property var e: modelData
                visible: page.cfg_useCustomPlaces
                Layout.fillWidth: true
                spacing: 2

                // ---- separator row ----
                RowLayout {
                    visible: !!row.e.sep
                    Layout.fillWidth: true
                    Kirigami.Separator { Layout.fillWidth: true }
                    QQC2.Label { opacity: 0.6; text: i18n("Separator") }
                    Kirigami.Separator { Layout.fillWidth: true }
                    QQC2.ToolButton { icon.name: "go-up"; enabled: row.ri > 0; onClicked: page.move(row.ri, -1) }
                    QQC2.ToolButton { icon.name: "go-down"; enabled: row.ri < page.entries.length - 1; onClicked: page.move(row.ri, 1) }
                    QQC2.ToolButton { icon.name: "list-remove"; onClicked: page.removeAt(row.ri) }
                }

                // ---- place row ----
                RowLayout {
                    visible: !row.e.sep
                    Layout.fillWidth: true
                    QQC2.Button {
                        implicitWidth: Kirigami.Units.iconSizes.medium + Kirigami.Units.largeSpacing
                        implicitHeight: implicitWidth
                        display: QQC2.AbstractButton.IconOnly
                        icon.name: row.e.icon ? "" : (row.e.kind === "command" ? "system-run" : (row.e.kind === "link" ? "internet-web-browser" : (row.e.kind === "file" ? "text-x-generic" : (row.e.kind === "app" ? "system-run" : "folder"))))
                        icon.source: row.e.icon || ""
                        icon.width: Kirigami.Units.iconSizes.smallMedium
                        icon.height: Kirigami.Units.iconSizes.smallMedium
                        onClicked: { page.pickIndex = row.ri; iconPicker.open() }
                        QQC2.ToolTip.visible: hovered
                        QQC2.ToolTip.text: i18n("Choose a custom icon")
                    }
                    QQC2.ToolButton {
                        visible: !!row.e.icon
                        icon.name: "edit-clear"
                        onClicked: page.setField(row.ri, "icon", "")
                        QQC2.ToolTip.visible: hovered
                        QQC2.ToolTip.text: i18n("Use the default icon")
                    }
                    QQC2.TextField {
                        Layout.preferredWidth: Kirigami.Units.gridUnit * 9
                        placeholderText: i18n("Name")
                        text: row.e.name || ""
                        onEditingFinished: page.setField(row.ri, "name", text)
                    }
                    ValueCombo {
                        options: [
                            { text: i18n("Folder"), value: "folder" },
                            { text: i18n("File"), value: "file" },
                            { text: i18n("App (.desktop)"), value: "app" },
                            { text: i18n("Link (URL)"), value: "link" },
                            { text: i18n("Command"), value: "command" }
                        ]
                        current: row.e.kind || "folder"
                        onPicked: v => page.setField(row.ri, "kind", v)
                    }
                    Item { Layout.fillWidth: true }
                    QQC2.ToolButton { icon.name: "go-up"; enabled: row.ri > 0; onClicked: page.move(row.ri, -1) }
                    QQC2.ToolButton { icon.name: "go-down"; enabled: row.ri < page.entries.length - 1; onClicked: page.move(row.ri, 1) }
                    QQC2.ToolButton { icon.name: "list-remove"; onClicked: page.removeAt(row.ri) }
                }
                RowLayout {
                    visible: !row.e.sep
                    Layout.fillWidth: true
                    Layout.leftMargin: Kirigami.Units.iconSizes.medium + Kirigami.Units.largeSpacing
                    QQC2.TextField {
                        Layout.fillWidth: true
                        Layout.maximumWidth: Kirigami.Units.gridUnit * 24
                        placeholderText: row.e.kind === "app" ? i18n("Path to a .desktop file") : row.e.kind === "command" ? i18n("Command to run") : (row.e.kind === "link" ? i18n("https://…") : i18n("Path, e.g. ~/Games"))
                        text: row.e.target || ""
                        onEditingFinished: page.setField(row.ri, "target", text)
                    }
                    QQC2.Button {
                        visible: row.e.kind === "folder" || row.e.kind === "file" || row.e.kind === "app" || !row.e.kind
                        icon.name: "document-open-folder"
                        onClicked: {
                            page.pickIndex = row.ri
                            if (row.e.kind === "file" || row.e.kind === "app") filePicker.open(); else folderPicker.open()
                        }
                        QQC2.ToolTip.visible: hovered
                        QQC2.ToolTip.text: i18n("Browse…")
                    }
                }
                Kirigami.Separator { Layout.fillWidth: true; Layout.topMargin: 2; visible: !row.e.sep; opacity: 0.4 }
            }
        }
    }
}

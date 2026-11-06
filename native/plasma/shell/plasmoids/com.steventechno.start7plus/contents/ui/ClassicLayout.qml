import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

// Windows 9x style menu: banner + one column (pinned on top) + flyouts.
// All logic (launching, pinning, search, places...) lives in StartMenu; `m` is that menu.
Item {
    id: cl

    property var m
    readonly property var cfg: Plasmoid.configuration
    readonly property real u: Kirigami.Units.gridUnit
    readonly property real pad: Kirigami.Units.smallSpacing
    readonly property bool showBanner: cfg.bannerShow
    readonly property real bannerW: showBanner ? u * 2.6 : 0
    readonly property real colW: u * 15
    readonly property real flyW: u * 15
    readonly property real colX: pad + bannerW + (showBanner ? pad : 0)

    property string flyKind: ""
    property var flyItems: []
    property real flyY: 0
    property var subItems: []
    property real subY: 0

    // size the menu asks for: grows to the right while flyouts are open
    readonly property real requiredWidth: colX + colW + pad
        + (flyKind !== "" ? flyW : 0) + (subItems.length > 0 ? flyW : 0)
    readonly property real requiredHeight: col.implicitHeight + pad * 2

    // ---------------------------------------------------------------- flyout contents
    function buildItems(kind) {
        var out = [], i
        if (kind === "programs") {
            var ents = m.allEntries
            for (i = 0; i < ents.length; ++i) {
                var en = ents[i]
                if (en.type === "sep") { out.push({ sep: true }); continue }
                if (en.type === "new") { out.push({ type: "new", name: en.name, icon: en.icon }); continue }
                var kids = []
                for (var j = 0; j < en.apps.length; ++j) {
                    var a = en.apps[j]
                    kids.push(en.type === "folder"
                        ? { type: "entry", name: a.name, icon: a.icon, entry: a, parent: en }
                        : { type: "app", name: a.name, icon: a.icon, app: a, parent: en })
                }
                if (kids.length === 0) kids.push({ type: "none", name: i18n("(Empty)"), icon: "" })
                out.push({ type: "sub", name: en.name, icon: en.icon, entry: en, children: kids })
            }
        } else if (kind === "places") {
            var pl = m.visiblePlaces
            for (i = 0; i < pl.length; ++i) {
                out.push(pl[i].sep ? { sep: true } : { type: "place", name: pl[i].name, icon: pl[i].icon, place: pl[i] })
            }
        } else if (kind === "settings") {
            var all = m.places
            for (i = 0; i < all.length; ++i) {
                if (all[i].group === 2 && all[i].cmd !== "khelpcenter")
                    out.push({ type: "place", name: all[i].name, icon: all[i].icon, place: all[i] })
            }
            out.push({ sep: true })
            out.push({ type: "action", action: "startsettings", name: i18n("Start Menu Settings…"), icon: "configure" })
        }
        return out
    }

    function clearSearch() { if (m.searchBoxText !== "") m.searchBoxText = "" }
    function openFly(kind, row) {
        if (kind !== "search") clearSearch()
        subItems = []
        flyItems = kind === "recents" ? [] : buildItems(kind)
        flyKind = kind
        flyY = row.mapToItem(cl, 0, 0).y - 3
        if (kind === "search") Qt.callLater(function () { sfield.forceActiveFocus() })
    }
    function closeFly() {
        clearSearch()
        hoverTimer.stop()
        subTimer.stop()
        subItems = []
        flyKind = ""
        flyItems = []
    }
    function openSub(item, row) {
        subItems = item.children
        subY = row.mapToItem(cl, 0, 0).y - 3
    }
    function resetView() {
        closeFly()
    }

    function terminalCmd() {
        return "setsid -f sh -c 'for t in konsole ptyxis gnome-terminal xterm; do command -v $t >/dev/null 2>&1 && exec $t; done' >/dev/null 2>&1 </dev/null"
    }
    function doAction(a) {
        switch (a) {
        case "shutdown":  m.shutDown(); break
        case "logoff":    m.runCommand("dbus-send --session --type=method_call --dest=org.kde.LogoutPrompt /LogoutPrompt org.kde.LogoutPrompt.promptLogout"); m.launched(); break
        case "terminal":  m.runCommand(terminalCmd()); m.launched(); break
        case "help":      m.runCommand("khelpcenter"); m.launched(); break
        case "startsettings":
            m.launched()
            Qt.callLater(function () {
                var act = Plasmoid.internalAction("configure")
                if (act) act.trigger()
            })
            break
        }
    }

    function activateItem(item, index) {
        if (item === null || item === undefined) {            // recents
            m.recentModel.trigger(index, "", null)
            m.launched()
            return
        }
        switch (item.type) {
        case "app":    m.launchApp(item.app); break
        case "entry":  m.launchEntry(item.entry); break
        case "place":  m.activatePlace(item.place); break
        case "action": doAction(item.action); break
        case "new":    m.openNameDialog("new", -1); break
        }
    }

    // hover handling for the column rows (opens/switches/closes the first flyout)
    property string pendingKind: ""
    property Item pendingRow: null
    function hoverMain(kind, row) {
        pendingKind = kind
        pendingRow = row
        hoverTimer.interval = flyKind !== "" ? 60 : 220
        hoverTimer.restart()
    }
    Timer {
        id: hoverTimer
        onTriggered: {
            if (cl.pendingKind === "") cl.closeFly()
            else if (cl.pendingKind !== cl.flyKind) cl.openFly(cl.pendingKind, cl.pendingRow)
        }
    }
    property var subPendingItem: null
    property Item subPendingRow: null
    Timer {
        id: subTimer
        interval: 200
        onTriggered: {
            if (cl.subPendingItem && cl.subPendingItem.type === "sub") cl.openSub(cl.subPendingItem, cl.subPendingRow)
            else cl.subItems = []
        }
    }

    // ---------------------------------------------------------------- banner
    BannerStrip {
        visible: cl.showBanner
        x: cl.pad
        y: cl.pad
        width: cl.bannerW
        height: cl.height - cl.pad * 2
        text: cl.cfg.bannerTextMode === "custom" && cl.cfg.bannerText !== "" ? cl.cfg.bannerText
              : (cl.cfg.bannerTextMode === "pretty" ? (m.distroPretty || m.distroName || "Linux") : (m.distroName || "Linux"))
        style: cl.cfg.bannerStyle
        color1: cl.cfg.bannerColor1
        color2: cl.cfg.bannerColor2
        textColor: cl.cfg.bannerTextColor
        fontSize: cl.cfg.bannerFontSize
        speed: cl.cfg.bannerSpeed
    }

    // ---------------------------------------------------------------- the column
    ColumnLayout {
        id: col
        x: cl.colX
        y: cl.pad
        width: cl.colW
        height: cl.height - cl.pad * 2
        spacing: 0

        Item {
            id: rowsBox
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: rowsCol.implicitHeight + groupCol.implicitHeight

            Column {
                id: rowsCol
                width: parent.width

                // pinned programs (same in both layouts)
                Repeater {
                    model: m.pinnedApps
                    delegate: Win7Item {
                        id: pinRow
                        width: rowsCol.width
                        iconSize: Kirigami.Units.iconSizes.medium
                        text: modelData.name
                        iconSource: modelData.icon
                        dragUrl: m.dragUrlFor(modelData)
                        onDragStarted: m.dragging = true
                        onDragEnded: m.dragging = false
                        onClicked: m.launchApp(modelData)
                        onHoveredChanged: if (hovered) cl.hoverMain("", null)
                        onRightClicked: (mx, my) => m.openContext(modelData, pinRow, mx, my)
                    }
                }

                Rectangle {
                    visible: m.pinnedApps.length > 0
                    width: parent.width
                    height: 1 + cl.pad * 2
                    color: "transparent"
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.margins: cl.pad
                        height: 1
                        color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.25)
                    }
                }

            }

            // everything below the pins sits at the bottom of the menu
            Column {
                id: groupCol
                anchors.bottom: parent.bottom
                width: parent.width

                Win7Item {
                    id: progRow
                    width: rowsCol.width
                    iconSize: Kirigami.Units.iconSizes.medium
                    text: i18n("Programs")
                    iconSource: "applications-all"
                    showArrow: true
                    highlighted: cl.flyKind === "programs"
                    onClicked: cl.openFly("programs", progRow)
                    onHoveredChanged: if (hovered) cl.hoverMain("programs", progRow)
                }
                Win7Item {
                    id: recRow
                    visible: cl.cfg.showRecents
                    height: visible ? implicitHeight : 0
                    width: rowsCol.width
                    iconSize: Kirigami.Units.iconSizes.medium
                    text: i18n("Recents")
                    iconSource: "document-open-recent"
                    showArrow: true
                    highlighted: cl.flyKind === "recents"
                    onClicked: cl.openFly("recents", recRow)
                    onHoveredChanged: if (hovered) cl.hoverMain("recents", recRow)
                }
                Win7Item {
                    id: setRow
                    width: rowsCol.width
                    iconSize: Kirigami.Units.iconSizes.medium
                    text: i18n("Settings")
                    iconSource: "preferences-system"
                    showArrow: true
                    highlighted: cl.flyKind === "settings"
                    onClicked: cl.openFly("settings", setRow)
                    onHoveredChanged: if (hovered) cl.hoverMain("settings", setRow)
                }
                Win7Item {
                    id: searchRow
                    width: rowsCol.width
                    iconSize: Kirigami.Units.iconSizes.medium
                    text: i18n("Search")
                    iconSource: "edit-find"
                    showArrow: true
                    highlighted: cl.flyKind === "search"
                    onClicked: cl.openFly("search", searchRow)
                    onHoveredChanged: if (hovered) cl.hoverMain("search", searchRow)
                }
                Win7Item {
                    width: rowsCol.width
                    iconSize: Kirigami.Units.iconSizes.medium
                    text: i18n("Help")
                    iconSource: "help-browser"
                    onClicked: cl.doAction("help")
                    onHoveredChanged: if (hovered) cl.hoverMain("", null)
                }
                Win7Item {
                    width: rowsCol.width
                    iconSize: Kirigami.Units.iconSizes.medium
                    text: i18n("Terminal")
                    iconSource: "utilities-terminal"
                    onClicked: cl.doAction("terminal")
                    onHoveredChanged: if (hovered) cl.hoverMain("", null)
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            Layout.topMargin: cl.pad
            Layout.bottomMargin: cl.pad
            Layout.leftMargin: cl.pad
            Layout.rightMargin: cl.pad
            color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.25)
        }

        Win7Item {
            visible: m.gamingModeAvailable
            Layout.fillWidth: true
            iconSize: Kirigami.Units.iconSizes.medium
            text: i18n("Return to gaming mode")
            iconSource: "input-gamepad"
            onClicked: m.returnToGamingMode()
            onHoveredChanged: if (hovered) cl.hoverMain("", null)
        }
        Win7Item {
            Layout.fillWidth: true
            iconSize: Kirigami.Units.iconSizes.medium
            text: i18n("Log out")
            iconSource: "system-log-out"
            onClicked: cl.doAction("logoff")
            onHoveredChanged: if (hovered) cl.hoverMain("", null)
        }
        Win7Item {
            Layout.fillWidth: true
            iconSize: Kirigami.Units.iconSizes.medium
            text: i18n("Shut down")
            iconSource: "system-shutdown"
            onClicked: cl.doAction("shutdown")
            onHoveredChanged: if (hovered) cl.hoverMain("", null)
        }
    }

    Connections {
        target: cl.m
        function onSearchBoxTextChanged() {
            if (sfield.text !== cl.m.searchBoxText) sfield.text = cl.m.searchBoxText
        }
    }

    // ---------------------------------------------------------------- flyouts
    FlyoutPanel {
        id: fly1
        visible: cl.flyKind !== "" && cl.flyKind !== "search"
        m: cl.m
        x: cl.colX + cl.colW
        width: cl.flyW
        items: cl.flyItems
        recents: cl.flyKind === "recents"
        anchorY: cl.flyY
        onActivated: (item, index, row) => {
            if (item && item.type === "sub") cl.openSub(item, row)
            else cl.activateItem(item, index)
        }
        onRowHovered: (item, row) => {
            cl.subPendingItem = item
            cl.subPendingRow = row
            subTimer.restart()
        }
        onContextRequested: (item, app, row, mx, my) => {
            if (item && item.type === "sub") cl.m.openFolderContext(item.entry, row, mx, my)
            else if (app) cl.m.openContext(app, row, mx, my)
        }
    }

    FlyoutPanel {
        id: fly2
        visible: cl.subItems.length > 0
        m: cl.m
        x: fly1.x + cl.flyW
        width: cl.flyW
        items: cl.subItems
        anchorY: cl.subY
        onActivated: (item, index, row) => cl.activateItem(item, index)
        onContextRequested: (item, app, row, mx, my) => {
            if (item && item.type === "entry") cl.m.openItemContext(item.parent, item.entry, row, mx, my)
            else if (app) cl.m.openContext(app, row, mx, my)
        }
    }

    // Search flyout: a search box with the results underneath
    Rectangle {
        id: searchPanel
        visible: cl.flyKind === "search"
        x: cl.colX + cl.colW
        width: cl.flyW
        height: Math.min(cl.u * 20, cl.height)
        y: Math.max(0, Math.min(cl.flyY, cl.height - height))
        z: 5
        radius: 3
        Kirigami.Theme.colorSet: Kirigami.Theme.View
        Kirigami.Theme.inherit: false
        color: Kirigami.Theme.backgroundColor
        border.width: 1
        border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.3)
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 3
            spacing: Kirigami.Units.smallSpacing

            PlasmaComponents.TextField {
                id: sfield
                Layout.fillWidth: true
                placeholderText: i18n("Search programs and files")
                clearButtonShown: true
                onTextChanged: if (m.searchBoxText !== text) m.searchBoxText = text
                Keys.onUpPressed: event => { m.navMove(-1); event.accepted = true }
                Keys.onDownPressed: event => { m.navMove(1); event.accepted = true }
                Keys.onReturnPressed: event => { m.navActivate(); event.accepted = true }
                Keys.onEnterPressed: event => { m.navActivate(); event.accepted = true }
                Keys.onEscapePressed: event => {
                    if (text.length > 0) text = ""
                    else cl.closeFly()
                }
            }

            ListView {
                id: results
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: m.searchResults
                QQC2.ScrollBar.vertical: QQC2.ScrollBar {}
                readonly property real barPad: contentHeight > height ? Kirigami.Units.gridUnit : 0
                delegate: Item {
                    id: resCell
                    readonly property var r: modelData
                    width: ListView.view.width - results.barPad
                    height: r.type === "header" ? hdr.implicitHeight + Kirigami.Units.smallSpacing * 2 : resRow.implicitHeight

                    PlasmaComponents.Label {
                        id: hdr
                        visible: resCell.r.type === "header"
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: Kirigami.Units.smallSpacing
                        anchors.verticalCenter: parent.verticalCenter
                        font.bold: true
                        opacity: 0.7
                        text: resCell.r.text || ""
                    }
                    Win7Item {
                        id: resRow
                        visible: resCell.r.type !== "header"
                        anchors.left: parent.left
                        anchors.right: parent.right
                        iconSize: Kirigami.Units.iconSizes.smallMedium
                        text: resCell.r.type === "app" ? resCell.r.app.name : (resCell.r.type === "file" ? resCell.r.file.name : "")
                        iconSource: resCell.r.type === "app" ? resCell.r.app.icon : "text-x-generic"
                        highlighted: m.navKey === "s:" + resCell.r.nav
                        onClicked: m.activateResult(resCell.r)
                        onRightClicked: (mx, my) => { if (resCell.r.type === "app") m.openContext(resCell.r.app, resRow, mx, my) }
                    }
                }
            }
        }
    }
}

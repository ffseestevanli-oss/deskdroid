import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Dialogs
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    id: page

    property alias cfg_showRecents: recentsCheck.checked
    property bool cfg_showRecentsDefault: true
    property alias cfg_allowDrag: dragCheck.checked
    property bool cfg_allowDragDefault: true
    property int cfg_recentCount: 10
    property int cfg_recentCountDefault: 10
    property alias cfg_softShutdown: softCheck.checked
    property bool cfg_softShutdownDefault: false
    property alias cfg_searchFiles: searchFilesCheck.checked
    property bool cfg_searchFilesDefault: true
    property alias cfg_showCategories: categoriesCheck.checked
    property bool cfg_showCategoriesDefault: true
    property alias cfg_showPlaceIcons: iconsCheck.checked
    property bool cfg_showPlaceIconsDefault: false
    property string cfg_menuLayout: "win7"
    property string cfg_menuLayoutDefault: "win7"
    property bool cfg_bannerShow: true
    property bool cfg_bannerShowDefault: true
    property string cfg_bannerTextMode: "name"
    property string cfg_bannerTextModeDefault: "name"
    property string cfg_bannerText: ""
    property string cfg_bannerTextDefault: ""
    property string cfg_bannerStyle: "gradient"
    property string cfg_bannerStyleDefault: "gradient"
    property string cfg_bannerColor1: "#000080"
    property string cfg_bannerColor1Default: "#000080"
    property string cfg_bannerColor2: "#1084d0"
    property string cfg_bannerColor2Default: "#1084d0"
    property string cfg_bannerTextColor: "#ffffff"
    property string cfg_bannerTextColorDefault: "#ffffff"
    property int cfg_bannerFontSize: 32
    property int cfg_bannerFontSizeDefault: 32
    property int cfg_bannerSpeed: 8
    property int cfg_bannerSpeedDefault: 8

    property var cfg_pinnedIds: []
    property var cfg_pinnedIdsDefault: []

    readonly property bool classic: cfg_menuLayout === "classic"
    readonly property bool animated: cfg_bannerStyle === "rgbfade" || cfg_bannerStyle === "wave"
    readonly property bool twoColors: cfg_bannerStyle === "gradient"
    readonly property bool oneColor: cfg_bannerStyle === "solid"

    ColorDialog {
        id: colorPicker
        property string key: ""
        title: i18n("Choose a color")
        onAccepted: page["cfg_" + key] = selectedColor.toString()
    }
    function pick(key) {
        colorPicker.key = key
        colorPicker.selectedColor = page["cfg_" + key]
        colorPicker.open()
    }

    Kirigami.FormLayout {
        ValueCombo {
            Kirigami.FormData.label: i18n("Menu layout:")
            options: [
                { text: i18n("Windows 7 (two panes)"), value: "win7" },
                { text: i18n("One pane (Windows 9x / Classic, experimental)"), value: "classic" }
            ]
            current: page.cfg_menuLayout
            onPicked: v => page.cfg_menuLayout = v
        }
        QQC2.Label {
            Layout.maximumWidth: Kirigami.Units.gridUnit * 22
            wrapMode: Text.WordWrap
            opacity: 0.7
            text: i18n("One pane puts your pinned programs on top, then Programs, Recents, Settings and Search as flyouts, then Help, Terminal, Log out and Shut down, with an optional banner down the side. Reopen the menu after changing this.")
        }

        QQC2.CheckBox {
            visible: page.classic
            Kirigami.FormData.label: i18n("Banner:")
            text: i18n("Show the banner")
            checked: page.cfg_bannerShow
            onToggled: page.cfg_bannerShow = checked
        }

        ValueCombo {
            visible: page.classic
            Kirigami.FormData.label: i18n("Text:")
            options: [
                { text: i18n("Distro name"), value: "name" },
                { text: i18n("Distro name and version"), value: "pretty" },
                { text: i18n("Custom text"), value: "custom" }
            ]
            current: page.cfg_bannerTextMode
            onPicked: v => page.cfg_bannerTextMode = v
        }
        QQC2.TextField {
                        Kirigami.FormData.label: i18n("Custom text:")
            visible: page.classic && (page.cfg_bannerTextMode === "custom")
            text: page.cfg_bannerText
            onTextEdited: page.cfg_bannerText = text
        }
        RowLayout {
            visible: page.classic
            Kirigami.FormData.label: i18n("Text size:")
            QQC2.SpinBox {
                from: 8
                to: 40
                editable: true
                value: page.cfg_bannerFontSize
                onValueModified: page.cfg_bannerFontSize = value
            }
            QQC2.Label { text: i18n("px"); opacity: 0.7 }
        }
        RowLayout {
            visible: page.classic
            Kirigami.FormData.label: i18n("Text color:")
            Rectangle {
                implicitWidth: Kirigami.Units.gridUnit * 2
                implicitHeight: Kirigami.Units.gridUnit * 1.2
                radius: 3
                color: page.cfg_bannerTextColor
                border.width: 1
                border.color: Kirigami.Theme.disabledTextColor
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: page.pick("bannerTextColor") }
            }
            QQC2.Button { text: i18n("Choose…"); onClicked: page.pick("bannerTextColor") }
        }

        Item { Kirigami.FormData.isSection: true; visible: page.classic }

        ValueCombo {
            visible: page.classic
            Kirigami.FormData.label: i18n("Style:")
            options: [
                { text: i18n("Gradient (two colors)"), value: "gradient" },
                { text: i18n("Single color"), value: "solid" },
                { text: i18n("Rainbow"), value: "rainbow" },
                { text: i18n("RGB fade"), value: "rgbfade" },
                { text: i18n("Rainbow wave"), value: "wave" }
            ]
            current: page.cfg_bannerStyle
            onPicked: v => page.cfg_bannerStyle = v
        }
        RowLayout {
                        Kirigami.FormData.label: page.twoColors ? i18n("Top color:") : i18n("Color:")
            visible: page.classic && (page.twoColors || page.oneColor)
            Rectangle {
                implicitWidth: Kirigami.Units.gridUnit * 2
                implicitHeight: Kirigami.Units.gridUnit * 1.2
                radius: 3
                color: page.cfg_bannerColor1
                border.width: 1
                border.color: Kirigami.Theme.disabledTextColor
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: page.pick("bannerColor1") }
            }
            QQC2.Button { text: i18n("Choose…"); onClicked: page.pick("bannerColor1") }
        }
        RowLayout {
                        Kirigami.FormData.label: i18n("Bottom color:")
            visible: page.classic && (page.twoColors)
            Rectangle {
                implicitWidth: Kirigami.Units.gridUnit * 2
                implicitHeight: Kirigami.Units.gridUnit * 1.2
                radius: 3
                color: page.cfg_bannerColor2
                border.width: 1
                border.color: Kirigami.Theme.disabledTextColor
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: page.pick("bannerColor2") }
            }
            QQC2.Button { text: i18n("Choose…"); onClicked: page.pick("bannerColor2") }
        }
        SpeedRow {
            Kirigami.FormData.label: i18n("Speed:")
            visible: page.classic && page.animated
            seconds: page.cfg_bannerSpeed
            onSpeedPicked: s => page.cfg_bannerSpeed = s
        }



        Item { Kirigami.FormData.isSection: true }

        QQC2.CheckBox {
            id: recentsCheck
            Kirigami.FormData.label: i18n("Left pane:")
            text: i18n("Show recent programs")
        }
        RowLayout {
            Kirigami.FormData.label: i18n("Recent programs to keep:")
            enabled: recentsCheck.checked
            QQC2.SpinBox {
                from: 1
                to: 50
                editable: true
                value: page.cfg_recentCount
                onValueModified: page.cfg_recentCount = value
            }
            QQC2.Label {
                opacity: 0.7
                text: i18n("A scrollbar appears when they don't all fit.")
            }
        }

        QQC2.CheckBox {
            id: dragCheck
            Kirigami.FormData.label: i18n("Dragging:")
            text: i18n("Allow dragging pinned and recent programs out of the menu (to panels or the desktop)")
        }

        QQC2.CheckBox {
            id: softCheck
            Kirigami.FormData.label: i18n("Power:")
            text: i18n("Use Soft Shut Down and Soft Restart")
        }
        QQC2.Label {
            Layout.maximumWidth: Kirigami.Units.gridUnit * 22
            wrapMode: Text.WordWrap
            opacity: 0.7
            text: i18n("Enable this if you want to use a gentle shut down. Otherwise, Leave disabled for a faster experience.")
        }

        Item { Kirigami.FormData.isSection: true }

        QQC2.CheckBox {
            id: searchFilesCheck
            Kirigami.FormData.label: i18n("Search:")
            text: i18n("Also search files and folders in my home folder")
        }

        QQC2.CheckBox {
            id: categoriesCheck
            Kirigami.FormData.label: i18n("All Programs:")
            text: i18n("Show the built-in categories")
        }
        QQC2.Label {
            Layout.maximumWidth: Kirigami.Units.gridUnit * 22
            wrapMode: Text.WordWrap
            opacity: 0.7
            text: i18n("Turn this off to show only your own folders in All Programs. Create folders with “New Folder…” at the bottom of All Programs, or by right-clicking a folder.")
        }

        QQC2.CheckBox {
            id: iconsCheck
            Kirigami.FormData.label: i18n("Right pane:")
            text: i18n("Show icons next to places")
        }

        Item { Kirigami.FormData.isSection: true }

        RowLayout {
            Kirigami.FormData.label: i18n("Pinned programs:")
            QQC2.Label {
                text: i18n("%1 of 8 pinned", page.cfg_pinnedIds ? page.cfg_pinnedIds.length : 0)
            }
            QQC2.Button {
                text: i18n("Unpin all")
                icon.name: "edit-clear-all"
                enabled: page.cfg_pinnedIds && page.cfg_pinnedIds.length > 0
                onClicked: page.cfg_pinnedIds = []
            }
        }

        QQC2.Label {
            Layout.maximumWidth: Kirigami.Units.gridUnit * 20
            wrapMode: Text.WordWrap
            opacity: 0.7
            text: i18n("To pin a program, right-click it in the start menu and choose “Pin to Start”.")
        }
    }
}

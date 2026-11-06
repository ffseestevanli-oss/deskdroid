import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Dialogs
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.plasma.plasmoid

KCM.SimpleKCM {
    id: page

    property alias cfg_roundCorners: roundCheck.checked
    property bool cfg_roundCornersDefault: false
    property int cfg_cornerRadius: 8
    property int cfg_cornerRadiusDefault: 8
    property bool cfg_radiusUnlocked: false
    property bool cfg_radiusUnlockedDefault: false
    property string cfg_accentStyle: "system"
    property string cfg_accentStyleDefault: "system"
    property string cfg_accentColor1: "#3daee9"
    property string cfg_accentColor1Default: "#3daee9"
    property string cfg_accentColor2: "#9b59b6"
    property string cfg_accentColor2Default: "#9b59b6"
    property string cfg_accentArea: "outer"
    property string cfg_accentAreaDefault: "outer"
    property int cfg_accentFill: 70
    property int cfg_accentFillDefault: 70
    property int cfg_accentWidth: 2
    property int cfg_accentWidthDefault: 2
    property int cfg_accentSpeed: 8
    property int cfg_accentSpeedDefault: 8

    readonly property int lockedMax: 16
    readonly property bool animated: cfg_accentStyle === "rgbfade" || cfg_accentStyle === "flow"
    readonly property bool oneColor: cfg_accentStyle === "custom"
    readonly property bool twoColors: cfg_accentStyle === "gradient"

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

    Plasma5Support.DataSource {
        id: exec
        engine: "executable"
        connectedSources: []
    }

    readonly property string restartCmd: "systemctl --user restart plasma-plasmashell || (kquitapp6 plasmashell; sleep 1; kstart plasmashell)"

    // Put every setting of this widget back to its default (pins, folders, picture, orb, places...)
    function wipeAllSettings() {
        var cfg = Plasmoid.configuration
        var keys = cfg.keys()
        for (var i = 0; i < keys.length; ++i) {
            var k = keys[i]
            if (/Default$/.test(k)) continue
            var d = cfg[k + "Default"]
            if (d !== undefined) cfg[k] = d
        }
        // restart the shell so every page and the menu reload from the clean state
        exec.connectSource("sleep 1; " + page.restartCmd)
    }

    Kirigami.PromptDialog {
        id: wipeDialog
        title: i18n("Complete reset")
        subtitle: i18n("This wipes every setting of this widget (pinned programs, folders, places, orb or button, profile picture and all other options) and starts fresh, as if it were just installed. Plasma Shell will restart. This cannot be undone.")
        standardButtons: Kirigami.Dialog.Cancel
        customFooterActions: [
            Kirigami.Action {
                text: i18n("Reset everything")
                icon.name: "edit-delete"
                onTriggered: {
                    wipeDialog.close()
                    page.wipeAllSettings()
                }
            }
        ]
    }

    Kirigami.FormLayout {
        // ------------------------------------------------ Accent border
        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Accent border")
        }

        QQC2.CheckBox {
            id: roundCheck
            Kirigami.FormData.label: i18n("Accent border:")
            text: i18n("Show an accent border around the menu")
        }
        QQC2.Label {
            Layout.maximumWidth: Kirigami.Units.gridUnit * 22
            wrapMode: Text.WordWrap
            opacity: 0.7
            text: i18n("Adds a colored border for extra style and rounds the corners away from the panel. Panel on top rounds the bottom corners, panel on the bottom rounds the top corners, and a panel on a side rounds the opposite side.")
        }

        ValueCombo {
            Kirigami.FormData.label: i18n("Color style:")
            enabled: roundCheck.checked
            options: [
                { text: i18n("System accent"), value: "system" },
                { text: i18n("Custom"), value: "custom" },
                { text: i18n("Custom gradient"), value: "gradient" },
                { text: i18n("Rainbow"), value: "rainbow" },
                { text: i18n("RGB fade"), value: "rgbfade" },
                { text: i18n("Rainbow flow"), value: "flow" }
            ]
            current: page.cfg_accentStyle
            onPicked: v => page.cfg_accentStyle = v
        }
        RowLayout {
            Kirigami.FormData.label: page.twoColors ? i18n("Start color:") : i18n("Color:")
            visible: page.oneColor || page.twoColors
            enabled: roundCheck.checked
            Rectangle {
                implicitWidth: Kirigami.Units.gridUnit * 2
                implicitHeight: Kirigami.Units.gridUnit * 1.2
                radius: 3
                color: page.cfg_accentColor1
                border.width: 1
                border.color: Kirigami.Theme.disabledTextColor
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: page.pick("accentColor1") }
            }
            QQC2.Button { text: i18n("Choose…"); onClicked: page.pick("accentColor1") }
        }
        RowLayout {
            Kirigami.FormData.label: i18n("End color:")
            visible: page.twoColors
            enabled: roundCheck.checked
            Rectangle {
                implicitWidth: Kirigami.Units.gridUnit * 2
                implicitHeight: Kirigami.Units.gridUnit * 1.2
                radius: 3
                color: page.cfg_accentColor2
                border.width: 1
                border.color: Kirigami.Theme.disabledTextColor
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: page.pick("accentColor2") }
            }
            QQC2.Button { text: i18n("Choose…"); onClicked: page.pick("accentColor2") }
        }
        ValueCombo {
            Kirigami.FormData.label: i18n("Color area:")
            enabled: roundCheck.checked
            options: [
                { text: i18n("Outer border only"), value: "outer" },
                { text: i18n("Right pane and left pane border"), value: "panes" },
                { text: i18n("Whole menu"), value: "menu" }
            ]
            current: page.cfg_accentArea
            onPicked: v => page.cfg_accentArea = v
        }
        QQC2.Label {
            Layout.maximumWidth: Kirigami.Units.gridUnit * 22
            wrapMode: Text.WordWrap
            opacity: 0.7
            text: page.cfg_accentArea === "outer"
                  ? i18n("Only the ring around the edge of the menu is colored.")
                  : (page.cfg_accentArea === "panes"
                     ? i18n("The right pane is filled with the color and the left pane keeps its normal gray outline, with no outer ring for a unified look. In the One pane layout the whole menu is filled.")
                     : i18n("The whole menu, including the left pane, is tinted with the color, with no outer ring."))
        }
        RowLayout {
            Kirigami.FormData.label: i18n("Intensity:")
            visible: page.cfg_accentArea !== "outer"
            enabled: roundCheck.checked
            QQC2.Slider {
                from: 5
                to: 100
                stepSize: 1
                snapMode: QQC2.Slider.SnapAlways
                value: page.cfg_accentFill
                onMoved: page.cfg_accentFill = Math.round(value)
            }
            QQC2.Label { text: i18n("%1%", page.cfg_accentFill); opacity: 0.7 }
        }
        RowLayout {
            Kirigami.FormData.label: i18n("Thickness:")
            visible: page.cfg_accentArea === "outer"
            enabled: roundCheck.checked
            QQC2.SpinBox {
                from: 1
                to: 8
                editable: true
                value: page.cfg_accentWidth
                onValueModified: page.cfg_accentWidth = value
            }
            QQC2.Label { text: i18n("px"); opacity: 0.7 }
        }
        SpeedRow {
            Kirigami.FormData.label: i18n("Speed:")
            visible: page.animated
            enabled: roundCheck.checked
            seconds: page.cfg_accentSpeed
            onSpeedPicked: s => page.cfg_accentSpeed = s
        }
        QQC2.Slider {
            Kirigami.FormData.label: i18n("Radius:")
            visible: !page.cfg_radiusUnlocked
            enabled: roundCheck.checked
            from: 0
            to: page.lockedMax
            stepSize: 1
            snapMode: QQC2.Slider.SnapAlways
            value: page.cfg_cornerRadius
            onMoved: page.cfg_cornerRadius = Math.round(value)
        }
        QQC2.SpinBox {
            Kirigami.FormData.label: page.cfg_radiusUnlocked ? i18n("Radius:") : ""
            enabled: roundCheck.checked
            editable: true
            from: 0
            to: page.cfg_radiusUnlocked ? 100000 : page.lockedMax
            value: page.cfg_cornerRadius
            textFromValue: function (v) { return i18n("%1 px", v) }
            valueFromText: function (t) { return parseInt(t) || 0 }
            onValueModified: page.cfg_cornerRadius = value
        }
        QQC2.Button {
            Kirigami.FormData.label: i18n("Radius limit:")
            icon.name: page.cfg_radiusUnlocked ? "object-locked" : "object-unlocked"
            text: page.cfg_radiusUnlocked ? i18n("Lock the limit (16 px)") : i18n("Unlock")
            onClicked: {
                if (page.cfg_radiusUnlocked) page.cfg_cornerRadius = Math.min(page.lockedMax, page.cfg_cornerRadius)
                page.cfg_radiusUnlocked = !page.cfg_radiusUnlocked
            }
        }
        Kirigami.InlineMessage {
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            visible: true
            type: Kirigami.MessageType.Warning
            text: i18n("Warning: These features may break the menu, They're here for fun, proceed with caution!")
        }

        // ------------------------------------------------ Maintenance
        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Maintenance")
        }
        QQC2.Button {
            Kirigami.FormData.label: i18n("Plasma Shell:")
            text: i18n("Restart Plasma Shell")
            icon.name: "system-reboot"
            onClicked: exec.connectSource(page.restartCmd)
        }
        QQC2.Label {
            Layout.maximumWidth: Kirigami.Units.gridUnit * 22
            wrapMode: Text.WordWrap
            opacity: 0.7
            text: i18n("While you may not need this right now, you'll never know")
        }
        QQC2.Label {
            Layout.maximumWidth: Kirigami.Units.gridUnit * 22
            wrapMode: Text.WordWrap
            opacity: 0.7
            text: i18n("Your panels and widgets will disappear for a few seconds while the shell restarts.")
        }

        QQC2.Button {
            Kirigami.FormData.label: i18n("Complete reset:")
            text: i18n("Reset everything…")
            icon.name: "edit-delete"
            onClicked: wipeDialog.open()
        }
        QQC2.Label {
            Layout.maximumWidth: Kirigami.Units.gridUnit * 22
            wrapMode: Text.WordWrap
            opacity: 0.7
            text: i18n("A complete wipe and fresh start, as if the widget were newly installed. Everything you customized is lost.")
        }
    }
}

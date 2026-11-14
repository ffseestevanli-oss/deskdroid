// The phone's battery: in the system tray (its icon, with the percentage and
// charging state in a popup), or on its own on a panel (icon and percentage).
// The popup also picks the desktop's power profile (Power Save, Balanced,
// Performance; PowerProfile.kt), like Plasma's own battery item.
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.private.kicker as Kicker
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    Status { id: status }
    Kicker.ProcessRunner { id: runner }

    readonly property int percent: status.valid ? status.data.battery : -1
    readonly property bool charging: status.valid && status.data.charging
    readonly property bool low: percent >= 0 && percent <= 15 && !charging
    // Breeze's battery icons come in steps of ten.
    readonly property string iconName: percent < 0 ? "battery-missing"
        : "battery-" + String(Math.round(percent / 10) * 10).padStart(3, "0") + (charging ? "-charging" : "")
    readonly property string stateText: !status.valid ? "" : charging
        ? (status.data.chargeMinutes > 0 ? "Charging, full in " + Math.floor(status.data.chargeMinutes / 60) + " h " + (status.data.chargeMinutes % 60) + " min" : "Charging")
        : (status.data.plugged ? "Plugged in" : "On battery")
    // The power profile DeskDroid applies, and the one picked here (shown at
    // once, before status.json catches up).
    property string picked: ""
    readonly property string profile: picked !== "" ? picked : (status.valid && status.data.profileChosen ? status.data.profileChosen : "balanced")
    readonly property bool bySaver: status.valid && status.data.profileBySaver === true
    readonly property var profiles: [
        { name: "powersave", label: "Power Save", icon: "power-profile-power-saver-symbolic" },
        { name: "balanced", label: "Balanced", icon: "power-profile-balanced-symbolic" },
        { name: "performance", label: "Performance", icon: "power-profile-performance-symbolic" }
    ]
    function profileLabel(n) {
        for (var i = 0; i < profiles.length; i++) if (profiles[i].name === n) return profiles[i].label;
        return "Balanced";
    }
    function pick(n) {
        picked = n;
        pickedReset.restart();
        runner.runCommand("android-open deskdroid:power:" + n);
    }
    Timer { id: pickedReset; interval: 5000; onTriggered: root.picked = "" }
    // The system tray draws its items as squares with a heading on their popups.
    readonly property bool inTray: (Plasmoid.containmentDisplayHints & PlasmaCore.Types.ContainmentDrawsPlasmoidHeading) !== 0

    Plasmoid.icon: iconName
    Plasmoid.status: low ? PlasmaCore.Types.NeedsAttentionStatus : PlasmaCore.Types.ActiveStatus
    preferredRepresentation: inTray ? compactRepresentation : fullRepresentation
    toolTipMainText: percent < 0 ? "Battery" : "Battery " + percent + "%"
    toolTipSubText: stateText + (status.valid ? (stateText ? "\n" : "") + "Power profile: " + profileLabel(bySaver ? "powersave" : profile) + (bySaver ? " (Battery Saver)" : "") : "")

    compactRepresentation: MouseArea {
        hoverEnabled: true
        onClicked: root.expanded = !root.expanded
        Kirigami.Icon {
            anchors.fill: parent
            source: root.iconName
            active: parent.containsMouse
        }
    }

    fullRepresentation: Loader {
        sourceComponent: root.inTray ? details : row
        Layout.minimumWidth: item ? item.Layout.minimumWidth : 0
        Layout.minimumHeight: item ? item.Layout.minimumHeight : 0
        Layout.preferredWidth: item ? item.Layout.preferredWidth : 0
        Layout.preferredHeight: item ? item.Layout.preferredHeight : 0
    }

    // On a panel: the icon and the percentage.
    Component {
        id: row
        RowLayout {
            spacing: Kirigami.Units.smallSpacing
            Layout.minimumWidth: implicitWidth
            Layout.preferredWidth: implicitWidth
            Kirigami.Icon {
                source: root.iconName
                Layout.preferredWidth: Math.min(parent.height, Kirigami.Units.iconSizes.medium)
                Layout.preferredHeight: Layout.preferredWidth
                Layout.alignment: Qt.AlignVCenter
            }
            Text {
                visible: root.percent >= 0
                text: root.percent + "%"
                color: root.low ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
                font.pixelSize: Math.max(11, parent.height * 0.4)
                Layout.alignment: Qt.AlignVCenter
            }
        }
    }

    // The tray's popup: the percentage, a bar, charging state, and the phone's settings.
    Component {
        id: details
        ColumnLayout {
            spacing: Kirigami.Units.largeSpacing
            Layout.minimumWidth: Kirigami.Units.gridUnit * 16
            Layout.preferredWidth: Kirigami.Units.gridUnit * 18
            Layout.minimumHeight: implicitHeight
            Layout.preferredHeight: implicitHeight
            RowLayout {
                spacing: Kirigami.Units.largeSpacing
                Layout.margins: Kirigami.Units.largeSpacing
                Kirigami.Icon {
                    source: root.iconName
                    Layout.preferredWidth: Kirigami.Units.iconSizes.large
                    Layout.preferredHeight: Kirigami.Units.iconSizes.large
                }
                ColumnLayout {
                    spacing: 0
                    Layout.fillWidth: true
                    Kirigami.Heading {
                        level: 2
                        text: root.percent < 0 ? "No battery information" : root.percent + "%"
                        color: root.low ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
                    }
                    PlasmaComponents3.Label {
                        text: root.stateText
                        opacity: 0.75
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                    }
                }
            }
            PlasmaComponents3.ProgressBar {
                visible: root.percent >= 0
                from: 0; to: 100
                value: Math.max(0, root.percent)
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.largeSpacing
                Layout.rightMargin: Kirigami.Units.largeSpacing
            }
            // Power profile: how hard DeskDroid's desktop and apps may work.
            ColumnLayout {
                spacing: Kirigami.Units.smallSpacing
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.largeSpacing
                Layout.rightMargin: Kirigami.Units.largeSpacing
                PlasmaComponents3.Label {
                    text: "Power Profile"
                    font.bold: true
                }
                RowLayout {
                    spacing: Kirigami.Units.smallSpacing
                    Layout.fillWidth: true
                    Repeater {
                        model: root.profiles
                        PlasmaComponents3.ToolButton {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            display: PlasmaComponents3.AbstractButton.TextUnderIcon
                            icon.name: modelData.icon
                            text: modelData.label
                            checkable: true
                            checked: root.profile === modelData.name
                            onClicked: root.pick(modelData.name)
                        }
                    }
                }
                PlasmaComponents3.Label {
                    text: root.bySaver ? "The phone's Battery Saver is on: Power Save until it's off."
                        : root.profile === "powersave" ? "Slower: efficient cores, busy apps limited, animations off. Longest battery life."
                        : root.profile === "performance" ? "Every core, the screen's full frame rate, no limits. Uses the most battery."
                        : "Leaves the fastest cores alone and draws at up to 60 frames a second."
                    opacity: 0.75
                    font: Kirigami.Theme.smallFont
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }
            }
            PlasmaComponents3.Button {
                text: "Phone's Battery Settings…"
                icon.name: "configure"
                Layout.alignment: Qt.AlignRight
                Layout.margins: Kirigami.Units.largeSpacing
                onClicked: { runner.runCommand("android-open deskdroid:settings:battery"); root.expanded = false }
            }
        }
    }
}

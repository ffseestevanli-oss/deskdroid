// The phone's battery in the panel: its icon and percentage, charging or not.
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    Status { id: status }

    readonly property int percent: status.valid ? status.data.battery : -1
    readonly property bool charging: status.valid && status.data.charging
    // Breeze's battery icons come in steps of ten.
    readonly property string iconName: percent < 0 ? "battery-missing"
        : "battery-" + String(Math.round(percent / 10) * 10).padStart(3, "0") + (charging ? "-charging" : "")

    preferredRepresentation: fullRepresentation
    toolTipMainText: percent < 0 ? "Battery" : "Battery " + percent + "%"
    toolTipSubText: !status.valid ? "" : charging
        ? (status.data.chargeMinutes > 0 ? "Charging, full in " + Math.floor(status.data.chargeMinutes / 60) + " h " + (status.data.chargeMinutes % 60) + " min" : "Charging")
        : (status.data.plugged ? "Plugged in" : "On battery")

    fullRepresentation: RowLayout {
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
            color: root.percent >= 0 && root.percent <= 15 && !root.charging ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
            font.pixelSize: Math.max(11, parent.height * 0.4)
            Layout.alignment: Qt.AlignVCenter
        }
    }
}

// The phone's memory in use (all apps, not only the desktop's).
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid

PlasmoidItem {
    id: root
    Status { id: status }
    readonly property real used: status.valid ? status.data.ramTotal - status.data.ramAvailable : 0
    function gb(b) { return (b / 1073741824).toFixed(1) + " GB" }
    preferredRepresentation: fullRepresentation
    toolTipMainText: "RAM"
    toolTipSubText: status.valid ? gb(used) + " of " + gb(status.data.ramTotal) + " in use" : ""
    fullRepresentation: Meter {
        label: "RAM"
        value: status.valid && status.data.ramTotal > 0 ? 100 * root.used / status.data.ramTotal : -1
        accent: "#3DFF8B"
    }
}

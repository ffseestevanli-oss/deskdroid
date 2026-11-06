// The desktop's processor use (Android shows an app only its own processes):
// all of DeskDroid's programs together, as a share of all the phone's cores.
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid

PlasmoidItem {
    id: root
    Status { id: status }
    preferredRepresentation: fullRepresentation
    toolTipMainText: "CPU"
    toolTipSubText: status.valid ? "The desktop's apps use " + status.data.cpu.toFixed(1) + "% of the phone's " + status.data.cores + " cores" : ""
    fullRepresentation: Meter {
        label: "CPU"
        value: status.valid ? status.data.cpu : -1
    }
}

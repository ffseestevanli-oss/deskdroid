// An applet shown small (an icon, say): tapping it shows the full applet above.
import QtQuick
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid

PlasmaCore.ToolTipArea {
    id: root

    property Item fullRepresentation
    property Item compactRepresentation
    property PlasmoidItem plasmoidItem

    onCompactRepresentationChanged: {
        if (compactRepresentation) {
            compactRepresentation.parent = root;
            compactRepresentation.anchors.fill = root;
            compactRepresentation.visible = true;
        }
    }

    onFullRepresentationChanged: {
        if (fullRepresentation) {
            fullRepresentation.parent = popupContent;
            fullRepresentation.anchors.fill = popupContent;
        }
    }

    PlasmaCore.Dialog {
        id: popup
        visualParent: root
        location: PlasmaCore.Types.Floating
        visible: root.plasmoidItem ? root.plasmoidItem.expanded : false
        onVisibleChanged: if (!visible && root.plasmoidItem) root.plasmoidItem.expanded = false
        mainItem: Item {
            id: popupContent
            width: root.fullRepresentation ? Math.max(root.fullRepresentation.implicitWidth, 200) : 200
            height: root.fullRepresentation ? Math.max(root.fullRepresentation.implicitHeight, 200) : 200
        }
    }
}

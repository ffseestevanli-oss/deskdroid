// A panel view: the theme's panel background, with the panel containment on it.
import QtQuick
import org.kde.ksvg as KSvg
import org.kde.plasma.core as PlasmaCore

Item {
    id: root

    property Item containment

    KSvg.FrameSvgItem {
        id: background
        anchors.fill: parent
        imagePath: "widgets/panel-background"
        enabledBorders: KSvg.FrameSvg.TopBorder
    }

    Item {
        id: containmentParent
        anchors.fill: parent
        anchors.topMargin: background.margins.top
    }

    onContainmentChanged: {
        if (!containment) {
            return;
        }
        containment.parent = containmentParent;
        containment.visible = true;
        containment.anchors.fill = containmentParent;
    }
}

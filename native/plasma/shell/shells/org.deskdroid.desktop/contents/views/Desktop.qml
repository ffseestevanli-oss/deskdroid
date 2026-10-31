// The desktop view: the desktop containment (with its wallpaper) fills it.
import QtQuick

Item {
    id: root

    property Item containment

    onContainmentChanged: {
        if (!containment) {
            return;
        }
        containment.parent = root;
        containment.visible = true;
        containment.anchors.fill = root;
    }
}

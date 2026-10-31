// A panel: its applets in a row, from the left, each as wide as it asks.
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid

ContainmentItem {
    id: root

    function addApplet(applet) {
        const item = root.itemFor(applet);
        if (!item) {
            return;
        }
        for (let i = 0; i < applets.count; i++) {
            if (applets.get(i).applet === item) {
                return;
            }
        }
        applets.append({applet: item});
    }

    Containment.onAppletAdded: (applet, geometry) => addApplet(applet)
    Containment.onAppletRemoved: applet => {
        const item = root.itemFor(applet);
        for (let i = 0; i < applets.count; i++) {
            if (applets.get(i).applet === item) {
                applets.remove(i);
                return;
            }
        }
    }
    Component.onCompleted: Plasmoid.applets.forEach(addApplet)

    ListModel {
        id: applets
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        spacing: 8

        Repeater {
            model: applets
            delegate: Item {
                id: slot
                required property Item applet
                Layout.fillHeight: true
                Layout.preferredWidth: applet ? Math.max(applet.implicitWidth, height) : 0
                Component.onCompleted: {
                    if (applet) {
                        applet.parent = slot;
                        applet.anchors.fill = slot;
                        applet.visible = true;
                    }
                }
            }
        }

        Item {
            Layout.fillWidth: true
        }
    }
}

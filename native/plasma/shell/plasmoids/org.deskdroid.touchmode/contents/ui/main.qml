// The touch mode in the system tray: a mouse pointer while the phone's screen
// is a touchpad, a finger on a touchscreen in Direct touch. A click switches
// (as the three-finger tap and the DD menu do). DeskDroid writes the mode to
// files/touch-mode (Prefs.writeTouchMode). System Settings › Gestures ›
// Edge Swipes can hide it ("mode_indicator" in files/gestures.json).
import QtQuick
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.private.kicker as Kicker
import org.kde.plasma.components as PlasmaComponents3
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    Kicker.ProcessRunner { id: runner }

    property string mode: "touchpad"
    property bool shown: true
    // The files folder, from this package's own path: files/kwin/share/plasma/plasmoids/<id>/contents/ui/.
    readonly property string files: {
        var here = Qt.resolvedUrl(".").toString();
        var i = here.indexOf("/kwin/share/");
        return i < 0 ? "" : here.substring(0, i);
    }
    readonly property bool direct: mode === "direct"
    readonly property url iconUrl: Qt.resolvedUrl("../icons/" + (direct ? "direct" : "touchpad") + ".svg")
    readonly property string label: direct ? "Direct touch" : "Touchpad"

    function read(name, done) {
        if (!files) return;
        var x = new XMLHttpRequest();
        x.onreadystatechange = function () {
            if (x.readyState === XMLHttpRequest.DONE) done(x.responseText || "");
        };
        x.open("GET", files + "/" + name);
        x.send();
    }
    function refresh() {
        read("touch-mode", function (t) {
            t = t.trim();
            if (t === "direct" || t === "touchpad") root.mode = t;
        });
        read("gestures.json", function (t) {
            var on = true;
            try { on = JSON.parse(t).mode_indicator !== false; } catch (e) {}
            root.shown = on;
        });
    }
    function toggle() {
        root.mode = direct ? "touchpad" : "direct"; // shown at once; the file follows
        runner.runCommand("android-open deskdroid:touchmode:toggle");
    }
    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Plasmoid.icon: iconUrl
    Plasmoid.title: "Touch Mode"
    Plasmoid.status: shown ? PlasmaCore.Types.ActiveStatus : PlasmaCore.Types.HiddenStatus
    toolTipMainText: "Touch mode: " + label
    toolTipSubText: direct ? "Your finger works the desktop directly. Click, or tap with three fingers, for Touchpad."
                           : "The screen moves a pointer like a laptop's touchpad. Click, or tap with three fingers, for Direct touch."
    preferredRepresentation: compactRepresentation

    compactRepresentation: MouseArea {
        hoverEnabled: true
        onClicked: root.toggle()
        Kirigami.Icon {
            anchors.fill: parent
            source: root.iconUrl
            isMask: true
            color: Kirigami.Theme.textColor
            active: parent.containsMouse
        }
    }
    // Opened from the tray's hidden items: the two modes, a check by the one in use.
    fullRepresentation: ColumnLayout {
        Layout.minimumWidth: Kirigami.Units.gridUnit * 12
        spacing: Kirigami.Units.smallSpacing
        Repeater {
            model: [{ name: "touchpad", label: "Touchpad" }, { name: "direct", label: "Direct touch" }]
            delegate: PlasmaComponents3.ItemDelegate {
                required property var modelData
                Layout.fillWidth: true
                text: modelData.label
                icon.source: Qt.resolvedUrl("../icons/" + modelData.name + ".svg")
                checkable: true
                checked: root.mode === modelData.name
                onClicked: { if (root.mode !== modelData.name) root.toggle(); root.expanded = false }
            }
        }
    }
}

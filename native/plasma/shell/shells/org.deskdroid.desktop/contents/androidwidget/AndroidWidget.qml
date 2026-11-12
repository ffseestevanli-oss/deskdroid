// An Android widget on the desktop. Each of the phone's widgets is a plasmoid
// of its own (org.deskdroid.android.*, written by AndroidWidgets.kt into
// files/.local/share/plasma/plasmoids), whose main.qml is a PlasmoidItem with
// this as its full representation and the widget's provider filled in.
//
// This file must not use Plasmoid: it lives outside the applet's package, so
// its QML context isn't the applet's and the attached Plasmoid object can't be
// created here ("Could not create attached properties object 'Plasma::Applet'").
// main.qml passes in the token and calls removed() instead.
//
// The phone runs the widget (AppWidgetHost) and draws it at this plasmoid's
// size into files/android-widgets/<token>.png, with its state in
// <token>.json; clicks, swipes and the scroll wheel go back to it through
// android-open (NativeDesk.watchOpenRequests). <token> is this plasmoid's
// own id for its Android widget, kept in its settings.
import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.private.kicker as Kicker
import org.kde.kirigami as Kirigami

Item {
    id: root

    // Filled in by the generated main.qml.
    property string provider        // the widget's provider, package/class
    property int profile: 0         // Android profile (user) serial number
    property string label
    property int defaultWidth: Kirigami.Units.gridUnit * 16
    property int defaultHeight: Kirigami.Units.gridUnit * 8

    // A file:// URL already (from Qt.resolvedUrl), for both the state and the frames.
    readonly property string widgetsDir: {
        var here = Qt.resolvedUrl(".").toString();
        var i = here.indexOf("/kwin/share/");
        return i < 0 ? "" : here.substring(0, i) + "/android-widgets";
    }
    property string token            // main.qml: Plasmoid.configuration.token
    signal tokenMade(string token)   // main.qml saves it in the plasmoid's settings
    property var info: ({})          // <token>.json: state, serial, w, h, msg
    readonly property string widgetState: info.state || ""
    readonly property real dpr: Screen.devicePixelRatio > 0 ? Screen.devicePixelRatio : 1
    readonly property int pxWidth: Math.round(width * dpr)
    readonly property int pxHeight: Math.round(height * dpr)

    Layout.preferredWidth: defaultWidth
    Layout.preferredHeight: defaultHeight
    Layout.minimumWidth: Kirigami.Units.gridUnit * 3
    Layout.minimumHeight: Kirigami.Units.gridUnit * 2

    Kicker.ProcessRunner { id: runner }
    function send(what) { runner.runCommand("android-open deskdroid:widget:" + what) }

    function announce() {
        if (!token || !provider || pxWidth < 8 || pxHeight < 8) return;
        send(["show", token, profile, provider, pxWidth, pxHeight, Math.round(160 * dpr)].join(":"));
    }

    Component.onCompleted: {
        if (!token) root.tokenMade(Date.now().toString(36) + Math.floor(Math.random() * 0x7fffffff).toString(36));
        announceTimer.restart();
    }
    onPxWidthChanged: announceTimer.restart()
    onPxHeightChanged: announceTimer.restart()
    onTokenChanged: announceTimer.restart()

    // Resizing sends one size, once it stops changing.
    Timer {
        id: announceTimer
        interval: 400
        onTriggered: root.announce()
    }

    // Removed from the desktop: the phone lets the widget go (a minute later,
    // so Undo can still bring it back).
    function removed(destroyed) {
        if (!root.token) return;
        root.send((destroyed ? "remove:" : "keep:") + root.token);
        if (!destroyed) root.announce();
    }

    function readState() {
        if (!widgetsDir || !token) return;
        var x = new XMLHttpRequest();
        x.onreadystatechange = function () {
            if (x.readyState !== XMLHttpRequest.DONE || !x.responseText) return;
            try {
                var s = JSON.parse(x.responseText);
                if (s.serial !== root.info.serial || s.state !== root.info.state || s.msg !== root.info.msg) root.info = s;
            } catch (e) {}
        };
        x.open("GET", widgetsDir + "/" + token + ".json");
        x.send();
    }
    Timer {
        interval: root.widgetState === "ok" ? 250 : 1000
        running: root.visible && root.token !== ""
        repeat: true
        triggeredOnStart: true
        onTriggered: root.readState()
    }

    Item {
        id: full
        anchors.fill: parent

        // Two images: the next frame loads in the hidden one and only then
        // takes the place of the shown one, so updates never flash.
        Item {
            id: frame
            anchors.fill: parent
            visible: root.widgetState === "ok"
            property int front: 0
            property string wanted: root.widgetState === "ok" && root.info.serial
                ? root.widgetsDir + "/" + root.token + ".png?" + root.info.serial : ""
            readonly property Image shown: front === 0 ? a : b
            onWantedChanged: if (wanted) (front === 0 ? b : a).source = wanted

            Image {
                id: a
                anchors.fill: parent
                cache: false
                asynchronous: true
                smooth: true
                fillMode: Image.PreserveAspectFit
                visible: frame.front === 0
                onStatusChanged: if (status === Image.Ready && source.toString() === frame.wanted) frame.front = 0
            }
            Image {
                id: b
                anchors.fill: parent
                cache: false
                asynchronous: true
                smooth: true
                fillMode: Image.PreserveAspectFit
                visible: frame.front === 1
                onStatusChanged: if (status === Image.Ready && source.toString() === frame.wanted) frame.front = 1
            }
        }

        // A point on the plasmoid as a pixel of the phone's frame.
        function toFrame(x, y) {
            var img = frame.shown;
            var pw = img.paintedWidth || width, ph = img.paintedHeight || height;
            var fw = root.info.w || root.pxWidth, fh = root.info.h || root.pxHeight;
            var fx = (x - (width - pw) / 2) * fw / pw, fy = (y - (height - ph) / 2) * fh / ph;
            return Qt.point(Math.round(Math.max(0, Math.min(fw - 1, fx))), Math.round(Math.max(0, Math.min(fh - 1, fy))));
        }

        MouseArea {
            id: area
            anchors.fill: parent
            enabled: root.widgetState === "ok"
            acceptedButtons: Qt.LeftButton
            property point start
            property double at: 0
            property bool moved: false
            property real wheel: 0
            onPressed: mouse => { start = Qt.point(mouse.x, mouse.y); at = Date.now(); moved = false }
            onPositionChanged: mouse => {
                if (Math.abs(mouse.x - start.x) + Math.abs(mouse.y - start.y) > Kirigami.Units.gridUnit / 2) moved = true;
            }
            onReleased: mouse => {
                var p = full.toFrame(start.x, start.y);
                var held = Date.now() - at;
                if (!moved) {
                    root.send((held > 600 ? "long:" : "tap:") + [root.token, p.x, p.y].join(":"));
                } else {
                    var q = full.toFrame(mouse.x, mouse.y);
                    root.send("swipe:" + [root.token, p.x, p.y, q.x, q.y, Math.max(80, Math.min(800, held))].join(":"));
                }
            }
            // The wheel scrolls lists in the widget: a short swipe per burst of turns.
            onWheel: wheelEvent => {
                wheel += wheelEvent.angleDelta.y;
                wheelAt = Qt.point(wheelEvent.x, wheelEvent.y);
                if (!wheelTimer.running) wheelTimer.start();
            }
            property point wheelAt
            Timer {
                id: wheelTimer
                interval: 120
                onTriggered: {
                    if (area.wheel === 0) return;
                    var p = full.toFrame(area.wheelAt.x, area.wheelAt.y);
                    var fh = root.info.h || root.pxHeight;
                    var d = Math.max(-fh / 2, Math.min(fh / 2, area.wheel / 120 * fh / 5));
                    var y2 = Math.max(0, Math.min(fh - 1, p.y + d));
                    area.wheel = 0;
                    root.send("swipe:" + [root.token, p.x, p.y, p.x, Math.round(y2), 150].join(":"));
                }
            }
        }

        // Anything but a frame: what the widget is waiting for.
        ColumnLayout {
            anchors.centerIn: parent
            width: Math.min(parent.width - Kirigami.Units.largeSpacing * 2, Kirigami.Units.gridUnit * 18)
            visible: root.widgetState !== "ok"
            spacing: Kirigami.Units.smallSpacing

            PlasmaComponents3.BusyIndicator {
                Layout.alignment: Qt.AlignHCenter
                visible: root.widgetState === "" || root.widgetState === "starting"
                running: visible
            }
            Kirigami.Icon {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                Layout.preferredHeight: Kirigami.Units.iconSizes.medium
                visible: !(root.widgetState === "" || root.widgetState === "starting") && full.height > Kirigami.Units.gridUnit * 5
                source: root.widgetState === "locked" ? "object-locked" : "smartphone"
            }
            PlasmaComponents3.Label {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                elide: Text.ElideRight
                maximumLineCount: 4
                textFormat: Text.PlainText
                text: root.widgetState === "permission" ? "Allow DeskDroid to show " + root.label + "."
                    : root.widgetState === "denied" ? root.label + " wasn't allowed."
                    : root.widgetState === "locked" ? "Unlock the private space to see " + root.label + "."
                    : root.widgetState === "missing" ? root.label + "'s app is gone from the phone."
                    : root.widgetState === "error" ? (root.info.msg || root.label + " couldn't start.")
                    : ""
                visible: text !== ""
            }
            PlasmaComponents3.Button {
                Layout.alignment: Qt.AlignHCenter
                visible: root.widgetState === "permission" || root.widgetState === "denied" || root.widgetState === "locked" || root.widgetState === "error"
                text: root.widgetState === "locked" ? "Unlock" : root.widgetState === "error" ? "Try Again" : "Allow…"
                icon.name: root.widgetState === "locked" ? "object-unlocked" : "dialog-ok"
                onClicked: root.send("allow:" + root.token)
            }
        }
    }
}

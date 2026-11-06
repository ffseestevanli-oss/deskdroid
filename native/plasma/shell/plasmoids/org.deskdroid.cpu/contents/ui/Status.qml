// DeskDroid writes the phone's status to files/status.json every 2 s
// (PhoneStatus.kt); this reads it. The files folder is found from this
// package's own path: files/kwin/share/plasma/plasmoids/<id>/contents/ui/.
import QtQuick

QtObject {
    id: status
    property var data: ({})
    property bool valid: data.time !== undefined
    readonly property string file: {
        var here = Qt.resolvedUrl(".").toString();
        var i = here.indexOf("/kwin/share/");
        return i < 0 ? "" : here.substring(0, i) + "/status.json";
    }
    function read() {
        if (!file) return;
        var x = new XMLHttpRequest();
        x.onreadystatechange = function () {
            if (x.readyState !== XMLHttpRequest.DONE || !x.responseText) return;
            try { status.data = JSON.parse(x.responseText); } catch (e) {}
        };
        x.open("GET", file);
        x.send();
    }
    property Timer timer: Timer {
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: status.read()
    }
}

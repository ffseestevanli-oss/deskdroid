import QtQuick

// A vertical level meter in 20 segments (DD Party's rainbow bar).
Item {
    id: m
    property real level: 0     // 0..1 linear
    implicitWidth: 8; implicitHeight: 60
    readonly property real db: 20 * Math.log(Math.max(level, 1e-5)) / Math.LN10
    readonly property int lit: Math.max(0, Math.min(20, Math.round((db + 48) / 48 * 20)))
    Column {
        anchors.fill: parent
        spacing: 1
        Repeater {
            model: 20
            Rectangle {
                required property int index
                width: m.width; height: (m.height - 19) / 20
                readonly property int seg: 19 - index
                color: seg < m.lit ? Theme.rainbow[Math.min(6, Math.floor((19 - seg) / 20 * 7))] : Theme.empty
            }
        }
    }
}

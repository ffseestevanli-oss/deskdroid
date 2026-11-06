import QtQuick
import QtQuick.Controls as QQC2

// ComboBox that always shows the stored value (never blank) and reports the user's pick.
QQC2.ComboBox {
    id: cb

    property var options: []        // [{ text, value }, ...]
    property string current: ""     // the stored value to display
    signal picked(string value)

    textRole: "text"
    model: options

    function idxOf(v) {
        for (var i = 0; i < options.length; ++i) {
            if (options[i].value === v) return i
        }
        return 0
    }
    function sync() {
        currentIndex = Qt.binding(function () { return cb.idxOf(cb.current) })
    }

    Component.onCompleted: sync()
    onOptionsChanged: sync()
    onActivated: index => {
        cb.picked(cb.options[index].value)
        cb.sync()
    }
}

// The sub-pages' header: back, and the page's title, in the party look.
import QtQuick
import QtQuick.Layouts
import "."

RowLayout {
    property string title: ""
    Layout.fillWidth: true
    spacing: 16
    PartyButton {
        text: "‹  Back"
        compact: true
        accent: Party.border
        onClicked: applicationWindow().pageStack.goBack()
    }
    RainbowText {
        heading: parent.title
        size: 24
        Layout.fillWidth: true
    }
}

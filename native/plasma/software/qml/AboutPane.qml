// Software's About tab: where apps come from, what an .adpk is, how
// Flathub apps run, and where the catalog is.
import QtQuick
import QtQuick.Layouts
import "."

ColumnLayout {
    id: about
    property var counts: ({})
    spacing: 14

    component Heading: Text {
        font.family: Party.heading; font.weight: Font.Black; font.pixelSize: 14; font.letterSpacing: 3
        Layout.topMargin: 8
    }
    component Para: Text {
        font.family: Party.body; font.pixelSize: 15
        color: Party.textSoft
        wrapMode: Text.WordWrap
        lineHeight: 1.2
        textFormat: Text.StyledText
        Layout.fillWidth: true
    }

    Flow {
        Layout.fillWidth: true
        spacing: 12
        Repeater {
            model: [
                { n: about.counts.deskdroid || 0, label: "DeskDroid Repo", c: Party.cyan },
                { n: about.counts.flathub || 0, label: "Flathub", c: Party.green },
                { n: about.counts.dependencies || 0, label: "Dependencies", c: Party.purple },
                { n: about.counts.installed || 0, label: "Installed", c: Party.yellow },
            ]
            Item {
                width: 170
                height: 86
                Chamfer { anchors.fill: parent; cut: 12; cutTopLeft: false; fillColor: Party.card; strokeColor: Party.borderSoft; strokeWidth: 1.5; accent: modelData.c; accentWidth: 3 }
                Column {
                    anchors.left: parent.left
                    anchors.leftMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    Text { text: modelData.n; font.family: Party.heading; font.weight: Font.Black; font.pixelSize: 28; color: modelData.c }
                    Text { text: modelData.label; font.family: Party.body; font.pixelSize: 13; color: Party.muted }
                }
            }
        }
    }

    Heading { text: "—  WHERE APPS COME FROM  —"; color: Party.cyan }
    Para {
        text: "<b>DeskDroid Repo</b> has apps built for DeskDroid itself: KDE apps compiled for Android, DeskDroid's own apps like Sasha, and themes.<br><br>"
            + "<b>Flathub</b> has Flathub's own ARM64 Linux builds, repackaged without changes. They aren't recompiled: ddmask, DeskDroid's compatibility layer, translates what they ask of Linux into what Android allows while they run, much as Proton does for Windows games.<br><br>"
            + "<b>Dependencies</b> are the runtimes Flathub apps share (KDE, GNOME, Freedesktop and Mesa for graphics). Installing an app installs the runtimes it needs first; the same runtime serves every app that uses it."
    }

    Heading { text: "—  .ADPK PACKAGES  —"; color: Party.purple }
    Para {
        text: "An .adpk is a DeskDroid package, like a .deb or .rpm: one file with the app, its menu entry and icons, and a small app.json saying what it is and what it needs. Double-click one in Dolphin, or use <b>Install from a file…</b>, to install it. Install packages only from people you trust."
    }

    Heading { text: "—  UPDATES  —"; color: Party.yellow }
    Para {
        text: "Agora compares what you have with the catalog each time it opens. An app with a newer version shows <b>Update</b>, and the tabs count the updates waiting."
    }

    Heading { text: "—  CATALOG  —"; color: Party.green }
    Para {
        text: backend.source ? "Read from " + backend.source : "Not read yet."
        color: Party.dim
        font.pixelSize: 13
        wrapMode: Text.WrapAnywhere
    }
}

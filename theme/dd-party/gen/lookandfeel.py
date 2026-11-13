"""Global theme (look-and-feel) package org.deskdroid.ddparty: ties the pieces
together, plus the splash screen and the default panel layout."""
import os, sys, json, shutil
from palette import *

ID = LNF_ID

DEFAULTS = """[kdeglobals][KDE]
widgetStyle=kvantum

[kdeglobals][General]
ColorScheme=DDParty

[kdeglobals][Icons]
Theme=DD-Party

[plasmarc][Theme]
name=%s

[Wallpaper]
Image=%s

[kcminputrc][Mouse]
cursorTheme=breeze_cursors

[kwinrc][org.kde.kdecoration2]
library=org.kde.kwin.aurorae
theme=__aurorae__svg__%s

[KSplash]
Theme=%s
""" % (SLUG, os.environ.get("DDP_WALLPAPER", CAMEL), CAMEL, ID)

LAYOUT = r"""// DD Party default layout: one floating bottom panel, like DeskDroid's own.
var panel = new Panel;
panel.location = "bottom";
panel.height = 2 * Math.floor(gridUnit * 2.6 / 2);
try { panel.floating = true; } catch (e) {}
try { panel.lengthMode = "fill"; } catch (e) {}

var kickoff = panel.addWidget("org.kde.plasma.kickoff");
kickoff.currentConfigGroup = ["Shortcuts"];
kickoff.writeConfig("global", "Alt+F1");
kickoff.currentConfigGroup = ["General"];
kickoff.writeConfig("icon", "start-here-kde");
kickoff.writeConfig("favoritesDisplay", 0);

panel.addWidget("org.kde.plasma.pager");

var tasks = panel.addWidget("org.kde.plasma.icontasks");
tasks.currentConfigGroup = ["General"];
tasks.writeConfig("launchers", [
    "applications:org.kde.dolphin.desktop",
    "applications:org.kde.konsole.desktop",
    "applications:org.deskdroid.software.desktop",
    "applications:systemsettings.desktop"
]);

panel.addWidget("org.kde.plasma.marginsseparator");
panel.addWidget("org.kde.plasma.systemtray");

var clock = panel.addWidget("org.kde.plasma.digitalclock");
clock.currentConfigGroup = ["Appearance"];
clock.writeConfig("autoFontAndSize", false);
clock.writeConfig("fontFamily", "Orbitron");
clock.writeConfig("boldText", true);
clock.writeConfig("fontWeight", 700);
clock.writeConfig("dateFormat", "shortDate");

panel.addWidget("org.kde.plasma.showdesktop");

var desktopsArray = desktopsForActivity(currentActivity());
for (var j = 0; j < desktopsArray.length; j++) {
    desktopsArray[j].wallpaperPlugin = "org.kde.image";
}
"""

SPLASH = r"""/*
    DD Party splash: the DeskDroid logo, its name in Orbitron and the
    20-segment rainbow bar from the installer, filling as Plasma starts.
*/
import QtQuick
import org.kde.kirigami 2 as Kirigami

Rectangle {
    id: root
    color: "#000000"
    property int stage
    readonly property var rainbow: ["#FF3B5C", "#FF9F1C", "#FFE14D", "#3DFF8B", "#2EC5FF", "#8B5CFF", "#FF4FD8"]

    function rainbowAt(t) {
        const n = rainbow.length - 1
        const pos = Math.max(0, Math.min(1, t)) * n
        const i = Math.min(Math.floor(pos), n - 1)
        const f = pos - i
        const a = Qt.color(rainbow[i]), b = Qt.color(rainbow[i + 1])
        return Qt.rgba(a.r + (b.r - a.r) * f, a.g + (b.g - a.g) * f, a.b + (b.b - a.b) * f, 1)
    }

    onStageChanged: {
        if (stage == 2) {
            introAnimation.running = true
        } else if (stage == 5) {
            introAnimation.from = 1; introAnimation.to = 0; introAnimation.running = true
        }
    }

    // soft magenta glow behind the logo
    Rectangle {
        anchors.centerIn: content
        width: Kirigami.Units.gridUnit * 34
        height: width
        radius: width / 2
        opacity: 0.22
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#990045" }
            GradientStop { position: 1.0; color: "#000000" }
        }
        visible: content.opacity > 0
    }

    Column {
        id: content
        anchors.centerIn: parent
        spacing: Kirigami.Units.gridUnit
        opacity: 0

        Image {
            anchors.horizontalCenter: parent.horizontalCenter
            source: "images/deskdroid.png"
            sourceSize.width: Kirigami.Units.gridUnit * 7
            sourceSize.height: Kirigami.Units.gridUnit * 7
            asynchronous: true
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "DESKDROID"
            color: "#F2F2F7"
            font.family: "Orbitron"
            font.weight: Font.Black
            font.pixelSize: Kirigami.Units.gridUnit * 1.6
            font.letterSpacing: Kirigami.Units.gridUnit * 0.35
        }
        Rectangle {
            id: bar
            anchors.horizontalCenter: parent.horizontalCenter
            width: Kirigami.Units.gridUnit * 22
            height: Kirigami.Units.gridUnit * 1.1
            color: "#12121E"
            border.color: "#2A2A3D"
            border.width: 1
            property int pulse: 0
            readonly property int lit: Math.round(Math.min(1, root.stage / 6) * 20)
            Timer {
                interval: 90; repeat: true; running: true
                onTriggered: bar.pulse = (bar.pulse + 1) % 20
            }
            Row {
                anchors.fill: parent
                anchors.margins: 3
                spacing: 2
                Repeater {
                    model: 20
                    Rectangle {
                        width: (bar.width - 6 - 2 * 19) / 20
                        height: parent.height
                        color: index < bar.lit || ((index - bar.pulse + 20) % 20) < 3
                               ? root.rainbowAt(index / 19) : "#1E1E2E"
                        opacity: index < bar.lit ? 1 : (((index - bar.pulse + 20) % 20) < 3 ? 0.55 : 1)
                    }
                }
            }
        }
    }

    // the rainbow strip along the top, as in every DeskDroid screen
    Rectangle {
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: 4
        opacity: content.opacity
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: "#FF3B5C" }
            GradientStop { position: 0.17; color: "#FF9F1C" }
            GradientStop { position: 0.33; color: "#FFE14D" }
            GradientStop { position: 0.5; color: "#3DFF8B" }
            GradientStop { position: 0.67; color: "#2EC5FF" }
            GradientStop { position: 0.83; color: "#8B5CFF" }
            GradientStop { position: 1.0; color: "#FF4FD8" }
        }
    }

    OpacityAnimator {
        id: introAnimation
        running: false
        target: content
        from: 0
        to: 1
        duration: Kirigami.Units.veryLongDuration * 2
        easing.type: Easing.InOutQuad
    }
}
"""

NATIVE = os.environ.get("DDP_NATIVE") == "1"
if NATIVE:
    # DeskDroid's native Plasma (Android): Breeze widgets in DD Party's
    # colours; no Kvantum or splash there, and its shell is
    # org.deskdroid.desktop, so no panel layout either. The window borders
    # are DD Party's Aurorae theme (KWin keeps Breeze in a build without Aurorae).
    DEFAULTS = (DEFAULTS.replace("widgetStyle=kvantum", "widgetStyle=Breeze")
                .split("\n[KSplash]")[0] + "\n")
    assert "kvantum" not in DEFAULTS and "KSplash" not in DEFAULTS

if __name__ == "__main__":
    out = sys.argv[1] + f"/plasma/look-and-feel/{ID}"
    logo = sys.argv[2]
    if os.path.exists(out):
        shutil.rmtree(out)
    os.makedirs(out + "/contents/previews")
    open(out + "/contents/defaults", "w").write(DEFAULTS)
    if not NATIVE:
        os.makedirs(out + "/contents/layouts")
        os.makedirs(out + "/contents/splash/images")
        open(out + "/contents/layouts/org.kde.plasma.desktop-layout.js", "w").write(LAYOUT)
        open(out + "/contents/splash/Splash.qml", "w").write(SPLASH)
        shutil.copy(logo, out + "/contents/splash/images/deskdroid.png")
    prev = os.path.join(os.path.dirname(logo), "previews-glass" if GLASS else "previews")
    for f in ("preview.png", "fullscreenpreview.jpg"):
        if os.path.exists(os.path.join(prev, f)):
            shutil.copy(os.path.join(prev, f), out + "/contents/previews/" + f)
    json.dump({
        "KPackageStructure": "Plasma/LookAndFeel",
        "KPlugin": {
            "Authors": [{"Name": "DeskDroid"}], "Category": "",
            "Description": ("DeskDroid's party look, see-through: blurred glass panels, popups, title bars and windows in near-black, #990045 magenta and rainbow"
                            if GLASS else "DeskDroid's party look: near-black, #990045 magenta, rainbow accents, chamfered corners"),
            "Id": ID, "License": "GPL-2.0-or-later", "Name": NAME, "Version": "1.0",
        },
        "X-Plasma-APIVersion": "2",
    }, open(out + "/metadata.json", "w"), indent=4)

#!/usr/bin/env python3
"""Add Widgets with the phone's widgets: Plasma's widgets on top, then a
second section with the Android widgets (NativeDesk.kt's AndroidWidgets
lists them in files/android-widgets/catalog.json; each one is a generated
plasmoid, org.deskdroid.android.*, hidden from Plasma's own list).

Search narrows both sections; picking a category shows Plasma's widgets only.
Android widgets are added like any other: click, Enter or drag.

explorer-android.py <shell package dir>"""
import pathlib
import sys

p = pathlib.Path(sys.argv[1]) / "contents" / "explorer" / "WidgetExplorer.qml"
t = p.read_text()


def edit(old, new, count=1):
    global t
    if t.count(old) != count:
        sys.exit(f"explorer-android.py: WidgetExplorer.qml changed near {old[:60]!r}")
    t = t.replace(old, new)


# The catalog, read when the sidebar opens; search narrows it.
edit("""    property bool draggingWidget: false
""", """    property bool draggingWidget: false

    // DeskDroid: the phone's widgets (files/android-widgets/catalog.json,
    // found from this file's own path: files/kwin/share/plasma/shells/...).
    property var androidCatalog: []
    property bool androidShown: true
    readonly property string androidCatalogFile: {
        var here = Qt.resolvedUrl(".").toString();
        var i = here.indexOf("/kwin/share/");
        return i < 0 ? "" : here.substring(0, i) + "/android-widgets/catalog.json";
    }
    function readAndroidCatalog() {
        if (!androidCatalogFile) return;
        var x = new XMLHttpRequest();
        x.onreadystatechange = function () {
            if (x.readyState !== XMLHttpRequest.DONE) return;
            try { main.androidCatalog = JSON.parse(x.responseText).widgets || []; } catch (e) { main.androidCatalog = []; }
            main.filterAndroid();
        };
        x.open("GET", androidCatalogFile);
        x.send();
    }
    function filterAndroid() {
        var words = searchInput.text.toLowerCase().split(/\\s+/).filter(function (w) { return w.length > 0; });
        androidModel.clear();
        for (var i = 0; i < androidCatalog.length; i++) {
            var w = androidCatalog[i];
            var hay = (w.name + " " + w.description).toLowerCase();
            if (!words.every(function (x) { return hay.indexOf(x) >= 0; })) continue;
            androidModel.append({
                pluginName: w.plugin, name: w.name, description: w.description,
                decoration: w.icon || "smartphone", screenshot: w.preview ? "file://" + w.preview : "",
                isSupported: true, unsupportedMessage: "", running: 0, local: false, recent: false
            });
        }
    }
    ListModel { id: androidModel }
""")
edit("""        root.widgetExplorer.containment = main.containment
    }
""", """        root.widgetExplorer.containment = main.containment
        main.readAndroidCatalog()
    }
""")
edit("""    function addCurrentApplet() {
        var pluginName = list.currentItem ? list.currentItem.pluginName : ""
""", """    function addCurrentApplet() {
        var current = list.currentItem || androidList.currentItem
        var pluginName = current ? current.pluginName : ""
""")
edit("""            list.contentX = 0
            list.contentY = 0
""", """            list.contentX = 0
            list.contentY = 0
            scroller.contentY = 0
            main.androidShown = !model.filterData
""")
edit("""                        list.positionViewAtBeginning()
                        list.currentIndex = -1
""", """                        list.positionViewAtBeginning()
                        list.currentIndex = -1
                        androidList.currentIndex = -1
                        scroller.contentY = 0
                        main.filterAndroid()
""")
edit("""            value: list.contentHeight > height
""", """            value: scroller.contentHeight > height
""")

# Both lists in one scrolling column, each as tall as its rows.
edit("""        GridView {
            id: list
""", """        Flickable { // DeskDroid: Plasma's widgets, then the phone's
        id: scroller
        contentWidth: width
        contentHeight: sections.height
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        Column {
        id: sections
        width: scroller.width

        RowLayout {
            visible: androidSection.visible
            width: parent.width - main.contentMargins * 2
            x: main.contentMargins
            height: Kirigami.Units.gridUnit * 2
            Kirigami.Heading {
                level: 4
                text: "Plasma Widgets"
                textFormat: Text.PlainText
            }
            Kirigami.Separator { Layout.fillWidth: true }
        }

        GridView {
            id: list
            width: parent.width
            height: contentHeight + topMargin + bottomMargin
            interactive: false
            onCurrentIndexChanged: if (currentIndex >= 0) androidList.currentIndex = -1
""")
edit("""            KeyNavigation.up: searchInput
            KeyNavigation.down: uninstallButton
        }
    }
""", """            KeyNavigation.up: searchInput
            KeyNavigation.down: androidList.count > 0 ? androidList : uninstallButton
        }

        Column {
            id: androidSection
            width: parent.width
            visible: main.androidShown && androidModel.count > 0

            RowLayout {
                width: parent.width - main.contentMargins * 2
                x: main.contentMargins
                height: Kirigami.Units.gridUnit * 2
                Kirigami.Heading {
                    level: 4
                    text: "Android Widgets"
                    textFormat: Text.PlainText
                }
                Kirigami.Separator { Layout.fillWidth: true }
            }

            GridView {
                id: androidList
                width: parent.width
                height: contentHeight + topMargin + bottomMargin
                interactive: false
                topMargin: main.contentMargins
                leftMargin: main.contentMargins
                rightMargin: main.contentMargins
                bottomMargin: main.contentMargins
                activeFocusOnTab: true
                cellWidth: list.cellWidth
                cellHeight: list.cellHeight
                model: androidModel
                delegate: AppletDelegate {}
                highlight: PlasmaExtras.Highlight {
                    pressed: androidList.currentItem && androidList.currentItem.pressed
                }
                highlightMoveDuration: 0
                onCurrentIndexChanged: if (currentIndex >= 0) list.currentIndex = -1
                KeyNavigation.up: list
                KeyNavigation.down: uninstallButton
            }
        }
        }
        }
    }
""")
edit("""        visible: list.count == 0 && !setModelTimer.running
""", """        visible: list.count == 0 && !androidSection.visible && !setModelTimer.running
""")
p.write_text(t)

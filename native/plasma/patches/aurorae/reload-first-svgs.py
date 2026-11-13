#!/usr/bin/env python3
"""DeskDroid: the first window opened after Plasma starts got an Aurorae title
bar with its text and icon but no frame and no buttons (every later window
was fine, and maximising didn't help): the theme's SVGs weren't drawn for the
first decoration. Each decoration and button now loads its SVG again shortly
after it's made, as a later window's does, so the first one draws too.
Usage: reload-first-svgs.py <aurorae source folder>"""
import sys

src = sys.argv[1] + "/src/qml/"


def patch(name, anchor, svg_id, binding):
    p = src + name
    s = open(p).read()
    assert anchor in s, (name, anchor)
    timer = f'''
    // DeskDroid: load the SVG again once things are up (the first title bar
    // after Plasma starts drew nothing from it).
    Timer {{
        interval: 1500
        running: true
        onTriggered: {{
            {svg_id}.imagePath = "";
            {svg_id}.imagePath = Qt.binding(function() {{ return {binding}; }});
        }}
    }}
'''
    s = s.replace(anchor, anchor + timer, 1)
    open(p, "w").write(s)


patch("aurorae.qml", "        imagePath: auroraeTheme.decorationPath\n    }\n", "backgroundSvg", "auroraeTheme.decorationPath")
patch("AuroraeButton.qml", "        imagePath: pathForButton()\n    }\n", "buttonSvg", "pathForButton()")

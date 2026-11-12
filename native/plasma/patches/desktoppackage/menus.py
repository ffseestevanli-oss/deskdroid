#!/usr/bin/env python3
"""Kickoff and Application Menu (Kicker), as DeskDroid has them:

- No power options: the phone's power button has those. Each menu has one
  "Session" entry (KDE's Log Out, renamed in plasmashell/add-to-workspace.py),
  which opens the Session screen: Restart Desktop, End Session (not as the
  home app) and Lock Private Profile.
- Apps sorted alphabetically (Android Apps too) by default.

menus.py <share/plasma/plasmoids>"""
import pathlib
import sys

root = pathlib.Path(sys.argv[1])


def edit(rel, old, new):
    p = root / rel
    t = p.read_text()
    if t.count(old) != 1:
        sys.exit(f"menus.py: {old!r} not once in {rel}")
    p.write_text(t.replace(old, new))


def default(rel, entry, value):
    p = root / rel
    t = p.read_text()
    a = t.find(f'<entry name="{entry}"')
    if a < 0:
        sys.exit(f"menus.py: no {entry} in {rel}")
    b = t.index("<default>", a) + len("<default>")
    c = t.index("</default>", b)
    p.write_text(t[:b] + value + t[c:])


ko = "org.kde.plasma.kickoff/contents/"
default(ko + "config/main.xml", "alphaSort", "true")
default(ko + "config/main.xml", "systemFavorites", "logout")
default(ko + "config/main.xml", "primaryActions", "1")
# The footer: the Session button alone, whatever the settings say, and no
# overflow menu of other actions (Sleep, Restart, Shut Down...).
edit(ko + "ui/LeaveButtons.qml",
     "const allActionsArePrimary = Plasmoid.configuration.primaryActions === 3;",
     "const allActionsArePrimary = true; // DeskDroid: Session only")
edit(ko + "ui/LeaveButtons.qml",
     "return String(Plasmoid.configuration.systemFavorites).includes(favoriteId);",
     'return favoriteId === "logout"; // DeskDroid: Session only')
edit(ko + "ui/LeaveButtons.qml",
     "        filterRowCallback: root.__layout.collapseActionButtons\n"
     "            ? null /*i.e. keep all rows*/\n"
     "            : (sourceRow, sourceParent) => !systemFavoritesContainsRow(sourceRow, sourceParent)\n",
     "        filterRowCallback: root.__layout.collapseActionButtons // DeskDroid: Session only\n"
     "            ? (sourceRow, sourceParent) => systemFavoritesContainsRow(sourceRow, sourceParent)\n"
     "            : (sourceRow, sourceParent) => false\n")

ki = "org.kde.plasma.kicker/contents/"
default(ki + "config/main.xml", "alphaSort", "true")
default(ki + "config/main.xml", "favoriteSystemActions", "logout")
# No Power / Session folder; the Session entry stays in the sidebar.
edit(ki + "ui/main.qml", "        showSeparators: !kicker.isDash\n",
     "        showSeparators: !kicker.isDash\n        showPowerSession: false // DeskDroid\n")
# The sidebar's system actions: Session only, whatever the settings say.
p = root / ki / "ui/main.qml"
s = p.read_text()
old = "systemFavorites.favorites = Plasmoid.configuration.favoriteSystemActions;"
if s.count(old) != 2:
    sys.exit("menus.py: Kicker's system favorites changed")
p.write_text(s.replace(old, 'systemFavorites.favorites = ["logout"]; // DeskDroid: Session only'))

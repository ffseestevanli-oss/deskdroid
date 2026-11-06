# DeskDroid's first Plasma shell

A small Plasma shell (`org.deskdroid.desktop`) with its own desktop and panel
containments, a clock and a gradient wallpaper, all plain QML on top of the
real plasmashell, libplasma and KWin. Plasma's own shell package
(`org.kde.plasma.desktop`, from plasma-desktop) needs a dozen more libraries
first (task manager, activities, KCMUtils, KDeclarative...); these stand in
until those are built, then go away.

The bundler (native/nativedesk/build.sh) ships this folder as share/plasma.

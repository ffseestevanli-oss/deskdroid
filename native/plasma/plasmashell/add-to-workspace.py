#!/usr/bin/env python3
"""Cuts plasma-workspace down to plasmashell (and libkworkspace, which it
needs) and builds plasmashell as a library that DeskDroid's QtHost starts,
like kwin_wayland (see kwin-nativedesk/qthost_entry.cpp)."""
import pathlib
import sys

ws = pathlib.Path(sys.argv[1])
here = pathlib.Path(__file__).resolve().parent


def edit(rel, old, new):
    p = ws / rel
    t = p.read_text()
    if old not in t:
        sys.exit(f"add-to-workspace: {old!r} not in {rel}")
    p.write_text(t.replace(old, new, 1))


(ws / "CMakeLists.txt").write_text((here / "CMakeLists.top.txt").read_text())
(ws / "org.freedesktop.ScreenSaver.xml").write_text((here / "org.freedesktop.ScreenSaver.xml").read_text())

edit("shell/CMakeLists.txt", "add_executable(plasmashell)",
     "add_library(plasmashell SHARED)\n"
     "set_target_properties(plasmashell PROPERTIES CXX_VISIBILITY_PRESET default)")
# The systemd unit and the autostart entry are for a Linux session.
edit("shell/CMakeLists.txt", "ecm_install_configured_files(INPUT plasma-plasmashell.service.in",
     "# ecm_install_configured_files(INPUT plasma-plasmashell.service.in")
# Qt here has no X11 platform plugin, so no QX11Application to ask for.
dv = ws / "shell/desktopview.cpp"
t = dv.read_text()
x11app = "qGuiApp->nativeInterface<QNativeInterface::QX11Application>()"
if x11app not in t:
    sys.exit("add-to-workspace: no QX11Application use in desktopview.cpp")
dv.write_text(t.replace(x11app, "false"))
# No kactivitymanagerd yet: plasmashell loads without it, as in its own tests.
edit("shell/main.cpp", "    QApplication app(argc, argv);\n",
     "    QApplication app(argc, argv);\n"
     "    app.setProperty(\"org.kde.KActivities.core.disableAutostart\", true);\n")
edit("shell/main.cpp", "int main(int argc, char *argv[])", "int plasmashellMain(int argc, char *argv[])")

# The digital clock's city names come from ICU's C++ API, which Android
# doesn't offer to apps: the last part of the zone id stands in for now.
dc = "applets/digital-clock/plugin/"
edit(dc + "CMakeLists.txt", "        ICU::i18n\n        ICU::uc\n", "")
edit(dc + "timezonesi18n.h", "#include <unicode/tznames.h>\n", "")
edit(dc + "timezonesi18n.h", "    QScopedPointer<icu::TimeZoneNames> m_tzNames;\n", "")
edit(dc + "timezonesi18n.cpp", "#include <unicode/localebuilder.h>\n", "")
t = (ws / dc / "timezonesi18n.cpp").read_text()
a = t.index("    if (!m_tzNames) {")
b = t.index("toString();\n", a) + len("toString();\n")
t = t[:a] + "    return timezoneId.section(u'/', -1).replace(u'_', u' ');\n" + t[b:]
a = t.index("    const auto locale = icu::Locale(")
b = t.index("    m_isInitialized = true;", a)
t = t[:a] + t[b:]
assert "icu" not in t and "m_tzNames" not in t
(ws / dc / "timezonesi18n.cpp").write_text(t)

entry = (here.parent / "kwin-nativedesk" / "qthost_entry.cpp").read_text()
entry = entry.replace("KWin's main_wayland.cpp: on Android kwin_wayland", "plasmashell's main.cpp: on Android plasmashell")
entry = entry.replace('args.push_back("kwin_wayland")', 'args.push_back("plasmashell")')
entry = entry.replace("return kwinMain(", "return plasmashellMain(")
assert "kwinMain" not in entry and '"kwin_wayland"' not in entry
p = ws / "shell" / "main.cpp"
p.write_text(p.read_text() + "\n" + entry)

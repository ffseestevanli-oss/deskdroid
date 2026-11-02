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

# libtaskmanager's X11 helper (used only on X11) asks for QX11Application.
edit("libtaskmanager/virtualdesktopinfo.cpp",
     "return qGuiApp->nativeInterface<QNativeInterface::QX11Application>()->connection();", "return nullptr;")

# MPRIS for the task manager, without its KDED module (no kded here).
edit("libkmpris/CMakeLists.txt", "add_subdirectory(kded)", "# add_subdirectory(kded)")

entry = (here.parent / "kwin-nativedesk" / "qthost_entry.cpp").read_text()
entry = entry.replace("KWin's main_wayland.cpp: on Android kwin_wayland", "plasmashell's main.cpp: on Android plasmashell")
entry = entry.replace('args.push_back("kwin_wayland")', 'args.push_back("plasmashell")')
entry = entry.replace("return kwinMain(", "return plasmashellMain(")
assert "kwinMain" not in entry and '"kwin_wayland"' not in entry
p = ws / "shell" / "main.cpp"
p.write_text(p.read_text() + "\n" + entry)

# ---- End Session: Kickoff's Log Out and KDE's logout screen ----------------
# Kickoff's "Log Out" is "End Session": the desktop is a session inside
# DeskDroid, and ending it closes the desktop, not a login.
edit("applets/kicker/systementry.cpp", 'return i18n("Log Out");', 'return QStringLiteral("End Session"); // DeskDroid')
# No ksmserver here: SessionManagement asks the logout screen
# (ksmserver-logout-greeter, an app on PATH) to show itself directly, instead
# of over D-Bus activation, which this session bus doesn't do.
sm = "libkworkspace/sessionmanagement.cpp"
edit(sm, "#include <QEventLoopLocker>",
     "#include <QEventLoopLocker>\n#include <QProcess>\n"
     "static void deskdroidLogoutPrompt()\n{\n"
     "    QProcess::startDetached(QStringLiteral(\"ksmserver-logout-greeter\"),\n"
     "                            {QStringLiteral(\"--lookandfeel\"), QStringLiteral(\"org.kde.breeze.desktop\"), QStringLiteral(\"--logout\")});\n}\n")
t = (ws / sm).read_text()
a = t.index("void SessionManagement::requestLogout(ConfirmationMode confirmationMode)\n{")
b = t.index("\n}\n", a)
t = t[:a] + ("void SessionManagement::requestLogout(ConfirmationMode confirmationMode)\n{\n"
             "    Q_UNUSED(confirmationMode)\n"
             "    if (!canLogout()) {\n        return;\n    }\n"
             "    deskdroidLogoutPrompt(); // DeskDroid") + t[b:]
a = t.index("void SessionManagement::requestLogoutPrompt()\n{")
b = t.index("\n}\n", a)
t = t[:a] + "void SessionManagement::requestLogoutPrompt()\n{\n    deskdroidLogoutPrompt(); // DeskDroid" + t[b:]
(ws / sm).write_text(t)

# The logout screen, built as a library QtHost starts (apps/as-library.py).
lg = "logout-greeter/"
edit(lg + "CMakeLists.txt", "add_executable(ksmserver-logout-greeter ${LOGOUT_GREETER_SRCS})",
     "add_executable(ksmserver-logout-greeter)\ntarget_sources(ksmserver-logout-greeter PRIVATE ${LOGOUT_GREETER_SRCS})")
edit(lg + "CMakeLists.txt", "    X11::X11\n", "")
edit(lg + "CMakeLists.txt", "install(TARGETS ksmserver-logout-greeter DESTINATION ${KDE_INSTALL_LIBEXECDIR})",
     "install(TARGETS ksmserver-logout-greeter ${KDE_INSTALL_TARGETS_DEFAULT_ARGS})")
edit(lg + "CMakeLists.txt", "kdbusaddons_generate_dbus_service_file(", "# kdbusaddons_generate_dbus_service_file(")
sd = ws / lg / "shutdowndlg.cpp"
t = sd.read_text()
for inc in ("#include <netwm.h>\n", "#include <X11/Xatom.h>\n", "#include <X11/Xutil.h>\n", "#include <fixx11h.h>\n"):
    if inc not in t:
        sys.exit(f"add-to-workspace: no {inc.strip()} in shutdowndlg.cpp")
    t = t.replace(inc, "")
a = t.index("    if (KWindowSystem::isPlatformX11()) {\n        constexpr auto role")
b = t.index("NET::SkipSwitcher);\n    }\n", a) + len("NET::SkipSwitcher);\n    }\n")
t = t[:a] + t[b:]
# Close Desktop: DeskDroid watches $HOME/open-requests and ends the desktop
# for an end-session request.
old = "void KSMShutdownDlg::slotLogout()\n{\n    m_session.requestLogout(SessionManagement::ConfirmationMode::Skip);\n"
if old not in t:
    sys.exit("add-to-workspace: slotLogout changed")
t = t.replace(old, "void KSMShutdownDlg::slotLogout()\n{\n"
              "    const QString d = QDir::homePath() + QStringLiteral(\"/open-requests\");\n"
              "    QDir().mkpath(d);\n"
              "    QFile f(d + QStringLiteral(\"/.end-session\"));\n"
              "    if (f.open(QIODevice::WriteOnly)) {\n        f.write(\"end-session\\n\");\n        f.close();\n"
              "        QFile::remove(d + QStringLiteral(\"/end-session.req\"));\n"
              "        f.rename(d + QStringLiteral(\"/end-session.req\"));\n    }\n", 1)
# Restart or Power Off: Android's power menu (DeskDroid opens it through its
# accessibility service), for a power-menu request.
old = "void KSMShutdownDlg::slotReboot()\n{\n"
if old not in t:
    sys.exit("add-to-workspace: slotReboot changed")
t = t.replace(old, old +
              "    {\n        const QString d = QDir::homePath() + QStringLiteral(\"/open-requests\");\n"
              "        QDir().mkpath(d);\n"
              "        QFile f(d + QStringLiteral(\"/.power-menu\"));\n"
              "        if (f.open(QIODevice::WriteOnly)) {\n            f.write(\"power-menu\\n\");\n            f.close();\n"
              "            QFile::remove(d + QStringLiteral(\"/power-menu.req\"));\n"
              "            f.rename(d + QStringLiteral(\"/power-menu.req\"));\n        }\n"
              "        reject(); // the logout screen closes, the desktop stays\n        return;\n    }\n", 1)
t = t.replace("#include <QFile>\n", "#include <QDir>\n#include <QFile>\n", 1)
sd.write_text(t)
for word in ("X11/", "XChangeProperty", "fixx11h"):
    assert word not in t, word
# "Log Out" in KDE's logout screen is "Close Desktop".
lo = "lookandfeel/org.kde.breeze/contents/logout/Logout.qml"
edit(lo, 'text: root.showAllOptions ? i18nd("plasma_lookandfeel_org.kde.lookandfeel", "&Log Out")\n'
         '                                          : i18nd("plasma_lookandfeel_org.kde.lookandfeel", "&Log Out Now")',
     'text: "Close Desktop" // DeskDroid')
edit(lo, "            LogoutButton {\n                id: cancelButton\n",
     "            LogoutButton { // DeskDroid: Android's power menu\n"
     "                id: phonePowerButton\n"
     "                icon.name: \"system-shutdown\"\n"
     "                text: \"Restart or Power Off\"\n"
     "                onClicked: rebootRequested()\n"
     "            }\n"
     "            LogoutButton {\n                id: cancelButton\n")
# --logout: show the logout prompt at start (SessionManagement starts it).
mn = lg + "main.cpp"
edit(mn, "        parser.addOption(lnfOption);\n",
     "        parser.addOption(lnfOption);\n"
     "        parser.addOption(QCommandLineOption(u\"logout\"_s, u\"DeskDroid: show the logout prompt now\"_s));\n")
edit(mn, "        windowed = parser.isSet(testingOption);\n",
     "        windowed = parser.isSet(testingOption);\n"
     "        deskdroidLogout = parser.isSet(u\"logout\"_s);\n")
edit(mn, "    bool windowed = false;\n", "    bool windowed = false;\n    bool deskdroidLogout = false;\n")
edit(mn, "        greeter.enableWindowed();\n    }\n",
     "        greeter.enableWindowed();\n    } else if (deskdroidLogout) {\n        greeter.promptLogout();\n    }\n")
import subprocess
subprocess.run([sys.executable, str(here.parent / "apps" / "as-library.py"), str(ws),
                lg + "CMakeLists.txt", "ksmserver-logout-greeter", mn], check=True)

# Mouse actions settings: picking a mouse action whose plugin isn't built
# (only the right-click menu is) left a null plugin that was used at once.
cc = "shell/currentcontainmentactionsmodel.cpp"
t = (ws / cc).read_text()
old = ("            m_plugins[action] = Plasma::PluginLoader::self()->loadContainmentActions(m_containment, plugin);\n"
       "            m_plugins[action]->setContainment(m_containment);\n")
if t.count(old) < 1:
    sys.exit("add-to-workspace: currentcontainmentactionsmodel.cpp changed")
t = t.replace(old, "            m_plugins[action] = Plasma::PluginLoader::self()->loadContainmentActions(m_containment, plugin);\n"
                   "            if (!m_plugins[action]) { m_plugins.remove(action); return; } // DeskDroid: plugin not built\n"
                   "            m_plugins[action]->setContainment(m_containment);\n")
(ws / cc).write_text(t)

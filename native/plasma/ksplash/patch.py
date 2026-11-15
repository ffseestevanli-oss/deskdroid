#!/usr/bin/env python3
"""DeskDroid's change to plasma-workspace's splash screen (build_ksplash).

ksplashqml counts seven start-up stages and quits after the last. Here the
desktop starts without startplasma, kcminit, ksmserver or plasma-session,
so their stages are counted as done at once (when DESKDROID_BIN is set, as
in the desktop's environment) and only plasmashell's "desktop" stage is
waited for. If plasmashell never says so, the splash goes after a minute."""
import pathlib
import sys

ws = pathlib.Path(sys.argv[1])
p = ws / "ksplash/ksplashqml/splashapp.cpp"
t = p.read_text()
old = """    if (KWindowSystem::isPlatformWayland()) {
        setStage(QStringLiteral("wm"));
    }
"""
new = old + """
    // DeskDroid: nothing else reports these stages here (patch.py).
    if (!m_testing && qEnvironmentVariableIsSet("DESKDROID_BIN")) {
        for (const auto stage : {"startPlasma", "kcminit", "ksmserver", "ready"}) {
            setStage(QString::fromLatin1(stage));
        }
        QTimer::singleShot(60000, this, [] {
            QGuiApplication::exit(EXIT_SUCCESS);
        });
    }
"""
if t.count(old) != 1:
    sys.exit("ksplash/patch.py: stage code not found")
t = t.replace(old, new)
if "#include <QTimer>" not in t:
    t = t.replace('#include "splashapp.h"\n', '#include "splashapp.h"\n#include <QTimer>\n', 1)
    assert "#include <QTimer>" in t
p.write_text(t)

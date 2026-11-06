#!/usr/bin/env python3
"""The file dialog's "The specified folder does not exist or was not readable"
says which folder: on Android it's often a path the phone's storage rules
hide, and without its name there's no telling which."""
import sys
p = sys.argv[1] + "/src/filewidgets/kdiroperator.cpp"
t = open(p).read()
old = """                               i18n("The specified folder does not exist "
                                    "or was not readable."));"""
assert t.count(old) == 1, "message"
t = t.replace(old, """                               i18n("The specified folder does not exist "
                                    "or was not readable.") + QLatin1Char('\\n') + newurl.toDisplayString(QUrl::PreferLocalFile));
            qWarning() << "DeskDroid: folder not readable:" << newurl;""")
open(p, "w").write(t)

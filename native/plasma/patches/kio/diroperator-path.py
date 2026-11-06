#!/usr/bin/env python3
"""File dialogs and file panels (KDirOperator) on a folder Android won't let
the app read, such as / or /storage: instead of the "The specified folder does
not exist or was not readable" message box (which on a phone comes up for
folders every Linux app expects to read, and can repeat), they go to the home
folder, and the folder's name goes to the log."""
import sys
p = sys.argv[1] + "/src/filewidgets/kdiroperator.cpp"
t = open(p).read()

old = """        if ((!res || !d->isReadable(newurl)) && i.isDir()) {
            resetCursor();
            KMessageBox::error(d->m_itemView,
                               i18n("The specified folder does not exist "
                                    "or was not readable."));
            return;"""
assert t.count(old) == 1, "setUrl"
t = t.replace(old, """        if ((!res || !d->isReadable(newurl)) && i.isDir()) {
            resetCursor();
            // DeskDroid: the home folder instead of a message box.
            qWarning() << "DeskDroid: folder not readable, going home instead:" << newurl;
            const QUrl home = QUrl::fromLocalFile(QDir::homePath());
            if (!newurl.matches(home, QUrl::StripTrailingSlash) && !d->m_currUrl.matches(home, QUrl::StripTrailingSlash)) {
                setUrl(home, clearforward);
            }
            return;""")

old = """    if (!d->isReadable(d->m_currUrl)) {
        KMessageBox::error(d->m_itemView,
                           i18n("The specified folder does not exist "
                                "or was not readable."));
        if (d->m_backStack.isEmpty()) {"""
assert t.count(old) == 1, "pathChanged"
t = t.replace(old, """    if (!d->isReadable(d->m_currUrl)) {
        // DeskDroid: back (or home) without a message box.
        qWarning() << "DeskDroid: folder not readable:" << d->m_currUrl;
        if (d->m_backStack.isEmpty()) {""")
if "#include <QDebug>" not in t:
    t = t.replace("#include <QDir>", "#include <QDebug>\n#include <QDir>", 1)
open(p, "w").write(t)

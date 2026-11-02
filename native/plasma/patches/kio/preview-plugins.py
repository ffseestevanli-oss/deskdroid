#!/usr/bin/env python3
"""Thumbnails for every caller of KIO's PreviewJob.

The wallpaper picker asks for KIO::PreviewJob::availablePlugins() from QML's
image threads, several at once, and the list of thumbnailers is a static
filled on first use with no lock: threads that came in while it was being
filled got an empty or partial list, so nothing was enabled and no image got
a thumbnail. The list is filled under a lock now, and a job given an empty
list of plugins uses the user's (or KDE's default) ones instead of none."""
import sys
p = sys.argv[1] + "/src/gui/previewjob.cpp"
t = open(p).read()
old = """        static QList<KPluginMetaData> jsonMetaDataPlugins;
        if (jsonMetaDataPlugins.isEmpty()) {"""
new = """        static QList<KPluginMetaData> jsonMetaDataPlugins;
        static QMutex jsonMetaDataPluginsLock;
        QMutexLocker jsonMetaDataPluginsLocker(&jsonMetaDataPluginsLock);
        if (jsonMetaDataPlugins.isEmpty()) {"""
assert t.count(old) == 1, "loadAvailablePlugins"
t = t.replace(old, new)
old = """    if (enabledPlugins) {
        d->enabledPlugins = *enabledPlugins;"""
new = """    if (enabledPlugins && !enabledPlugins->isEmpty()) {
        d->enabledPlugins = *enabledPlugins;"""
assert t.count(old) == 1, "constructor"
t = t.replace(old, new)
t = t.replace("#include <QMimeDatabase>", "#include <QMimeDatabase>\n#include <QMutex>", 1)
assert "#include <QMutex>" in t
open(p, "w").write(t)

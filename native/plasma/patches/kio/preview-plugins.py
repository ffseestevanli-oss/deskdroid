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
# Thumbnails are saved in <cache>/thumbnails/<size>/, made with a plain
# mkdir of the size folder: on Linux thumbnails/ is always there already, here
# it wasn't, so nothing could be cached and its device check failed.
old = """        thumbRoot = QStandardPaths::writableLocation(QStandardPaths::GenericCacheLocation) + QLatin1String("/thumbnails/");
"""
assert t.count(old) == 1, "thumbRoot"
t = t.replace(old, old + """        QDir().mkpath(thumbRoot);
""")
# The thumbnail worker sends width, height, format and pixel ratio ahead of
# the image even when it isn't using shared memory (which Android hasn't
# got); PreviewJob read the image straight from the start without shared
# memory, so every thumbnail came back empty. Read past those first.
old = """    if (thumb.isNull()) {
        // fallback a raw QImage
        str >> thumb;
    }
"""
assert t.count(old) == 1, "slotThumbData"
t = t.replace(old, """#if !WITH_SHM
    {
        int width;
        int height;
        QImage::Format format;
        qreal imgDevicePixelRatio;
        str >> width >> height >> format >> imgDevicePixelRatio;
        str >> thumb;
        thumb.setDevicePixelRatio(imgDevicePixelRatio);
    }
#endif
""" + old)
open(p, "w").write(t)

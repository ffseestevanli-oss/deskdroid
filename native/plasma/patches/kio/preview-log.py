#!/usr/bin/env python3
"""KIO's PreviewJob drops a file silently when it can't make its thumbnail;
log why (no thumbnailer for its type, or the step that failed and its error),
so the cause shows up in DeskDroid's log."""
import sys
p = sys.argv[1] + "/src/gui/previewjob.cpp"
t = open(p).read()
old = """        } else {
            Q_EMIT q->failed(fileItem);
        }"""
new = """        } else {
            qCWarning(KIO_GUI) << "DeskDroid: no thumbnailer for" << mimeType << "among" << plugins.size() << "plugins:" << fileItem.url();
            Q_EMIT q->failed(fileItem);
        }"""
assert t.count(old) == 1, "no-plugin branch"
t = t.replace(old, new)
old = """    removeSubjob(job);
    Q_ASSERT(!hasSubjobs()); // We should have only one job at a time ..."""
new = old + """
    if (job->error()) {
        qCWarning(KIO_GUI) << "DeskDroid: preview step" << int(d->state) << "failed for" << d->currentItem.item.url() << ":" << job->errorString();
    }"""
assert t.count(old) == 1, "slotResult"
t = t.replace(old, new)
old = """        bool pluginIsEnabled = enabledPlugins.contains(plugin.pluginId());"""
new = old + """
        {
            static int told = 0;
            if (told++ < 40) {
                qCWarning(KIO_GUI) << "DeskDroid: thumbnailer" << plugin.pluginId() << plugin.fileName() << "types" << plugin.mimeTypes().size()
                                   << "enabled" << pluginIsEnabled << "of" << enabledPlugins;
            }
        }"""
assert t.count(old) == 1, "plugin loop"
t = t.replace(old, new)
open(p, "w").write(t)

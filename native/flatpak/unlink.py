#!/usr/bin/env python3
"""Replaces every symlink under a folder with the file it points at.

unlink.py <folder>

Java's unzip (the app unpacks with it) can't make symlinks. A file that
only links point at moves to the first link's name and is copied for the
others; links to files outside the folder, or to folders, are dropped.
"""
import os
import shutil
import sys

root = os.path.realpath(sys.argv[1])
links = {}
for d, dirs, files in os.walk(root):
    for n in dirs + files:
        p = os.path.join(d, n)
        if os.path.islink(p):
            t = os.path.realpath(p)
            if t.startswith(root + "/") and os.path.isfile(t):
                links.setdefault(t, []).append(p)
            else:
                os.unlink(p)
for t, ls in links.items():
    ls.sort()
    for l in ls:
        os.unlink(l)
    for l in ls[1:]:
        shutil.copy2(t, l)
    os.rename(t, ls[0])

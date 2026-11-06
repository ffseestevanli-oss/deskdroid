#!/usr/bin/env python3
"""DeskDroid: the MIME type files for the desktop's data (share/mime).

KDE's app database (ksycoca) knows a MIME type only if
share/mime/<type>/<subtype>.xml exists, and only a type it knows can have
apps, defaults (mimeapps.list) or a remembered Open With choice. Without
them every file and folder asks which app to use, and choices don't stick.

The prefix's share/mime can't be shipped as it is: every KDE package that
installs a MIME package (kcoreaddons, Kate...) runs the build machine's
update-mime-database over it, which deletes the type files of every package
that isn't in packages/ (freedesktop.org.xml isn't: Qt has it built in). So
this writes them again at packaging time, after all of that:

  mime-types.py <out>/share/mime <freedesktop.org.xml> [<package.xml>...]

One small file per type from freedesktop.org.xml and the extra packages
(KDE's), which go to <out>/share/mime/packages too, for Qt to read. No
mime.cache: Qt reads the packages' XML and has freedesktop's built in.
"""
import shutil, sys, pathlib, xml.etree.ElementTree as ET

out = pathlib.Path(sys.argv[1])
fdo, extra = sys.argv[2], sys.argv[3:]
ns = "{http://www.freedesktop.org/standards/shared-mime-info}"
names = set()
for src in [fdo] + extra:
    for mt in ET.parse(src).getroot().iter(ns + "mime-type"):
        name = mt.get("type")
        if name and "/" in name:
            names.add(name)
for name in sorted(names):
    f = out / f"{name}.xml"
    f.parent.mkdir(parents=True, exist_ok=True)
    f.write_text(f'<?xml version="1.0" encoding="utf-8"?>\n<mime-type xmlns="{ns[1:-1]}" type="{name}"/>\n')
if extra:
    (out / "packages").mkdir(parents=True, exist_ok=True)
    for src in extra:
        shutil.copy(src, out / "packages" / pathlib.Path(src).name)
for must in ("inode/directory", "text/plain", "application/octet-stream", "image/png", "application/pdf"):
    if must not in names:
        sys.exit(f"mime-types.py: {must} is missing")
print(f"   mime: {len(names)} types ({len(extra)} extra packages)")

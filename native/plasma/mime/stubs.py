#!/usr/bin/env python3
"""DeskDroid: KDE's app database (ksycoca) knows a MIME type only if
share/mime/<type>/<subtype>.xml exists (update-mime-database's output), so
without them no app is found for any file. Qt keeps using its built-in
database (these files aren't one it reads), so they only need to exist:
write one small file per type in the given freedesktop.org.xml."""
import sys, pathlib, xml.etree.ElementTree as ET
src, out = sys.argv[1], pathlib.Path(sys.argv[2])
ns = "{http://www.freedesktop.org/standards/shared-mime-info}"
n = 0
for mt in ET.parse(src).getroot().iter(ns + "mime-type"):
    name = mt.get("type")
    if not name or "/" not in name:
        continue
    f = out / f"{name}.xml"
    f.parent.mkdir(parents=True, exist_ok=True)
    f.write_text(f'<?xml version="1.0" encoding="utf-8"?>\n<mime-type xmlns="http://www.freedesktop.org/standards/shared-mime-info" type="{name}"/>\n')
    n += 1
if n < 500:
    sys.exit(f"stubs.py: only {n} MIME types in {src}")
print(f"mime stubs: {n} types")

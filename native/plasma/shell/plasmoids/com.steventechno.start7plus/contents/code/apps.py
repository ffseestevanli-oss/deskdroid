#!/usr/bin/env python3
"""Scan .desktop files and print the application menu as JSON, grouped into Win7-style folders.
Works with system, user and Flatpak apps (used by the Win7 Start Menu plasmoid)."""
import glob, json, os, sys

home = os.path.expanduser("~")
data_home = os.environ.get("XDG_DATA_HOME") or os.path.join(home, ".local/share")
data_dirs = (os.environ.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share").split(":")
dirs = [data_home, os.path.join(home, ".local/share/flatpak/exports/share")] + data_dirs + \
       ["/var/lib/flatpak/exports/share", "/usr/share", "/usr/local/share"]

lang = (os.environ.get("LC_MESSAGES") or os.environ.get("LANGUAGE") or os.environ.get("LANG") or "").split(":")[0]
lang = lang.split(".")[0]
loc_keys = []
if lang and lang not in ("C", "POSIX"):
    loc_keys.append("Name[%s]" % lang)
    if "_" in lang:
        loc_keys.append("Name[%s]" % lang.split("_")[0])

FOLDERS = [  # (folder name, icon, desktop categories that map to it) - first match wins
    ("Settings",    "preferences-system",       {"Settings", "DesktopSettings", "HardwareSettings"}),
    ("Games",       "applications-games",       {"Game"}),
    ("Development", "applications-development", {"Development"}),
    ("Education",   "applications-education",   {"Education"}),
    ("Graphics",    "applications-graphics",    {"Graphics"}),
    ("Internet",    "applications-internet",    {"Network", "WebBrowser", "Email"}),
    ("Multimedia",  "applications-multimedia",  {"AudioVideo", "Audio", "Video"}),
    ("Office",      "applications-office",      {"Office"}),
    ("Science & Math", "applications-science",  {"Science", "Math"}),
    ("System",      "applications-system",      {"System"}),
    ("Utilities",   "applications-utilities",   {"Utility", "Accessibility"}),
]

def parse(path):
    d, inside = {}, False
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            for line in f:
                line = line.strip()
                if line.startswith("["):
                    inside = (line == "[Desktop Entry]")
                    continue
                if inside and "=" in line and not line.startswith("#"):
                    k, v = line.split("=", 1)
                    d.setdefault(k.strip(), v.strip())
    except OSError:
        return None
    return d

seen, apps = set(), []
for base in dirs:
    for path in sorted(glob.glob(os.path.join(base, "applications", "**", "*.desktop"), recursive=True)):
        rel = os.path.relpath(path, os.path.join(base, "applications")).replace("/", "-")
        if rel in seen:
            continue
        seen.add(rel)
        d = parse(path)
        if not d or d.get("Type") != "Application" or not d.get("Exec"):
            continue
        if d.get("NoDisplay", "").lower() == "true" or d.get("Hidden", "").lower() == "true":
            continue
        only = [x for x in d.get("OnlyShowIn", "").split(";") if x]
        notin = [x for x in d.get("NotShowIn", "").split(";") if x]
        if (only and "KDE" not in only) or "KDE" in notin:
            continue
        name = next((d[k] for k in loc_keys if k in d), d.get("Name", rel))
        icon = d.get("Icon", "application-x-executable")
        if icon.startswith("/"):
            icon = "file://" + icon
        cats = set(c for c in d.get("Categories", "").split(";") if c)
        folder = next((f for f in FOLDERS if cats & f[2]), None)
        kw = (d.get("GenericName", "") + " " + d.get("Keywords", "").replace(";", " ")).strip()
        apps.append((folder[0] if folder else "Other", name, icon, path, kw))

out = []
for fname, ficon, _ in FOLDERS + [("Other", "applications-other", set())]:
    items = sorted((a for a in apps if a[0] == fname), key=lambda a: a[1].lower())
    if items:
        out.append({"name": fname, "icon": ficon,
                    "apps": [{"id": os.path.basename(p), "name": n, "icon": i, "path": p, "kw": k} for _, n, i, p, k in items]})
out.sort(key=lambda f: (f["name"] == "Other", f["name"].lower()))
json.dump(out, sys.stdout, ensure_ascii=False)

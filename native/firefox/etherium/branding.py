#!/usr/bin/env python3
"""Makes Etherium, DeskDroid's browser: Firefox under its own name and icon
(a patched build can't carry Firefox's), with nothing phoning home and no
Google (Startpage searches).

    branding.py <firefox source dir>

Creates browser/branding/etherium from the unofficial branding: the names,
the icons (this folder's wave planet), and default preferences that turn off
everything Firefox sends to Mozilla or anyone else on its own (prefs.js).
"""
import json
import pathlib
import shutil
import struct
import sys

here = pathlib.Path(__file__).resolve().parent
src = pathlib.Path(sys.argv[1])
unofficial = src / "browser/branding/unofficial"
out = src / "browser/branding/etherium"
shutil.rmtree(out, ignore_errors=True)
shutil.copytree(unofficial, out)

# Names.
for rel in ("configure.sh", "locales/en-US/brand.ftl", "locales/en-US/brand.properties"):
    p = out / rel
    s = p.read_text().replace("Nightly", "Etherium").replace("nightlyunofficial", "etherium")
    if rel.endswith(".ftl"):
        s = s.replace("-brand-product-name = Firefox", "-brand-product-name = Etherium")
    p.write_text(s)

# Icons: each square PNG becomes the icon at its size (or the nearest
# larger one, which the page scales down); the logo and wordmark SVGs too.
sizes = sorted(int(p.stem.split("-")[1]) for p in here.glob("etherium-*.png"))
icons = 0
for p in out.rglob("*.png"):
    with open(p, "rb") as f:
        head = f.read(24)
    if head[:8] != b"\x89PNG\r\n\x1a\n":
        continue
    w, h = struct.unpack(">II", head[16:24])
    if w != h:
        continue
    size = next((s for s in sizes if s >= w), sizes[-1])
    shutil.copy(here / f"etherium-{size}.png", p)
    icons += 1
for p in out.rglob("*.svg"):
    if "wordmark" in p.name:
        shutil.copy(here / "wordmark.svg", p)
    elif "logo" in p.name:
        shutil.copy(here / "etherium.svg", p)

# Nothing phones home: Firefox's own defaults for this branding, which a
# user can still change in about:config.
prefs = out / "pref/firefox-branding.js"
prefs.write_text(prefs.read_text() + "\n" + (here / "prefs.js").read_text())

# No Google: the search engines Firefox ships with (the copy of Mozilla's
# search settings it falls back to, prefs.js keeping it from asking for
# newer ones) lose Google, and Startpage (Google's results, without Google
# seeing who asked) becomes the default everywhere, in private windows too,
# first in the list. DuckDuckGo, Wikipedia and the rest stay.
config = src / "services/settings/dumps/main/search-config-v2.json"
data = json.loads(config.read_text())
records = [r for r in data["data"]
           if not (r.get("recordType") == "engine" and r.get("identifier", "").startswith("google"))]
found = set()
for r in records:
    kind = r.get("recordType")
    if kind == "defaultEngines":
        r.update(globalDefault="startpage", globalDefaultPrivate="startpage", specificDefaults=[])
        found.add(kind)
    elif kind == "engineOrders":
        r["orders"] = [{"environment": {"allRegionsAndLocales": True}, "order": ["startpage", "ddg", "wikipedia*"]}]
        found.add(kind)
    elif r.get("identifier") == "startpage":
        r["variants"] = [{"environment": {"allRegionsAndLocales": True}}]
        found.add("startpage")
if found != {"defaultEngines", "engineOrders", "startpage"}:
    sys.exit(f"{config.relative_to(src)}: expected defaultEngines, engineOrders and startpage, found {sorted(found)}")
dropped = len(data["data"]) - len(records)
data["data"] = records
config.write_text(json.dumps(data, indent=2) + "\n")
print(f"etherium branding: {icons} icons, {prefs.relative_to(src)}, "
      f"{dropped} Google search engine(s) out, Startpage the default")

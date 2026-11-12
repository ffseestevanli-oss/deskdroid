#!/usr/bin/env python3
"""Installs an .adpk the way Store.kt's installZip does (ZipInputStream, no
file modes, ELF files in program/ executable, everything there read-only),
into a folder laid out like the phone's files folder.
  store-install.py <files dir> <apk lib dir> <pkg.adpk>"""
import json, os, shutil, stat, sys, zipfile
F, L, adpk = sys.argv[1:4]
root = os.path.join(F, "store/apps")
with zipfile.ZipFile(adpk) as z:
    meta = json.loads(z.read("app.json"))
    sid = meta["id"]
    d = os.path.join(root, sid)
    if os.path.exists(d):
        for r, ds, fs in os.walk(d):
            os.chmod(r, 0o755)
            for f in fs:
                p = os.path.join(r, f)
                if not os.path.islink(p): os.chmod(p, 0o644)
        shutil.rmtree(d)
    os.makedirs(os.path.join(d, "lib"))
    share = os.path.join(F, ".local/share")
    files = []
    for e in z.infolist():
        n = e.filename
        if n.endswith("/") or ".." in n: continue
        if n.startswith("lib/"): out = os.path.join(d, "lib", n[4:])
        elif n.startswith("program/") or n in ("program.txt", "program.env"): out = os.path.join(d, n)
        elif n.startswith("share/"): out = os.path.join(share, n[6:]); files.append(out)
        else: continue
        os.makedirs(os.path.dirname(out), exist_ok=True)
        with z.open(e) as src, open(out, "wb") as dst: shutil.copyfileobj(src, dst)
        if n.startswith("program/"):
            elf = open(out, "rb").read(4) == b"\x7fELF"
            os.chmod(out, 0o555 if elf else 0o444)
open(os.path.join(d, "files.txt"), "w").write("\n".join(files))
open(os.path.join(d, "version.txt"), "w").write(meta.get("version", ""))
open(os.path.join(d, "app.txt"), "w").write(sid)
cmd = os.path.join(F, "kwin/bin", sid)
if not os.path.lexists(cmd): os.symlink(os.path.join(L, "libdd_store-program.so"), cmd)
print("installed", sid, meta.get("version"))

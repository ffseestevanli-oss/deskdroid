#!/usr/bin/env python3
"""
Makes DeskDroid store packages (.adpk) from Flathub's ARM64 builds, so an app
installs from a file and runs without the flatpak command or Flathub on the
phone. See README.md next to this script.

  flathub-adpk.py app     <flatpak dir> <flatpak id> <store id> <runtime pkg> <out.adpk> [--name N] [--summary S]
                          [--ext <extension ref>,... [--ext-keep <folder>,...]]
  flathub-adpk.py runtime <flatpak dir> <ref> <store id> <out.adpk> --name N --summary S
  flathub-adpk.py mesa    <flatpak dir> <branch> <store id> <out.adpk>

<flatpak dir> is a `flatpak --user` installation with the refs installed for
aarch64. A package is the store's "program" kind (Store.kt):

  program.txt          bin/ddapp, the launcher (ddapp.c, a bionic program)
  program.env          DDAPP_RUN and DDAPP_PROGRAM
  program/run.sh       starts the app as `flatpak run` would (run.sh.in)
  program/files/       the app's /app (or the runtime's /usr)
  program/layout.txt   what a zip unpacked by the store can't carry: links
                       (and hard links), execute bits of scripts, empty
                       folders; ddapp lays it out on the first start
  share/               menu entries and icons (apps only)

--ext puts Flathub extensions the app declares ([Extension ...] in its
metadata: EasyEffects' LV2 plugins) inside the app's package, where Flatpak
would mount them, with the folders Flatpak merges (merge-dirs) as links and
their add-ld-path folders on the library path; --ext-keep keeps only those
top folders of each extension (lv2,lib: not the VST, CLAP, LADSPA copies).
"""
import hashlib, io, json, os, re, stat, subprocess, sys, zipfile, configparser

HERE = os.path.dirname(os.path.abspath(__file__))
STORE = "/S"  # stands for files/store/apps when working out relative links
TRIPLE = "aarch64-linux-gnu"


def esc(s):
    return s.replace("%", "%25").replace(" ", "%20").replace("\n", "%0A")


class Pkg:
    def __init__(self, sid):
        self.sid = sid
        self.entries = []  # (zip name, bytes or path, mode)
        self.layout = []
        self.mounts = []  # (absolute prefix, package-relative folder or (other pkg, folder))
        self.elfs = []

    def add_tree(self, src, dest, skip=lambda rel: False):
        """src's files at program/<dest>. Links and duplicate inodes go to layout."""
        seen = {}
        for root, dirs, files in os.walk(src):
            dirs.sort(); files.sort()
            relroot = os.path.relpath(root, src)
            relroot = "" if relroot == "." else relroot
            keep_dirs = []
            for d in dirs:
                rel = os.path.join(relroot, d)
                full = os.path.join(root, d)
                if skip(rel):
                    continue
                if os.path.islink(full):
                    files.append(d)  # handled as a link below
                else:
                    keep_dirs.append(d)
                    if not os.listdir(full):
                        self.layout.append(("D", os.path.join(dest, rel)))
            dirs[:] = keep_dirs
            for f in files:
                rel = os.path.join(relroot, f)
                if skip(rel):
                    continue
                full = os.path.join(root, f)
                at = os.path.join(dest, rel)
                st = os.lstat(full)
                if stat.S_ISLNK(st.st_mode):
                    self.layout.append(("L", at, self.fix_target(at, os.readlink(full))))
                    continue
                if not stat.S_ISREG(st.st_mode):
                    continue
                key = (st.st_dev, st.st_ino)
                if key in seen:
                    self.layout.append(("L", at, os.path.relpath(seen[key], os.path.dirname(at))))
                    continue
                if ".." in at or not self.zip_safe(at):
                    # The store skips names with "..": keep it under another name.
                    stored = ".dd/" + hashlib.sha1(at.encode("utf-8", "surrogateescape")).hexdigest()
                    self.entries.append(("program/" + stored, full, st.st_mode))
                    self.layout.append(("L", at, os.path.relpath(stored, os.path.dirname(at))))
                    seen[key] = stored
                    continue
                seen[key] = at
                self.entries.append(("program/" + at, full, st.st_mode))
                with open(full, "rb") as fh:
                    elf = fh.read(4) == b"\x7fELF"
                if elf:
                    self.elfs.append(full)
                elif st.st_mode & 0o111:
                    self.layout.append(("X", at))

    @staticmethod
    def zip_safe(name):
        try:
            name.encode("utf-8")
            return True
        except UnicodeEncodeError:
            return False

    def fix_target(self, at, target):
        """Absolute targets name sandbox paths (/app, /usr...): make them relative."""
        if not target.startswith("/"):
            return target
        for prefix, where in sorted(self.mounts, key=lambda m: -len(m[0])):
            if target == prefix or target.startswith(prefix + "/"):
                rest = target[len(prefix):].lstrip("/")
                if isinstance(where, tuple):
                    pkg, folder = where
                else:
                    pkg, folder = self.sid, where
                real = os.path.join(STORE, pkg, "program", folder, rest)
                here = os.path.join(STORE, self.sid, "program", os.path.dirname(at))
                return os.path.relpath(real, here)
        return target

    def libdirs(self, prefixes, extra=()):
        """Absolute RUNPATH/RPATH folders of the ELF files under the given
        sandbox prefixes ({"/app": "APP", "/usr": "RT"}): glibc's loader opens
        them itself, where ddflatpak can't map them, so run.sh adds the real
        folders to the library path instead."""
        dirs = []
        for i in range(0, len(self.elfs), 200):
            out = subprocess.run(["readelf", "-dW"] + self.elfs[i:i + 200], capture_output=True, text=True).stdout
            for m in re.finditer(r"\((?:RUNPATH|RPATH)\)\s+Library r(?:un)?path: \[(.*)\]", out):
                for d in m.group(1).split(":"):
                    for pre, var in prefixes.items():
                        if d == pre or d.startswith(pre + "/"):
                            v = var + ":" + d[len(pre):].lstrip("/")
                            if v not in dirs:
                                dirs.append(v)
        dirs += [d for d in extra if d not in dirs]
        self.add_bytes("program/libdirs.txt", "".join(d + "\n" for d in dirs))
        return dirs

    def add_bytes(self, name, data, mode=0o644):
        self.entries.append((name, data if isinstance(data, bytes) else data.encode(), mode))

    def write(self, out, meta):
        self.add_bytes("program/layout.txt", "".join(" ".join(esc(x) for x in l) + "\n" for l in self.layout))
        os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
        tmp = out + ".part"
        with zipfile.ZipFile(tmp, "w", zipfile.ZIP_DEFLATED, compresslevel=6, allowZip64=True) as z:
            def put(name, data, mode):
                zi = zipfile.ZipInfo(name, (1980, 1, 1, 0, 0, 0))
                zi.compress_type = zipfile.ZIP_DEFLATED
                zi.external_attr = (stat.S_IFREG | (mode & 0o777)) << 16
                if isinstance(data, bytes):
                    z.writestr(zi, data)
                else:
                    with open(data, "rb") as src, z.open(zi, "w", force_zip64=os.path.getsize(data) > 0x7fffffff) as dst:
                        while True:
                            b = src.read(1 << 20)
                            if not b:
                                break
                            dst.write(b)
            put("app.txt", (self.sid + "\n").encode(), 0o644)
            put("app.json", json.dumps(meta, indent=1).encode(), 0o644)
            for name, data, mode in sorted(self.entries, key=lambda e: (not e[0].startswith(("program.", "program/bin", "program/run")), e[0])):
                put(name, data, mode)
        os.replace(tmp, out)
        print(f"{out}: {os.path.getsize(out) / 1e6:.1f} MB, {len(self.entries)} files, {len(self.layout)} layout lines")


def launcher(pkg, run_sh):
    pkg.add_bytes("program.txt", "bin/ddapp\n")
    pkg.add_bytes("program.env", "DDAPP_RUN=@PROGRAM@/run.sh\nDDAPP_PROGRAM=@PROGRAM@\n")
    with open(os.environ.get("DDAPP_BIN", os.path.join(HERE, "ddapp")), "rb") as f:
        pkg.add_bytes("program/bin/ddapp", f.read(), 0o755)
    pkg.add_bytes("program/run.sh", run_sh, 0o755)


def flatpak_info(fpdir, ref):
    env = dict(os.environ, FLATPAK_USER_DIR=fpdir)
    out = subprocess.run(["flatpak", "info", "--user", ref], capture_output=True, text=True, env=env).stdout
    info = {}
    for line in out.splitlines():
        m = re.match(r"\s*([A-Za-z ]+):\s*(.*)", line)
        if m:
            info.setdefault(m.group(1).strip(), m.group(2).strip())
    return info


def deploy(fpdir, kind, ref):
    return os.path.realpath(os.path.join(fpdir, kind, ref, "active"))


def desktop_entries(files, fpid):
    d = os.path.join(files, "share/applications")
    if not os.path.isdir(d):
        return []
    return sorted(os.path.join(d, f) for f in os.listdir(d) if f.endswith(".desktop") and f.startswith(fpid))


def rewrite_desktop(text, sid, cmd):
    out = []
    for line in text.splitlines():
        key = line.split("=", 1)[0].strip()
        if key in ("DBusActivatable", "TryExec") or key.startswith("X-Flatpak"):
            continue
        if key == "Exec":
            args = line.split("=", 1)[1].split()
            args = [a for a in args if a not in ("@@", "@@u")]
            prog = os.path.basename(args[0]) if args else cmd
            extra = [] if prog == cmd else ["--dd-command=" + prog]
            line = "Exec=" + " ".join([sid] + extra + args[1:])
        out.append(line)
    return "\n".join(out) + "\n"


def extensions(pkg, fpdir, meta, refs, keep):
    """The extensions in refs inside the app's files (Flatpak mounts them at
    /app/<directory>); returns their add-ld-path folders for libdirs.txt."""
    secs = {s[len("Extension "):]: meta[s] for s in meta.sections() if s.startswith("Extension ")}
    libs, placed = [], []
    for ref in refs:
        ext = ref.split("/")[0]
        sec = secs.get(ext)
        if sec is None:
            sys.exit(f"{ext}: not an extension the app declares")
        where = sec["directory"].strip("/")
        src = os.path.join(deploy(fpdir, "runtime", ref), "files")
        pkg.add_tree(src, "files/" + where,
                     skip=lambda rel: bool(keep) and rel.split("/")[0] not in keep and rel != "manifest.json")
        for p in sec.get("add-ld-path", "").split(";"):
            if p and (not keep or p.split("/")[0] in keep):
                libs.append(f"APP:{where}/{p}")
        placed.append((where, src))
    # merge-dirs: an extension point with subdirectories gets each merged
    # folder (lv2) with links to what its extensions have there.
    for sec in secs.values():
        top = sec["directory"].strip("/")
        if sec.get("subdirectories") != "true":
            continue
        for md in [m for m in sec.get("merge-dirs", "").split(";") if m]:
            for where, src in placed:
                if os.path.dirname(where) != top or not os.path.isdir(os.path.join(src, md)):
                    continue
                for entry in sorted(os.listdir(os.path.join(src, md))):
                    pkg.layout.append(("L", f"files/{top}/{md}/{entry}", f"../{os.path.basename(where)}/{md}/{entry}"))
    return libs


def app(fpdir, fpid, sid, rtpkg, out, name=None, summary=None, exts=None, keep=None):
    ref = f"{fpid}/aarch64/stable"
    d = deploy(fpdir, "app", ref)
    files = os.path.join(d, "files")
    meta = configparser.ConfigParser(interpolation=None, strict=False)
    meta.optionxform = str
    meta.read(os.path.join(d, "metadata"))
    cmd = meta["Application"]["command"]
    runtime = meta["Application"]["runtime"]
    info = flatpak_info(fpdir, f"app/{ref}")
    pkg = Pkg(sid)
    pkg.mounts = [("/app", "files"), ("/usr", (rtpkg, "files"))]
    # Flatpak's own build leftovers and the parts only Flatpak reads.
    pkg.add_tree(files, "files", skip=lambda rel: rel.startswith(("share/runtime/", "lib/debug", "include", "lib/pkgconfig")))
    with open(os.path.join(d, "metadata"), "rb") as f:
        pkg.add_bytes("program/metadata", f.read())
    extra = extensions(pkg, fpdir, meta, exts or [], keep)
    pkg.libdirs({"/app": "APP", "/usr": "RT"}, extra)
    with open(os.path.join(HERE, "run.sh.in")) as f:
        run = f.read()
    for k, v in {"@SID@": sid, "@FPID@": fpid, "@CMD@": cmd, "@RTPKG@": rtpkg, "@RUNTIME@": runtime}.items():
        run = run.replace(k, v)
    launcher(pkg, run)
    # Menu entries, icons, metainfo: what Flatpak exports, pointed at the store command.
    entries = desktop_entries(files, fpid)
    icon_names = {fpid}
    for e in entries:
        with open(e, encoding="utf-8") as f:
            text = f.read()
        for m in re.finditer(r"^Icon=(.+)$", text, re.M):
            icon_names.add(m.group(1).strip())
        pkg.add_bytes("share/applications/" + os.path.basename(e), rewrite_desktop(text, sid, cmd))
        if name is None:
            m = re.search(r"^Name=(.+)$", text, re.M); name = m.group(1) if m else sid
        if summary is None:
            m = re.search(r"^(GenericName|Comment)=(.+)$", text, re.M); summary = m.group(2) if m else ""
    icons = os.path.join(files, "share/icons/hicolor")
    have_png = False
    svg = None
    for root, _, fs in os.walk(icons):
        for f in fs:
            base = f.rsplit(".", 1)[0]
            if base.removesuffix("-symbolic") not in icon_names and not base.startswith(fpid):
                continue
            full = os.path.join(root, f)
            rel = os.path.relpath(full, icons)
            data = open(os.path.realpath(full), "rb").read()
            pkg.add_bytes("share/icons/hicolor/" + rel, data)
            if f.endswith(".png") and "/apps" in "/" + rel:
                have_png = True
            if f.endswith(".svg") and rel.startswith("scalable/apps/") and base in icon_names and not base.endswith("-symbolic"):
                svg = (full, base)
    if not have_png and svg:
        png = subprocess.run(["rsvg-convert", "-w", "128", "-h", "128", svg[0]], capture_output=True).stdout
        if png:
            pkg.add_bytes(f"share/icons/hicolor/128x128/apps/{svg[1]}.png", png)
    for sub in ("metainfo", "appdata"):
        md = os.path.join(files, "share", sub)
        for ext in (".metainfo.xml", ".appdata.xml"):
            p = os.path.join(md, fpid + ext)
            if os.path.exists(p):
                pkg.add_bytes(f"share/metainfo/{fpid}.metainfo.xml", open(p, "rb").read())
                break
    version = info.get("Version") or info.get("Commit", "")[:12]
    pkg.write(out, {"id": sid, "name": name or sid, "summary": summary or "", "version": version,
                    "flatpak": fpid, "commit": info.get("Commit", ""), "runtime": runtime,
                    "needs": [rtpkg, "runtime-mesa-25.08"]})


RUNTIME_RUN = """#!/system/bin/sh
echo "@NAME@ is a runtime: it has no window of its own. Apps from Flathub that need it use it." >&2
exit 0
"""


def runtime(fpdir, ref, sid, out, name, summary):
    d = deploy(fpdir, "runtime", ref)
    info = flatpak_info(fpdir, "runtime/" + ref)
    pkg = Pkg(sid)
    pkg.mounts = [("/usr", "files")]
    pkg.add_tree(os.path.join(d, "files"), "files", skip=lambda rel: rel.startswith(("lib/debug", "share/runtime/locale")))
    pkg.libdirs({"/usr": "RT"})
    with open(os.path.join(d, "metadata"), "rb") as f:
        pkg.add_bytes("program/metadata", f.read())
    launcher(pkg, RUNTIME_RUN.replace("@NAME@", name))
    pkg.write(out, {"id": sid, "name": name, "summary": summary,
                    "version": info.get("Version") or ref.split("/")[-1] + "+" + info.get("Commit", "")[:8],
                    "flatpak": ref, "commit": info.get("Commit", "")})


GL_SKIP = re.compile(r"^(lib/libRusticlOpenCL|lib/libclang-cpp|lib/libLLVMSPIRVLib|lib/libteflon|lib/aarch64-linux-gnu/clang|OpenCL/vendors/rusticl"
                     r"|lib/libvulkan_(?!lvp)|vulkan/icd\.d/(?!lvp))")


def mesa(fpdir, branch, sid, out):
    gl = f"org.freedesktop.Platform.GL.default/aarch64/{branch}"
    cx = f"org.freedesktop.Platform.codecs-extra/aarch64/{branch}-extra"
    pkg = Pkg(sid)
    pkg.mounts = [(f"/usr/lib/{TRIPLE}/GL/default", "gl"), (f"/usr/lib/{TRIPLE}/GL", "gl"),
                  (f"/usr/lib/{TRIPLE}/codecs-extra", "codecs-extra")]
    pkg.add_tree(os.path.join(deploy(fpdir, "runtime", gl), "files"), "gl", skip=lambda rel: bool(GL_SKIP.match(rel)))
    pkg.add_tree(os.path.join(deploy(fpdir, "runtime", cx), "files"), "codecs-extra")
    launcher(pkg, RUNTIME_RUN.replace("@NAME@", "Mesa and codecs"))
    i1, i2 = flatpak_info(fpdir, "runtime/" + gl), flatpak_info(fpdir, "runtime/" + cx)
    pkg.write(out, {"id": sid, "name": f"Mesa and codecs {branch}", "summary": "Graphics drivers and video codecs for Flathub apps",
                    "version": f"{branch}+{i1.get('Commit', '')[:8]}", "flatpak": [gl, cx]})


def opts(args):
    o, rest = {}, []
    it = iter(args)
    for a in it:
        if a.startswith("--"):
            o[a[2:]] = next(it)
        else:
            rest.append(a)
    return o, rest


if __name__ == "__main__":
    o, a = opts(sys.argv[1:])
    if a[0] == "app":
        app(*a[1:6], name=o.get("name"), summary=o.get("summary"),
            exts=[e for e in o.get("ext", "").split(",") if e], keep=[k for k in o.get("ext-keep", "").split(",") if k])
    elif a[0] == "runtime":
        runtime(*a[1:5], name=o["name"], summary=o["summary"])
    elif a[0] == "mesa":
        mesa(*a[1:5])
    else:
        sys.exit(__doc__)

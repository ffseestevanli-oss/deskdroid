#!/usr/bin/env python3
"""Lists the Debian packages (arm64) the flatpak command needs, as URLs.

debs.py <Packages file> <mirror> <package>...

Follows Depends and Pre-Depends from the named packages, minus what
DeskDroid gives Flatpak apps itself or what can't work on Android anyway
(SKIP): glibc (native/glibc), the sandbox (bubblewrap, xdg-dbus-proxy:
ddflatpak runs apps without it), system services and package scripts.
Prints "<url> <sha256>" per package.
"""
import re
import sys

SKIP = {
    "libc6", "libc-bin", "libc-l10n", "locales", "bubblewrap", "xdg-dbus-proxy", "fuse3", "adduser",
    "debconf", "debconf-2.0", "cdebconf", "base-files", "base-passwd", "dpkg", "init-system-helpers",
    "systemd", "systemd-sysv", "dbus", "dbus-daemon", "dbus-system-bus", "dbus-bin", "dbus-session-bus",
    "default-dbus-session-bus", "polkitd", "perl-base", "sensible-utils", "mount", "util-linux",
    "login", "passwd", "libpam-modules", "libpam-runtime", "lsb-base", "sysvinit-utils",
    "tzdata", "media-types", "netbase", "readline-common", "dconf-service", "gpg-agent", "pinentry-curses",
    "dirmngr", "gnupg-l10n", "gpg-wks-client", "gpgsm",
}


def parse(path):
    pkgs, cur = {}, {}
    key = None
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            line = line.rstrip("\n")
            if not line:
                if "Package" in cur:
                    pkgs.setdefault(cur["Package"], cur)
                cur, key = {}, None
            elif line[0] in " \t":
                if key:
                    cur[key] += " " + line.strip()
            else:
                key, _, val = line.partition(":")
                cur[key] = val.strip()
    if "Package" in cur:
        pkgs.setdefault(cur["Package"], cur)
    return pkgs


def main():
    pkgs = parse(sys.argv[1])
    mirror = sys.argv[2].rstrip("/")
    provides = {}
    for name, p in pkgs.items():
        for prov in p.get("Provides", "").split(","):
            prov = re.sub(r"\(.*?\)", "", prov).strip()
            if prov:
                provides.setdefault(prov, name)
    want, todo = [], list(sys.argv[3:])
    seen = set()
    while todo:
        name = todo.pop(0)
        if name in seen or name in SKIP:
            continue
        seen.add(name)
        p = pkgs.get(name) or pkgs.get(provides.get(name, ""))
        if not p:
            sys.exit(f"debs.py: no package {name}")
        if p["Package"] != name:
            if p["Package"] in seen:
                continue
            seen.add(p["Package"])
        want.append(p)
        deps = ", ".join(x for x in (p.get("Pre-Depends", ""), p.get("Depends", "")) if x)
        for alt in deps.split(","):
            alt = alt.strip()
            if not alt:
                continue
            # "a | b": the first one there is (or already wanted).
            choices = [re.sub(r"\(.*?\)|\[.*?\]|:any", "", c).strip() for c in alt.split("|")]
            if any(c in seen or c in SKIP for c in choices):
                continue
            todo.append(next((c for c in choices if c in pkgs or c in provides), choices[0]))
    for p in want:
        print(f"{mirror}/{p['Filename']} {p['SHA256']}")


main()

#!/usr/bin/env python3
"""Print two lines: the distro's NAME and PRETTY_NAME from os-release."""
import os

def read(path):
    out = {}
    try:
        with open(path) as f:
            for line in f:
                line = line.strip()
                if "=" not in line or line.startswith("#"):
                    continue
                k, v = line.split("=", 1)
                out[k] = v.strip().strip('"').strip("'")
    except OSError:
        pass
    return out

d = {}
for p in ("/etc/os-release", "/usr/lib/os-release"):
    d = read(p)
    if d:
        break
name = d.get("NAME") or d.get("ID") or "Linux"
print(name)
print(d.get("PRETTY_NAME") or name)

#!/usr/bin/env python3
"""Lists the files a set of programs and modules needs, from an unpacked tree.

closure.py <root> <triple> <file>...

Follows each ELF file's NEEDED libraries through the tree's library folders
(and the extra folders in $CLOSURE_DIRS, ':'-separated, relative to root),
leaving out glibc's own libraries, which DeskDroid brings (native/glibc).
Prints the files by the names they were asked for (a library by its NEEDED
name, not the file a symlink leads to), relative to root; names it can't find
go to stderr and make it fail.
"""
import os
import re
import subprocess
import sys

root, triple, starts = sys.argv[1], sys.argv[2], sys.argv[3:]
GLIBC = re.compile(r"^(libc|libm|libpthread|libdl|librt|libresolv|libutil|libanl|libmvec|ld-linux-[a-z0-9_-]+)\.so")
dirs = [f"usr/lib/{triple}", f"lib/{triple}", "usr/lib"] + [d for d in os.environ.get("CLOSURE_DIRS", "").split(":") if d]


def needed(p):
    out = subprocess.run(["readelf", "-d", p], capture_output=True, text=True).stdout
    return re.findall(r"\(NEEDED\).*\[(.+)\]", out)


seen, names, missing = set(), [], set()
todo = [os.path.join(root, s) for s in starts]
while todo:
    asked = todo.pop()
    p = os.path.realpath(asked)
    if p in seen:
        continue
    seen.add(p)
    names.append(asked)
    for n in needed(p):
        if GLIBC.match(n):
            continue
        for d in dirs:
            c = os.path.join(root, d, n)
            if os.path.exists(c):
                todo.append(c)
                break
        else:
            missing.add(n)
for s in sorted(names):
    print(os.path.relpath(s, root))
for m in sorted(missing):
    print(f"closure.py: {m} not found", file=sys.stderr)
sys.exit(1 if missing else 0)

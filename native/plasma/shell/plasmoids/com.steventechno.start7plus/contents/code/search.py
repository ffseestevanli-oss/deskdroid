#!/usr/bin/env python3
"""Search file and folder names inside the user's home directory.
Usage: search.py "words to find"  ->  JSON {"query": ..., "files": [{"name","path","dir"}]}
Hidden files/folders are skipped, and the search stops after ~2 seconds."""
import json, os, sys, time

query = sys.argv[1] if len(sys.argv) > 1 else ""
terms = query.lower().split()
home = os.path.expanduser("~")
SKIP = {"node_modules", "__pycache__", "site-packages", "venv", ".venv"}
MAX_DEPTH = 8
LIMIT_COLLECT = 300
LIMIT_RETURN = 25

found = []
if terms:
    deadline = time.time() + 2.0
    for root, dirs, files in os.walk(home, followlinks=False):
        dirs[:] = [d for d in dirs if not d.startswith(".") and d not in SKIP]
        if root[len(home):].count(os.sep) >= MAX_DEPTH:
            dirs[:] = []
        for name in dirs + files:
            if name.startswith("."):
                continue
            low = name.lower()
            if all(t in low for t in terms):
                found.append((name, os.path.join(root, name)))
        if len(found) >= LIMIT_COLLECT or time.time() > deadline:
            break

def rank(item):
    low = item[0].lower()
    starts = 0 if low.startswith(terms[0]) else 1
    return (starts, len(low), low)

found.sort(key=rank) if terms else None
out = [{"name": n, "path": p, "dir": os.path.isdir(p)} for n, p in found[:LIMIT_RETURN]]
json.dump({"query": query, "files": out}, sys.stdout, ensure_ascii=False)

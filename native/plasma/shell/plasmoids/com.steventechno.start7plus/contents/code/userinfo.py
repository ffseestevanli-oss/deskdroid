#!/usr/bin/env python3
"""Print two lines: the user's display name and the path of their account picture (or empty)."""
import getpass, os, pwd, re, subprocess

user = getpass.getuser()
try:
    name = pwd.getpwnam(user).pw_gecos.split(",")[0].strip()
except Exception:
    name = ""
print(name or user)

def ok(p):
    try:
        return bool(p) and os.path.isfile(p) and os.path.getsize(p) > 0
    except OSError:
        return False

home = os.path.expanduser("~")
found = ""
for c in (os.path.join(home, ".face.icon"), os.path.join(home, ".face")):
    if ok(c):
        found = c
        break
if not found:
    try:
        out = subprocess.run(
            ["busctl", "--system", "get-property", "org.freedesktop.Accounts",
             "/org/freedesktop/Accounts/User%d" % os.getuid(),
             "org.freedesktop.Accounts.User", "IconFile"],
            capture_output=True, text=True, timeout=3).stdout
        m = re.match(r'^s "(.*)"', out.strip())
        if m and ok(m.group(1)):
            found = m.group(1)
    except Exception:
        pass
if not found:
    c = "/var/lib/AccountsService/icons/" + user
    if ok(c):
        found = c
print(found)

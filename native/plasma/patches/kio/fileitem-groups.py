#!/usr/bin/env python3
"""Lock emblems on files the app can read and write.

(Second part, at the end: local files ask access() instead.)

KFileItem decides whether a file is readable/writable from its owner and
group: for a file owned by someone else, it asks whether the user is in the
file's group through KUser::groups() (getgrouplist). Bionic only reports the
user's own group there, not the groups Android gives the app's process
(everybody, ext_data_rw...), which own shared storage's files; so every file
in /storage looked unreadable and got the lock emblem. Ask the process's own
groups (getgroups) instead."""
import sys
p = sys.argv[1] + "/src/core/kfileitem.cpp"
t = open(p).read()
old = "KUser(currentUser).groups().contains(KUserGroup(gidOfItem))"
assert t.count(old) == 2, "group checks"
t = t.replace(old, "deskdroidInGroup(gidOfItem)")
anchor = "#include <KShell>\n"
assert t.count(anchor) == 1, "includes"
t = t.replace(anchor, anchor + """#include <unistd.h>
#include <vector>

// The groups this process is in, as Android gave them (see above).
static bool deskdroidInGroup(gid_t gid)
{
    if (getegid() == gid) {
        return true;
    }
    const int n = getgroups(0, nullptr);
    if (n <= 0) {
        return false;
    }
    std::vector<gid_t> groups(n);
    const int got = getgroups(n, groups.data());
    for (int i = 0; i < got; ++i) {
        if (groups[i] == gid) {
            return true;
        }
    }
    return false;
}
""", 1)
# Shared storage (/storage/emulated, a FUSE file system) reports owners and
# groups the app's process doesn't match even with its real groups, so for
# local files ask the kernel (access(), through QFileInfo) instead of
# guessing from owner, group and mode.
old = "        const auto uidOfItem = userId();\n"
assert t.count(old) == 2, "uid checks"
t = t.replace(old, "        const auto uidOfItem = d->m_bIsLocalUrl ? -1 : userId();\n")
open(p, "w").write(t)

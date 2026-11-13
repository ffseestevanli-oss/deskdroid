#!/usr/bin/env python3
"""The user's name: the one DeskDroid gives, not Android's "u0_a123".

Bionic names the app's account after its uid (u0_a123) and has no full name,
so Kickoff, Start 7 Plus and the logout screen showed "u0_a123". For the
app's own uid, KUser's login and full name are DESKDROID_USER_NAME (the
app sets it: Android's name for the user, or "DeskDroid")."""
import sys
p = sys.argv[1] + "/src/lib/util/kuser_unix.cpp"
t = open(p).read()
old = """            loginName = QString::fromLocal8Bit(p->pw_name);
            properties[KUser::FullName] = QVariant(gecosList[0]);
"""
assert t.count(old) == 1, "fillPasswd changed"
t = t.replace(old, old + """#ifdef __BIONIC__
            if (uid == ::getuid()) { // DeskDroid
                QString name = QString::fromUtf8(qgetenv("DESKDROID_USER_NAME")).trimmed();
                if (name.isEmpty()) {
                    name = QStringLiteral("DeskDroid");
                }
                loginName = name;
                properties[KUser::FullName] = QVariant(name);
            }
#endif
""")
open(p, "w").write(t)

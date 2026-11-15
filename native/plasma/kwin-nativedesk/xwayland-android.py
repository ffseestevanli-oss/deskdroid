#!/usr/bin/env python3
"""KWin's Xwayland support on Android (build_kwin, KWIN_BUILD_X11=ON).

- Its lock files and socket file go in $XDG_RUNTIME_DIR (Android has no /tmp);
  the abstract socket keeps its usual name (@/tmp/.X11-unix/X<n>), which X
  clients try first, so DISPLAY=:<n> reaches it from any app.
- The X server is $KWIN_XWAYLAND when set: DeskDroid's xwayland.sh, which runs
  flatpak-cli's glibc Xwayland with its paths (native/flatpak/xwayland.sh).
"""
import sys

src = sys.argv[1]


def patch(rel, old, new, count=1):
    p = f"{src}/{rel}"
    s = open(p).read()
    assert s.count(old) == count, f"{rel}: {old[:60]!r} found {s.count(old)} times"
    open(p, "w").write(s.replace(old, new))


sock = "src/xwayland/lib/xwaylandsocket.cpp"
patch(sock, 'return QStringLiteral("/tmp/.X%1-lock").arg(display);',
      'return xDir() + QStringLiteral("/.X%1-lock").arg(display);')
patch(sock, '''static QString socketFileNameForDisplay(int display)
{
    return QStringLiteral("/tmp/.X11-unix/X%1").arg(display);
}''', '''static QString socketFileNameForDisplay(int display)
{
    return xDir() + QStringLiteral("/.X11-unix/X%1").arg(display);
}

// DeskDroid: the abstract socket's name, as X clients look for it.
static QString abstractNameForDisplay(int display)
{
    return QStringLiteral("/tmp/.X11-unix/X%1").arg(display);
}''')
patch(sock, 'static QString lockFileNameForDisplay(int display)', '''// DeskDroid: where the lock files and socket files go (no /tmp on Android).
static QString xDir()
{
    return qEnvironmentVariable("XDG_RUNTIME_DIR", QStringLiteral("/tmp"));
}

static QString lockFileNameForDisplay(int display)''')
patch(sock, '''static bool checkSocketsDirectory()
{''', '''static bool checkSocketsDirectory()
{
    // DeskDroid: the app's own folder, made here; no root-owned sticky /tmp.
    const QByteArray dir = QFile::encodeName(xDir() + QStringLiteral("/.X11-unix"));
    if (mkdir(dir.constData(), 0700) == 0 || errno == EEXIST) {
        return true;
    }
    qCWarning(KWIN_XWL, "Failed to make %s: %s", dir.constData(), strerror(errno));
    return false;''')
patch(sock, 'const int abstractFileDescriptor = listen_helper(socketFilePath, UnixSocketAddress::Type::Abstract, mode);',
      'const int abstractFileDescriptor = listen_helper(abstractNameForDisplay(display), UnixSocketAddress::Type::Abstract, mode);')

patch("src/xwayland/xwaylandlauncher.cpp",
      'm_xwaylandProcess->setProgram(QStandardPaths::findExecutable("Xwayland"));',
      'm_xwaylandProcess->setProgram(qEnvironmentVariableIsSet("KWIN_XWAYLAND") ? qEnvironmentVariable("KWIN_XWAYLAND") : QStandardPaths::findExecutable("Xwayland"));')

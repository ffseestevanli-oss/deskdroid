#!/usr/bin/env python3
"""Moving and copying files on the phone's shared storage.

Android's shared storage (/storage/emulated/N) is a FUSE file system run by
the MediaProvider app, which decides every rename and every new file itself.
It sometimes refuses a rename into another folder (EACCES or EPERM) that it
allows a little later, notably right after the target folder was made, while
making a new file there works. The file worker then reported "Access denied"
and the move stopped.

On shared storage, the worker now:
- retries a refused rename or a refused new file for a moment;
- if the rename is still refused, reports it as unsupported, so the copy job
  moves the file by copying it and deleting the original (as it does between
  drives);
- logs each refusal with its error, so DeskDroid's log shows what Android did.
And Dolphin no longer refuses a drop, Paste or move into a folder there
on its own (see the second part, at the end).
"""
import sys

p = sys.argv[1] + "/src/kioworkers/file/file_unix.cpp"
t = open(p).read()

anchor = "WorkerResult FileProtocol::copy(const QUrl &srcUrl, const QUrl &destUrl, int _mode, JobFlags _flags)\n"
assert t.count(anchor) == 1, "copy()"
t = t.replace(anchor, r'''// DeskDroid: see native/plasma/patches/kio/file-shared-storage.py.
static bool deskdroidOnSharedStorage(const QByteArray &path)
{
    return path.startsWith("/storage/") || path.startsWith("/sdcard/");
}

// Calls op() until it succeeds or fails with something other than EACCES or
// EPERM, for about 1.5 s on shared storage (once elsewhere). Returns op()'s
// last result, with errno as op() left it.
template<typename Op>
static int deskdroidRetryRefused(const char *what, const QByteArray &path, Op op)
{
    int r = op();
    if (r != -1 || !deskdroidOnSharedStorage(path)) {
        return r;
    }
    int err = errno;
    int tries = 1;
    while ((err == EACCES || err == EPERM) && tries < 16) {
        QThread::msleep(100);
        ++tries;
        r = op();
        if (r != -1) {
            qCWarning(KIO_FILE) << "deskdroid: Android allowed" << what << path << "after" << tries << "tries";
            return r;
        }
        err = errno;
    }
    qCWarning(KIO_FILE) << "deskdroid: Android refused" << what << path << "after" << tries << "tries:" << strerror(err);
    errno = err;
    return r;
}

''' + anchor, 1)

# New file in copy(): retry a refused open before giving up.
old = "    QFile destFile(dest);\n    if (!destFile.open(QIODevice::Truncate | QIODevice::WriteOnly)) {\n"
assert t.count(old) == 1, "copy dest open"
t = t.replace(old, """    QFile destFile(dest);
    if (deskdroidRetryRefused("making", _dest, [&] {
            return destFile.open(QIODevice::Truncate | QIODevice::WriteOnly) ? 0 : -1;
        }) == -1) {
""")

# rename(): retry, then let the copy job copy and delete instead.
old = """    if (::rename(_src.data(), _dest.data()) == -1) {
        auto result = execWithElevatedPrivilege(RENAME, {_src, _dest}, errno);"""
assert t.count(old) == 1, "rename"
t = t.replace(old, """    if (deskdroidRetryRefused("moving to", _dest, [&] {
            return ::rename(_src.data(), _dest.data());
        }) == -1) {
        if ((errno == EACCES || errno == EPERM) && (deskdroidOnSharedStorage(_src) || deskdroidOnSharedStorage(_dest))) {
            qCWarning(KIO_FILE) << "deskdroid: moving" << _src << "by copying it and deleting the original";
            return WorkerResult::fail(KIO::ERR_UNSUPPORTED_ACTION, QStringLiteral("rename"));
        }
        auto result = execWithElevatedPrivilege(RENAME, {_src, _dest}, errno);""")

for inc in ("#include <QThread>\n", "#include <cstring>\n"):
    if inc not in t:
        first = t.index("#include ")
        t = t[:first] + inc + t[first:]
open(p, "w").write(t)

# Dolphin checks writability itself before it asks the worker: the drop
# (KIO::DropJob), Paste and the copy job's look at the target folder all go
# by KFileItem::isWritable() or the folder's mode bits. On shared storage
# those come from Android's file system and say nothing reliable about what
# MediaProvider will allow, so there the operation itself decides.
src = sys.argv[1] + "/src/core/kfileitem.cpp"
t = open(src).read()
old = """bool KFileItem::isWritable() const
{
    if (!d) {
        return false;
    }

    d->ensureInitialized();
"""
assert t.count(old) == 1, "isWritable"
t = t.replace(old, old + """
    // DeskDroid: see native/plasma/patches/kio/file-shared-storage.py.
    if (d->m_bIsLocalUrl && d->m_url.toLocalFile().startsWith(QLatin1String("/storage/emulated/"))) {
        return QFileInfo::exists(d->m_url.toLocalFile());
    }
""")
open(src, "w").write(t)

src = sys.argv[1] + "/src/core/copyjob.cpp"
t = open(src).read()
old = "            const bool isWritable = (permissions != -1) && (permissions & S_IWUSR);\n"
assert t.count(old) == 1, "copyjob writable"
t = t.replace(old, """            const bool isWritable = ((permissions != -1) && (permissions & S_IWUSR))
                || (m_dest.isLocalFile() && m_dest.toLocalFile().startsWith(QLatin1String("/storage/emulated/"))); // DeskDroid
""")
open(src, "w").write(t)

// DeskDroid x11-shim (README.md): the part of libXcursor the Cursors page
// uses, reading Xcursor files and themes without X11.
#include <X11/Xcursor/Xcursor.h>

#include <QByteArray>
#include <QDir>
#include <QFile>
#include <QRegularExpression>
#include <QSet>
#include <QStringList>
#include <QtEndian>

#include <cstdlib>
#include <cstring>

namespace
{
constexpr uint32_t imageType = 0xfffd0002;

uint32_t u32(const QByteArray &d, qsizetype at)
{
    return at + 4 <= d.size() ? qFromLittleEndian<uint32_t>(d.constData() + at) : 0;
}

struct Toc {
    uint32_t size;
    uint32_t position;
};

// The image entries of an Xcursor file, or none if it isn't one.
QList<Toc> readToc(const QByteArray &d)
{
    QList<Toc> toc;
    if (d.size() < 16 || !d.startsWith("Xcur")) {
        return toc;
    }
    const uint32_t header = u32(d, 4);
    const uint32_t n = u32(d, 12);
    for (uint32_t i = 0; i < n && i < 0x10000; ++i) {
        const qsizetype at = header + i * 12;
        if (at + 12 > d.size()) {
            break;
        }
        if (u32(d, at) == imageType) {
            toc.append({u32(d, at + 4), u32(d, at + 8)});
        }
    }
    return toc;
}

XcursorImage *readImage(const QByteArray &d, uint32_t pos)
{
    const uint32_t header = u32(d, pos);
    if (header < 36 || u32(d, pos + 4) != imageType) {
        return nullptr;
    }
    const uint32_t w = u32(d, pos + 16), h = u32(d, pos + 20);
    if (w == 0 || h == 0 || w > 0x7fff || h > 0x7fff || pos + header + qsizetype(w) * h * 4 > d.size()) {
        return nullptr;
    }
    auto *img = static_cast<XcursorImage *>(std::malloc(sizeof(XcursorImage) + size_t(w) * h * 4));
    img->version = u32(d, pos + 12);
    img->size = u32(d, pos + 8);
    img->width = w;
    img->height = h;
    img->xhot = u32(d, pos + 24);
    img->yhot = u32(d, pos + 28);
    img->delay = u32(d, pos + 32);
    img->pixels = reinterpret_cast<XcursorPixel *>(img + 1);
    const char *src = d.constData() + pos + header;
    for (size_t i = 0; i < size_t(w) * h; ++i) {
        img->pixels[i] = qFromLittleEndian<uint32_t>(src + i * 4);
    }
    return img;
}

XcursorImages *newImages(const QList<XcursorImage *> &list)
{
    if (list.isEmpty()) {
        return nullptr;
    }
    auto *images = static_cast<XcursorImages *>(std::malloc(sizeof(XcursorImages)));
    images->nimage = list.size();
    images->images = static_cast<XcursorImage **>(std::malloc(sizeof(XcursorImage *) * list.size()));
    images->name = nullptr;
    for (int i = 0; i < list.size(); ++i) {
        images->images[i] = list[i];
    }
    return images;
}

// All images of the nominal size nearest to size (all sizes when size is 0).
XcursorImages *loadFile(const QString &path, int size)
{
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly)) {
        return nullptr;
    }
    const QByteArray d = f.readAll();
    const QList<Toc> toc = readToc(d);
    uint32_t best = 0;
    if (size > 0) {
        for (const Toc &t : toc) {
            if (best == 0 || std::abs(int(t.size) - size) < std::abs(int(best) - size)) {
                best = t.size;
            }
        }
    }
    QList<XcursorImage *> list;
    for (const Toc &t : toc) {
        if (size > 0 && t.size != best) {
            continue;
        }
        if (XcursorImage *img = readImage(d, t.position)) {
            list.append(img);
        }
    }
    return newImages(list);
}

QStringList searchPath()
{
    QStringList dirs = QString::fromLocal8Bit(XcursorLibraryPath()).split(u':', Qt::SkipEmptyParts);
    for (QString &d : dirs) {
        if (d.startsWith(u"~/")) {
            d = QDir::homePath() + d.mid(1);
        }
    }
    return dirs;
}

QStringList inherits(const QString &theme)
{
    for (const QString &dir : searchPath()) {
        QFile f(dir + u'/' + theme + QStringLiteral("/index.theme"));
        if (!f.open(QIODevice::ReadOnly)) {
            continue;
        }
        bool inGroup = false;
        while (!f.atEnd()) {
            const QString line = QString::fromUtf8(f.readLine()).trimmed();
            if (line.startsWith(u'[')) {
                inGroup = line == u"[Icon Theme]";
            } else if (inGroup && line.startsWith(u"Inherits")) {
                const qsizetype eq = line.indexOf(u'=');
                if (eq > 0 && line.left(eq).trimmed() == u"Inherits") {
                    QStringList list = line.mid(eq + 1).split(QRegularExpression(QStringLiteral("[;,]")), Qt::SkipEmptyParts);
                    for (QString &s : list) {
                        s = s.trimmed();
                    }
                    return list;
                }
            }
        }
        return {};
    }
    return {};
}

QString findCursor(const QString &theme, const QString &name, QSet<QString> &seen)
{
    if (theme.isEmpty() || seen.contains(theme) || seen.size() > 32) {
        return {};
    }
    seen.insert(theme);
    for (const QString &dir : searchPath()) {
        const QString path = dir + u'/' + theme + QStringLiteral("/cursors/") + name;
        if (QFile::exists(path)) {
            return path;
        }
    }
    for (const QString &parent : inherits(theme)) {
        const QString path = findCursor(parent, name, seen);
        if (!path.isEmpty()) {
            return path;
        }
    }
    return {};
}
} // namespace

XcursorImages *XcursorFilenameLoadAllImages(const char *file)
{
    return file ? loadFile(QFile::decodeName(file), 0) : nullptr;
}

XcursorImages *XcursorLibraryLoadImages(const char *name, const char *theme, int size)
{
    if (!name || !*name) {
        return nullptr;
    }
    QSet<QString> seen;
    QString path = findCursor(QFile::decodeName(theme ? theme : "default"), QFile::decodeName(name), seen);
    if (path.isEmpty() && (!theme || std::strcmp(theme, "default") != 0)) {
        path = findCursor(QStringLiteral("default"), QFile::decodeName(name), seen);
    }
    return path.isEmpty() ? nullptr : loadFile(path, size > 0 ? size : 24);
}

XcursorImage *XcursorLibraryLoadImage(const char *name, const char *theme, int size)
{
    XcursorImages *images = XcursorLibraryLoadImages(name, theme, size);
    if (!images) {
        return nullptr;
    }
    XcursorImage *first = images->images[0];
    for (int i = 1; i < images->nimage; ++i) {
        std::free(images->images[i]);
    }
    std::free(images->images);
    std::free(images);
    return first;
}

void XcursorImageDestroy(XcursorImage *image)
{
    std::free(image);
}

void XcursorImagesDestroy(XcursorImages *images)
{
    if (!images) {
        return;
    }
    for (int i = 0; i < images->nimage; ++i) {
        std::free(images->images[i]);
    }
    std::free(images->images);
    std::free(images->name);
    std::free(images);
}

// XCURSOR_PATH (DeskDroid sets it for KWin and the desktop), else libXcursor's
// default: ~/.icons, then icons in each XDG data folder.
const char *XcursorLibraryPath(void)
{
    static QByteArray path;
    if (path.isEmpty()) {
        if (const char *env = std::getenv("XCURSOR_PATH"); env && *env) {
            path = env;
        } else {
            QStringList dirs{QStringLiteral("~/.icons")};
            const QByteArray home = qgetenv("XDG_DATA_HOME");
            dirs << (home.isEmpty() ? QStringLiteral("~/.local/share") : QFile::decodeName(home)) + QStringLiteral("/icons");
            QByteArray data = qgetenv("XDG_DATA_DIRS");
            if (data.isEmpty()) {
                data = "/usr/local/share:/usr/share";
            }
            for (const QString &d : QFile::decodeName(data).split(u':', Qt::SkipEmptyParts)) {
                dirs << d + QStringLiteral("/icons");
            }
            path = QFile::encodeName(dirs.join(u':'));
        }
    }
    return path.constData();
}

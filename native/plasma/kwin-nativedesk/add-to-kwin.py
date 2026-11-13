#!/usr/bin/env python3
"""Adds the nativedesk backend to a KWin source tree: copies the backend in as
src/backends/nativedesk, gives kwin_wayland a --nativedesk option, and builds
kwin_wayland as a library that DeskDroid's QtHost starts (qthost_entry.cpp)."""
import pathlib
import shutil
import sys

here = pathlib.Path(__file__).resolve().parent
kwin = pathlib.Path(sys.argv[1])

dest = kwin / "src/backends/nativedesk"
dest.mkdir(parents=True, exist_ok=True)
for f in ("CMakeLists.txt", "nativedesk_backend.h", "nativedesk_backend.cpp", "deskdroid_ahb_server.h", "deskdroid_ahb_server.cpp",
          "nativedesk_bridge.h", "nativedesk_bridge.cpp"):
    shutil.copy(here / f, dest / f)
shutil.copy(here.parent.parent / "nativedesk/protocol.h", dest / "protocol.h")
shutil.copy(here.parent / "ahb/deskdroid_ahb.h", dest / "deskdroid_ahb.h")


def edit(path, old, new):
    p = kwin / path
    s = p.read_text()
    if s.count(old) != 1:
        sys.exit(f"{path}: expected one '{old.strip()}'")
    p.write_text(s.replace(old, new))


# Every app here is /system/bin/app_process, so KWin can't tell plasmashell
# by its program for the interfaces only Plasma may use (the task manager's
# window list): plasmashell is the process QtHost started with its library.
ws = "src/wayland_server.cpp"
edit(ws, '#include "wayland_server.h"\n', '#include "wayland_server.h"\n#include <QFile>\n')
edit(ws, "        static bool permissionCheckDisabled = ",
     "        { // DeskDroid\n"
     "            QFile cmdline(QStringLiteral(\"/proc/%1/cmdline\").arg(client->processId()));\n"
     "            if (cmdline.open(QIODevice::ReadOnly) && cmdline.readAll().split('\\0').contains(QByteArrayLiteral(\"libplasmashell.so\"))) {\n"
     "                return true;\n"
     "            }\n"
     "        }\n"
     "        static bool permissionCheckDisabled = ")

# The same for each window's program name (its resource name, which effects
# and window rules go by: the Scale effect leaves plasmashell's popups to the
# Sliding Popups effect by it): the library QtHost runs, not app_process.
edit("src/waylandwindow.cpp",
     "        const QByteArray executableFileName = fileInfo.fileName().toUtf8();\n",
     "        QByteArray executableFileName = fileInfo.fileName().toUtf8();\n"
     "        if (executableFileName.startsWith(\"app_process\")) { // DeskDroid: QtHost's library\n"
     "            QFile cmdline(QStringLiteral(\"/proc/%1/cmdline\").arg(surface()->client()->processId()));\n"
     "            if (cmdline.open(QIODevice::ReadOnly)) {\n"
     "                for (const QByteArray &arg : cmdline.readAll().split('\\0')) {\n"
     "                    const QByteArray name = arg.mid(arg.lastIndexOf('/') + 1);\n"
     "                    if (name.startsWith(\"lib\") && name.endsWith(\".so\") && !name.startsWith(\"libdd_\")) {\n"
     "                        executableFileName = name.mid(3, name.size() - 6);\n"
     "                        break;\n"
     "                    }\n"
     "                }\n"
     "            }\n"
     "        }\n")
edit("src/waylandwindow.cpp", "#include \"waylandwindow.h\"\n", "#include \"waylandwindow.h\"\n#include <QFile>\n")

# Plasma's popups (Kickoff, the calendar...) reach KWin here as plain,
# borderless plasmashell windows, without the applet-popup role or the slide
# request Plasma makes on a desktop: they opened with no animation, and closed
# like any window (Fall Apart, when it was on). Sliding Popups now slides them
# from their panel's edge itself, as on a desktop; it takes their close
# animation as soon as they open, so the window close effects leave them.
sp = "src/plugins/slidingpopups/slidingpopups.cpp"
edit(sp, "void SlidingPopupsEffect::setupSlideData(EffectWindow *w)\n{\n",
     "// DeskDroid: a plasmoid's popup, whatever role Plasma managed to give it.\n"
     "static bool deskdroidIsPlasmoidPopup(EffectWindow *w)\n"
     "{\n"
     "    return w->isAppletPopup()\n"
     "        || (w->isNormalWindow() && !w->hasDecoration() && w->windowClass().endsWith(QLatin1String(\" org.kde.plasmashell\")));\n"
     "}\n\n"
     "// DeskDroid: the screen edge of the panel nearest the popup (its applet's\n"
     "// panel), or else the screen edge nearest it.\n"
     "static int deskdroidPopupEdge(EffectWindow *w)\n"
     "{\n"
     "    enum { Left, Top, Right, Bottom };\n"
     "    const QRectF screen = effects->clientArea(FullScreenArea, w->screen(), effects->currentDesktop());\n"
     "    const QRectF popup = w->frameGeometry();\n"
     "    auto edgeOf = [&screen](const QRectF &r) {\n"
     "        const qreal d[] = {r.left() - screen.left(), r.top() - screen.top(), screen.right() - r.right(), screen.bottom() - r.bottom()};\n"
     "        return int(std::min_element(std::begin(d), std::end(d)) - std::begin(d));\n"
     "    };\n"
     "    EffectWindow *panel = nullptr;\n"
     "    qreal best = 0;\n"
     "    const auto windows = effects->stackingOrder();\n"
     "    for (EffectWindow *dock : windows) {\n"
     "        if (!dock->isDock() || dock->isDeleted() || !dock->isVisible() || dock->screen() != w->screen()) {\n"
     "            continue;\n"
     "        }\n"
     "        const QRectF g = dock->frameGeometry();\n"
     "        const qreal dx = std::max<qreal>({0, g.left() - popup.right(), popup.left() - g.right()});\n"
     "        const qreal dy = std::max<qreal>({0, g.top() - popup.bottom(), popup.top() - g.bottom()});\n"
     "        const qreal distance = std::hypot(dx, dy);\n"
     "        if (!panel || distance < best) {\n"
     "            panel = dock;\n"
     "            best = distance;\n"
     "        }\n"
     "    }\n"
     "    if (!panel) {\n"
     "        return edgeOf(popup);\n"
     "    }\n"
     "    // A panel spans its edge: a wide one is at the top or bottom, a tall one at a side.\n"
     "    const QRectF g = panel->frameGeometry();\n"
     "    if (g.width() >= g.height()) {\n"
     "        return g.center().y() < screen.center().y() ? Top : Bottom;\n"
     "    }\n"
     "    return g.center().x() < screen.center().x() ? Left : Right;\n"
     "}\n\n"
     "void SlidingPopupsEffect::setupSlideData(EffectWindow *w)\n{\n")
edit(sp, "    if (auto internal = w->internalWindow()) {\n        internal->installEventFilter(this);\n        setupInternalWindowSlide(w);\n    }\n}\n",
     "    if (auto internal = w->internalWindow()) {\n        internal->installEventFilter(this);\n        setupInternalWindowSlide(w);\n    }\n\n"
     "    if (!m_animationsData.contains(w) && deskdroidIsPlasmoidPopup(w)) { // DeskDroid\n"
     "        static const Location locations[] = {Location::Left, Location::Top, Location::Right, Location::Bottom};\n"
     "        AnimationData &animData = m_animationsData[w];\n"
     "        animData.location = locations[deskdroidPopupEdge(w)];\n"
     "        animData.offset = -1; // from the screen edge to the popup, as Plasma asks\n"
     "        animData.slideLength = 0;\n"
     "        animData.slideInDuration = m_slideInDuration;\n"
     "        animData.slideOutDuration = m_slideOutDuration;\n"
     "        setupAnimData(w);\n"
     "    }\n"
     "}\n")
edit(sp, '#include "slidingpopups.h"\n', '#include "slidingpopups.h"\n#include <algorithm>\n#include <cmath>\n')

# Dodge display cutouts:the backend learns which edges the camera cutout and
# rounded corners hide (deskdroidSafeMargins); panels are laid out inside
# what's left, left and right only. Maximized windows and the wallpaper
# (exclusive zone -1) still reach every edge.
decl = "#include <QMargins>\nnamespace KWin { class Output; QMargins deskdroidSafeMargins(const Output *output); }\n"
ls = "src/layershellv1integration.cpp"
edit(ls, '#include "layershellv1integration.h"\n', '#include "layershellv1integration.h"\n' + decl)
edit(ls, "        QRect workArea = output->geometry();\n",
     "        QRect workArea = output->geometry().marginsRemoved(deskdroidSafeMargins(output)); // DeskDroid\n")

# Windows dodge the cutouts too, in landscape only (where the camera cutout
# and rounded corners are at the sides): what maximized windows and window
# placement get is the screen less the panels' margins (deskdroidWindowMargins,
# 0 in portrait or with dodging off).
ws = "src/workspace.cpp"
edit(ws, '#include "workspace.h"\n',
     '#include "workspace.h"\n#include <QMargins>\n'
     'namespace KWin { class Output; QMargins deskdroidWindowMargins(const Output *output); }\n')
edit(ws, "            screenAreas[desktop][output] = output->geometryF();\n",
     "            screenAreas[desktop][output] = output->geometryF().marginsRemoved(deskdroidWindowMargins(output)); // DeskDroid\n")

edit("src/backends/CMakeLists.txt", "add_subdirectory(virtual)", "add_subdirectory(virtual)\nadd_subdirectory(nativedesk)")
m = "src/main_wayland.cpp"
edit(m, '#include "backends/virtual/virtual_backend.h"\n',
     '#include "backends/virtual/virtual_backend.h"\n#include "backends/nativedesk/nativedesk_backend.h"\n')
edit(m, "    parser.addOption(virtualFbOption);\n",
     "    parser.addOption(virtualFbOption);\n"
     "    QCommandLineOption nativeDeskOption(QStringLiteral(\"nativedesk\"), QStringLiteral(\"Show the desktop on DeskDroid's Android compositor.\"));\n"
     "    parser.addOption(nativeDeskOption);\n")
edit(m, "        Virtual,\n    };", "        Virtual,\n        NativeDesk,\n    };")
edit(m, "    } else if (parser.isSet(virtualFbOption)) {\n",
     "    } else if (parser.isSet(nativeDeskOption)) {\n"
     "        backendType = BackendType::NativeDesk;\n"
     "    } else if (parser.isSet(virtualFbOption)) {\n")
edit(m, "    case BackendType::Virtual: {\n",
     "    case BackendType::NativeDesk:\n"
     "        a.setSession(KWin::Session::create(KWin::Session::Type::Noop));\n"
     "        a.setOutputBackend(std::make_unique<KWin::NativeDeskBackend>(initialWindowSize, outputScale));\n"
     "        break;\n"
     "    case BackendType::Virtual: {\n")

# The phone's keyboard follows text fields: KWin's input method decides here
# whether the focused surface has an enabled text input; the backend hears it,
# with the field's purpose and hints (a password field gets no suggestions).
edit("src/inputmethod.cpp", "    if (m_internalContext->isEnabled()) {\n        active = true;\n    }\n    setActive(active);\n",
     "    if (m_internalContext->isEnabled()) {\n        active = true;\n    }\n"
     "    deskdroidReport(active);\n    setActive(active);\n")
edit("src/inputmethod.cpp", "void InputMethod::contentTypeChanged()\n{\n",
     "void InputMethod::contentTypeChanged()\n{\n    deskdroidReport(deskdroidActive);\n")
# The field's text around the cursor goes to the phone's keyboard too: it
# corrects and moves the cursor through what's really there.
edit("src/inputmethod.cpp", "void InputMethod::surroundingTextChanged()\n{\n",
     "void InputMethod::surroundingTextChanged()\n{\n    deskdroidSurrounding();\n")
edit("src/inputmethod.cpp", '#include "inputmethod.h"\n', '#include "inputmethod.h"\n#include <QDebug>\n')
edit("src/inputmethod.cpp", "namespace KWin\n{\n",
     "namespace KWin\n{\n"
     "void (*deskdroidTextInputHook)(bool, int, int) = nullptr;\n"
     "void (*deskdroidSurroundingHook)(const QString &, int, int) = nullptr;\n"
     "static bool deskdroidActive = false;\n"
     "static bool deskdroidTold = false; // the field's first text was logged\n"
     "static void deskdroidSurrounding()\n"
     "{\n"
     "    if (!deskdroidSurroundingHook) {\n"
     "        return;\n"
     "    }\n"
     "    auto seat = waylandServer()->seat();\n"
     "    QString text;\n"
     "    qint32 cursor = 0, anchor = 0;\n"
     "    if (auto t3 = seat->textInputV3(); t3 && t3->isEnabled()) {\n"
     "        text = t3->surroundingText();\n"
     "        cursor = t3->surroundingTextCursorPosition();\n"
     "        anchor = t3->surroundingTextSelectionAnchor();\n"
     "    } else if (auto t2 = seat->textInputV2(); t2 && t2->isEnabled()) {\n"
     "        text = t2->surroundingText();\n"
     "        cursor = t2->surroundingTextCursorPosition();\n"
     "        anchor = t2->surroundingTextSelectionAnchor();\n"
     "    } else {\n"
     "        return;\n"
     "    }\n"
     "    // UTF-8 byte offsets to UTF-16 indices (Android's).\n"
     "    const QByteArray utf8 = text.toUtf8();\n"
     "    auto index = [&utf8](qint32 b) {\n"
     "        return int(QString::fromUtf8(utf8.left(std::clamp<qint32>(b, 0, utf8.size()))).size());\n"
     "    };\n"
     "    deskdroidSurroundingHook(text, index(cursor), index(anchor));\n"
     "}\n"
     "static void deskdroidReport(bool active)\n"
     "{\n"
     "    if (!deskdroidTextInputHook) {\n"
     "        return;\n"
     "    }\n"
     "    int purpose = 0, hints = 0;\n"
     "    const char *via = \"none\";\n"
     "    auto seat = waylandServer()->seat();\n"
     "    if (auto t3 = seat->textInputV3(); t3 && t3->isEnabled()) {\n"
     "        purpose = int(t3->contentPurpose());\n"
     "        hints = t3->contentHints().toInt();\n"
     "        via = \"text-input-v3\";\n"
     "    } else if (auto t2 = seat->textInputV2(); t2 && t2->isEnabled()) {\n"
     "        purpose = int(t2->contentPurpose());\n"
     "        hints = t2->contentHints().toInt();\n"
     "        via = \"text-input-v2\";\n"
     "    } else if (auto t1 = seat->textInputV1(); t1 && t1->isEnabled()) {\n"
     "        purpose = int(t1->contentPurpose());\n"
     "        hints = t1->contentHints().toInt();\n"
     "        via = \"text-input-v1\";\n"
     "    }\n"
     "    if (active != deskdroidActive) {\n"
     "        deskdroidTold = false;\n"
     "        qInfo(\"nativedesk: text field %s (%s, purpose %d, hints %#x)\", active ? \"focused\" : \"left\", via, purpose, hints);\n"
     "    }\n"
     "    deskdroidActive = active;\n"
     "    deskdroidTextInputHook(active, purpose, hints);\n"
     "    if (active) {\n"
     "        deskdroidSurrounding();\n"
     "    }\n"
     "}\n")

# Text from the phone's keyboard (swipe typing, corrections, suggestions): the
# backend hands KWin's input method the words it commits and the word being
# composed, which go to the focused app over Wayland text-input like an input
# method's (an app without text input gets the committed text as key presses).
edit("src/inputmethod.h", "    void setActive(bool active);\n",
     "    void setActive(bool active);\n"
     "    void deskdroidText(int kind, const QString &text, int cursor); // DeskDroid\n")
edit("src/inputmethod.cpp", "void InputMethod::commitString(qint32 serial, const QString &text)\n{\n",
     "void InputMethod::deskdroidText(int kind, const QString &text, int cursor)\n"
     "{\n"
     "    if (kind == 1) { // commit\n"
     "        if (!deskdroidTold) {\n"
     "            deskdroidTold = true;\n"
     "            auto seat = waylandServer()->seat();\n"
     "            qInfo(\"nativedesk: first phone keyboard text: v1 %d, v2 %d, v3 %d, internal %d (none: as keys)\",\n"
     "                  seat->textInputV1()->isEnabled(), seat->textInputV2()->isEnabled(), seat->textInputV3()->isEnabled(), m_internalContext->isEnabled());\n"
     "        }\n"
     "        commitString(m_serial++, text);\n"
     "        return;\n"
     "    }\n"
     "    // The word being composed, underlined in the field; the cursor in UTF-8 bytes.\n"
     "    cursor = std::clamp(cursor, 0, int(text.size()));\n"
     "    const int bytes = text.left(cursor).toUtf8().size();\n"
     "    auto seat = waylandServer()->seat();\n"
     "    if (auto t1 = seat->textInputV1(); t1 && t1->isEnabled()) {\n"
     "        t1->setPreEditCursor(bytes);\n"
     "        t1->preEdit(text, QString());\n"
     "    } else if (auto t2 = seat->textInputV2(); t2 && t2->isEnabled()) {\n"
     "        t2->setPreEditCursor(bytes);\n"
     "        t2->preEdit(text, QString());\n"
     "    } else if (auto t3 = seat->textInputV3(); t3 && t3->isEnabled()) {\n"
     "        t3->sendPreEditString(text, bytes, bytes);\n"
     "        t3->done();\n"
     "    } else if (m_internalContext->isEnabled()) {\n"
     "        m_internalContext->handlePreeditText(text, cursor, cursor);\n"
     "    }\n"
     "}\n\n"
     "void InputMethod::commitString(qint32 serial, const QString &text)\n{\n")

# Apps that draw with the GPU hand KWin their buffers (deskdroid_ahb_v1):
# KWin takes them as wl_buffers and samples them as textures.
edit("src/wayland/display.cpp", '#include "singlepixelbuffer.h"\n',
     '#include "singlepixelbuffer.h"\n#include "backends/nativedesk/deskdroid_ahb_server.h"\n')
edit("src/wayland/display.cpp", "    } else if (auto buffer = SinglePixelClientBuffer::get(resource)) {\n        return buffer;\n",
     "    } else if (auto buffer = SinglePixelClientBuffer::get(resource)) {\n        return buffer;\n"
     "    } else if (auto buffer = AhbClientBuffer::get(resource)) {\n        return buffer;\n")
si = "src/scene/surfaceitem.cpp"
edit(si, '#include "utils/common.h"\n', '#include "utils/common.h"\n#include "backends/nativedesk/deskdroid_ahb_server.h"\n')
edit(si, "bool OpenGLSurfaceTexture::create()\n{\n",
     "// DeskDroid: an app's GPU buffer, sampled where it is.\n"
     "static bool deskdroidBindAhb(EglBackend *backend, AhbClientBuffer *ahb, OpenGLSurfaceContents &contents)\n"
     "{\n"
     "    EGLImageKHR image = ahb->image(backend->eglDisplayObject());\n"
     "    if (image == EGL_NO_IMAGE_KHR) {\n"
     "        return false;\n"
     "    }\n"
     "    if (contents.planes.count() != 1 || contents.planes[0]->size() != ahb->size()) {\n"
     "        auto texture = std::make_shared<GLTexture>(GL_TEXTURE_2D);\n"
     "        texture->setSize(ahb->size());\n"
     "        if (!texture->create()) {\n"
     "            return false;\n"
     "        }\n"
     "        texture->setWrapMode(GL_CLAMP_TO_EDGE);\n"
     "        texture->setFilter(GL_LINEAR);\n"
     "        contents = OpenGLSurfaceContents(texture);\n"
     "    }\n"
     "    contents.planes[0]->bind();\n"
     "    glEGLImageTargetTexture2DOES(GL_TEXTURE_2D, static_cast<GLeglImageOES>(image));\n"
     "    contents.planes[0]->unbind();\n"
     "    contents.planes[0]->setContentTransform(ahb->yInverted() ? OutputTransform::Normal : OutputTransform::FlipY);\n"
     "    return true;\n"
     "}\n\n"
     "bool OpenGLSurfaceTexture::create()\n{\n"
     "    if (auto ahb = AhbClientBuffer::from(m_pixmap->item()->buffer())) {\n"
     "        m_texture.reset();\n"
     "        m_bufferType = BufferType::None;\n"
     "        return deskdroidBindAhb(m_backend, ahb, m_texture);\n"
     "    }\n")
edit(si, "void OpenGLSurfaceTexture::update(const QRegion &region)\n{\n",
     "void OpenGLSurfaceTexture::update(const QRegion &region)\n{\n"
     "    if (auto ahb = AhbClientBuffer::from(m_pixmap->item()->buffer())) {\n"
     "        if (m_bufferType != BufferType::None) {\n"
     "            destroy();\n"
     "        }\n"
     "        deskdroidBindAhb(m_backend, ahb, m_texture);\n"
     "        return;\n"
     "    }\n")

# No DRM device here (the GPU is reached through Android's EGL): KWin's GL
# path asks the render backend's DRM device about sync objects and PCI ids.
edit("src/wayland_server.cpp", "    if (backend->drmDevice()->supportsSyncObjTimelines()) {",
     "    if (backend->drmDevice() && backend->drmDevice()->supportsSyncObjTimelines()) {")
edit("src/compositor.cpp", "    if (const auto pciInfo = backend->drmDevice()->pciDeviceInfo()) {",
     "    if (const auto pciInfo = backend->drmDevice() ? backend->drmDevice()->pciDeviceInfo() : std::optional<drmPciDeviceInfo>()) {")

# kwin_wayland as a library with a JNI entry point, since Qt for Android needs
# a Java VM: QtHost loads it into an app_process and calls QtHost.run().
edit("src/CMakeLists.txt", "add_executable(kwin_wayland main_wayland.cpp)",
     "add_library(kwin_wayland SHARED main_wayland.cpp)\n"
     "set_target_properties(kwin_wayland PROPERTIES CXX_VISIBILITY_PRESET default)")
edit(m, "int main(int argc, char *argv[])", "int kwinMain(int argc, char *argv[])")
p = kwin / m
p.write_text(p.read_text() + "\n" + (here / "qthost_entry.cpp").read_text())

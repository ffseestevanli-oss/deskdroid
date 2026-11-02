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
for f in ("CMakeLists.txt", "nativedesk_backend.h", "nativedesk_backend.cpp", "deskdroid_ahb_server.h", "deskdroid_ahb_server.cpp"):
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

# Dodge display cutouts: the backend learns which edges the camera cutout and
# rounded corners hide (deskdroidSafeMargins); panels are laid out, and
# maximized windows sized, inside what's left. The wallpaper (exclusive zone
# -1) still covers the whole screen.
decl = "#include <QMargins>\nnamespace KWin { class Output; QMargins deskdroidSafeMargins(const Output *output); }\n"
ls = "src/layershellv1integration.cpp"
edit(ls, '#include "layershellv1integration.h"\n', '#include "layershellv1integration.h"\n' + decl)
edit(ls, "        QRect workArea = output->geometry();\n",
     "        QRect workArea = output->geometry().marginsRemoved(deskdroidSafeMargins(output)); // DeskDroid\n")
wsp = "src/workspace.cpp"
edit(wsp, '#include "workspace.h"\n', '#include "workspace.h"\n' + decl)
edit(wsp, "        workAreas[desktop] = m_geometry;\n\n        for (const Output *output : std::as_const(m_outputs)) {\n            screenAreas[desktop][output] = output->geometryF();\n        }\n",
     "        workAreas[desktop] = m_outputs.size() == 1 ? QRectF(m_geometry).marginsRemoved(QMarginsF(deskdroidSafeMargins(m_outputs.first()))) : QRectF(m_geometry); // DeskDroid\n\n"
     "        for (const Output *output : std::as_const(m_outputs)) {\n"
     "            screenAreas[desktop][output] = output->geometryF().marginsRemoved(QMarginsF(deskdroidSafeMargins(output))); // DeskDroid\n"
     "        }\n")

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
# whether the focused surface has an enabled text input; the backend hears it.
edit("src/inputmethod.cpp", "    if (m_internalContext->isEnabled()) {\n        active = true;\n    }\n    setActive(active);\n",
     "    if (m_internalContext->isEnabled()) {\n        active = true;\n    }\n"
     "    if (deskdroidTextInputHook) {\n        deskdroidTextInputHook(active);\n    }\n    setActive(active);\n")
edit("src/inputmethod.cpp", "namespace KWin\n{\n", "namespace KWin\n{\nvoid (*deskdroidTextInputHook)(bool) = nullptr;\n")

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

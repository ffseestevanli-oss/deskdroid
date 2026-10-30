/*
 * "deskdroid" Qt platform plugin: puts Qt windows on the nativedesk compositor
 * (../compositor.c) through ../protocol.h. This is how Qt, and so KDE, would
 * run natively on Android without the Java side of Qt's own Android plugin.
 *
 * Each window is one connection to the compositor with three AHardwareBuffers.
 * Raster windows (QPainter in software) are copied into a buffer on flush;
 * OpenGL windows render straight into the buffers through EGLImage-backed
 * framebuffers, and Qt sees them as the window's default framebuffer. Frames
 * are paced by the compositor: requestUpdate() waits for its FRAME event.
 */
#include <android/hardware_buffer.h>
#include <dlfcn.h>
#include <poll.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

#define EGL_EGLEXT_PROTOTYPES
#define GL_GLEXT_PROTOTYPES
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES3/gl3.h>
#include <GLES2/gl2ext.h>

#include <QtCore/QMetaObject>
#include <QtCore/QSocketNotifier>
#include <QtCore/private/qeventdispatcher_unix_p.h>
#include <QtGui/QImage>
#include <QtGui/QOpenGLContext>
#include <QtGui/QWindow>
#include <QtGui/private/qfreetypefontdatabase_p.h>
#include <qpa/qplatformbackingstore.h>
#include <qpa/qplatformintegration.h>
#include <qpa/qplatformintegrationplugin.h>
#include <qpa/qplatformnativeinterface.h>
#include <qpa/qplatformopenglcontext.h>
#include <qpa/qplatformscreen.h>
#include <qpa/qplatformwindow.h>
#include <qpa/qwindowsysteminterface.h>

#include "protocol.h"

namespace {

constexpr int N_BUFFERS = 3;

EGLDisplay eglDisplay()
{
    static EGLDisplay dpy = [] {
        EGLDisplay d = eglGetDisplay(EGL_DEFAULT_DISPLAY);
        eglInitialize(d, nullptr, nullptr);
        return d;
    }();
    return dpy;
}

template <typename T> T eglProc(const char *name)
{
    return reinterpret_cast<T>(eglGetProcAddress(name));
}

struct Buffer {
    AHardwareBuffer *ahb = nullptr;
    EGLImageKHR image = EGL_NO_IMAGE_KHR;
    GLuint tex = 0, fbo = 0, depth = 0;
    bool busy = false; // the compositor may be reading it
};

class Window : public QPlatformWindow
{
public:
    explicit Window(QWindow *w) : QPlatformWindow(w)
    {
        m_fd = socket(AF_UNIX, SOCK_SEQPACKET | SOCK_CLOEXEC, 0);
        sockaddr_un a = {};
        a.sun_family = AF_UNIX;
        size_t len = strlen(NDESK_SOCKET);
        memcpy(a.sun_path + 1, NDESK_SOCKET, len);
        socklen_t alen = offsetof(sockaddr_un, sun_path) + 1 + len;
        if (m_fd < 0 || ::connect(m_fd, reinterpret_cast<sockaddr *>(&a), alen) < 0) {
            qWarning("deskdroid: can't reach the compositor");
            return;
        }
        QSize s = w->geometry().size().expandedTo(QSize(1, 1));
        ndesk_msg m = {};
        m.op = NDESK_HELLO;
        m.hello.version = NDESK_VERSION;
        m.hello.width = s.width();
        m.hello.height = s.height();
        snprintf(m.hello.title, NDESK_TITLE_MAX, "%s", qPrintable(w->title()));
        send(m);
        m_notifier = new QSocketNotifier(m_fd, QSocketNotifier::Read);
        QObject::connect(m_notifier, &QSocketNotifier::activated, [this] { readMessages(); });
    }

    ~Window() override
    {
        delete m_notifier;
        freeBuffers();
        if (m_fd >= 0) ::close(m_fd);
    }

    void setVisible(bool visible) override
    {
        QPlatformWindow::setVisible(visible);
        if (visible)
            QWindowSystemInterface::handleExposeEvent(window(), QRect(QPoint(), geometry().size()));
    }

    void setGeometry(const QRect &rect) override
    {
        QPlatformWindow::setGeometry(rect);
        QWindowSystemInterface::handleGeometryChange(window(), rect);
        if (window()->isVisible())
            QWindowSystemInterface::handleExposeEvent(window(), QRect(QPoint(), rect.size()));
    }

    WId winId() const override { return WId(m_fd); }

    // The compositor's FRAME event, not a timer, delivers update requests.
    void requestUpdate() override
    {
        if (!m_notifier) return;
        if (m_frameReady)
            QMetaObject::invokeMethod(m_notifier, [this] { deliverUpdateRequest(); }, Qt::QueuedConnection);
        else
            m_updatePending = true;
    }

    // Raster: copy the backing store's image into a free buffer and commit it.
    void presentImage(const QImage &img)
    {
        if (!ensureBuffers(img.size(), false)) return;
        int id = acquire();
        Buffer &b = m_buf[id];
        AHardwareBuffer_Desc d;
        AHardwareBuffer_describe(b.ahb, &d);
        void *dst = nullptr;
        if (AHardwareBuffer_lock(b.ahb, AHARDWAREBUFFER_USAGE_CPU_WRITE_OFTEN, -1, nullptr, &dst) != 0) return;
        const int rowBytes = qMin<int>(img.width(), d.width) * 4;
        for (int y = 0; y < qMin<int>(img.height(), d.height); y++)
            memcpy(static_cast<char *>(dst) + size_t(y) * d.stride * 4, img.constScanLine(y), rowBytes);
        int fence = -1;
        AHardwareBuffer_unlock(b.ahb, &fence);
        commit(id, fence, false);
    }

    // OpenGL: the framebuffer Qt renders into (the current back buffer).
    GLuint backFbo()
    {
        if (!ensureBuffers(geometry().size().expandedTo(QSize(1, 1)), true)) return 0;
        if (m_back < 0) m_back = acquire();
        return m_buf[m_back].fbo;
    }

    void swapGl()
    {
        if (m_back < 0) return;
        static auto createSync = eglProc<PFNEGLCREATESYNCKHRPROC>("eglCreateSyncKHR");
        static auto destroySync = eglProc<PFNEGLDESTROYSYNCKHRPROC>("eglDestroySyncKHR");
        static auto dupFence = eglProc<PFNEGLDUPNATIVEFENCEFDANDROIDPROC>("eglDupNativeFenceFDANDROID");
        int fence = -1;
        if (createSync && dupFence) {
            EGLSyncKHR s = createSync(eglDisplay(), EGL_SYNC_NATIVE_FENCE_ANDROID, nullptr);
            glFlush();
            if (s != EGL_NO_SYNC_KHR) {
                fence = dupFence(eglDisplay(), s);
                destroySync(eglDisplay(), s);
            }
        }
        if (fence < 0) glFinish();
        commit(m_back, fence, true); // GL's framebuffer has row 0 at the bottom
        m_back = acquire();
        glBindFramebuffer(GL_FRAMEBUFFER, m_buf[m_back].fbo);
    }

private:
    void send(const ndesk_msg &m, int passFd = -1)
    {
        iovec iov = { const_cast<ndesk_msg *>(&m), sizeof m };
        msghdr h = {};
        h.msg_iov = &iov;
        h.msg_iovlen = 1;
        char ctrl[CMSG_SPACE(sizeof(int))];
        if (passFd >= 0) {
            h.msg_control = ctrl;
            h.msg_controllen = sizeof ctrl;
            cmsghdr *c = CMSG_FIRSTHDR(&h);
            c->cmsg_level = SOL_SOCKET;
            c->cmsg_type = SCM_RIGHTS;
            c->cmsg_len = CMSG_LEN(sizeof(int));
            memcpy(CMSG_DATA(c), &passFd, sizeof(int));
        }
        if (sendmsg(m_fd, &h, MSG_NOSIGNAL) < 0) qWarning("deskdroid: compositor went away");
    }

    void commit(int id, int fence, bool yInvert)
    {
        ndesk_msg m = {};
        m.op = NDESK_COMMIT;
        m.commit.id = id;
        m.commit.has_fence = fence >= 0;
        m.commit.y_invert = yInvert;
        send(m, fence);
        if (fence >= 0) ::close(fence);
        m_buf[id].busy = true;
        m_frameReady = false;
    }

    void readMessages()
    {
        ndesk_msg m;
        while (recv(m_fd, &m, sizeof m, MSG_DONTWAIT) == sizeof m) {
            switch (m.op) {
            case NDESK_RELEASE:
                if (m.release.id < N_BUFFERS) m_buf[m.release.id].busy = false;
                break;
            case NDESK_FRAME:
                m_frameReady = true;
                if (m_updatePending) {
                    m_updatePending = false;
                    deliverUpdateRequest();
                }
                break;
            case NDESK_POINTER:
                pointer(m);
                break;
            case NDESK_KEY:
                key(m);
                break;
            }
        }
    }

    void pointer(const ndesk_msg &m)
    {
        const QPointF pos(m.pointer.x, m.pointer.y);
        Qt::MouseButtons now;
        if (m.pointer.buttons & 1) now |= Qt::LeftButton;
        if (m.pointer.buttons & 2) now |= Qt::RightButton;
        if (m.pointer.buttons & 4) now |= Qt::MiddleButton;
        const Qt::MouseButtons changed = now ^ m_buttons;
        for (Qt::MouseButton b : { Qt::LeftButton, Qt::RightButton, Qt::MiddleButton }) {
            if (!(changed & b)) continue;
            m_buttons ^= b;
            QWindowSystemInterface::handleMouseEvent(window(), pos, pos, m_buttons, b,
                (now & b) ? QEvent::MouseButtonPress : QEvent::MouseButtonRelease);
        }
        if (!changed)
            QWindowSystemInterface::handleMouseEvent(window(), pos, pos, m_buttons, Qt::NoButton, QEvent::MouseMove);
    }

    void key(const ndesk_msg &m)
    {
        // Android key codes: just enough to type and edit.
        int k = 0;
        switch (m.key.keycode) {
        case 66: k = Qt::Key_Return; break;     // KEYCODE_ENTER
        case 67: k = Qt::Key_Backspace; break;  // KEYCODE_DEL
        case 61: k = Qt::Key_Tab; break;
        case 111: k = Qt::Key_Escape; break;
        case 19: k = Qt::Key_Up; break;
        case 20: k = Qt::Key_Down; break;
        case 21: k = Qt::Key_Left; break;
        case 22: k = Qt::Key_Right; break;
        default:
            if (m.key.unicode > 0) k = int(QChar::toUpper(char32_t(m.key.unicode)));
        }
        const char32_t ch = char32_t(m.key.unicode);
        const QString text = m.key.unicode > 0 ? QString::fromUcs4(&ch, 1) : QString();
        QWindowSystemInterface::handleKeyEvent(window(), m.key.down ? QEvent::KeyPress : QEvent::KeyRelease,
                                               k, Qt::NoModifier, text);
    }

    // A free buffer; like a real swap, blocks until the compositor returns one.
    int acquire()
    {
        for (int tries = 0; tries < 50; tries++) {
            for (int i = 0; i < N_BUFFERS; i++)
                if (!m_buf[i].busy) return i;
            pollfd p = { m_fd, POLLIN, 0 };
            poll(&p, 1, 20);
            readMessages();
        }
        qWarning("deskdroid: no buffer came back, reusing one");
        return 0;
    }

    bool ensureBuffers(QSize size, bool gpu)
    {
        if (m_fd < 0) return false;
        if (m_buf[0].ahb && size == m_size && gpu == m_gpu) return true;
        freeBuffers();
        m_size = size;
        m_gpu = gpu;
        static auto getClientBuffer = eglProc<PFNEGLGETNATIVECLIENTBUFFERANDROIDPROC>("eglGetNativeClientBufferANDROID");
        static auto createImage = eglProc<PFNEGLCREATEIMAGEKHRPROC>("eglCreateImageKHR");
        static auto imageTarget = eglProc<PFNGLEGLIMAGETARGETTEXTURE2DOESPROC>("glEGLImageTargetTexture2DOES");
        for (int i = 0; i < N_BUFFERS; i++) {
            Buffer &b = m_buf[i];
            AHardwareBuffer_Desc d = {};
            d.width = size.width();
            d.height = size.height();
            d.layers = 1;
            d.format = AHARDWAREBUFFER_FORMAT_R8G8B8A8_UNORM;
            d.usage = AHARDWAREBUFFER_USAGE_GPU_SAMPLED_IMAGE |
                (gpu ? AHARDWAREBUFFER_USAGE_GPU_FRAMEBUFFER : AHARDWAREBUFFER_USAGE_CPU_WRITE_OFTEN);
            if (AHardwareBuffer_allocate(&d, &b.ahb) != 0) {
                qWarning("deskdroid: can't allocate a %dx%d buffer", size.width(), size.height());
                return false;
            }
            if (gpu) {
                const EGLint attr[] = { EGL_IMAGE_PRESERVED_KHR, EGL_TRUE, EGL_NONE };
                b.image = createImage(eglDisplay(), EGL_NO_CONTEXT, EGL_NATIVE_BUFFER_ANDROID,
                                      getClientBuffer(b.ahb), attr);
                glGenTextures(1, &b.tex);
                glBindTexture(GL_TEXTURE_2D, b.tex);
                imageTarget(GL_TEXTURE_2D, b.image);
                glGenRenderbuffers(1, &b.depth);
                glBindRenderbuffer(GL_RENDERBUFFER, b.depth);
                glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH24_STENCIL8, size.width(), size.height());
                glGenFramebuffers(1, &b.fbo);
                glBindFramebuffer(GL_FRAMEBUFFER, b.fbo);
                glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, b.tex, 0);
                glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_STENCIL_ATTACHMENT, GL_RENDERBUFFER, b.depth);
                if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE)
                    qWarning("deskdroid: framebuffer on a hardware buffer is incomplete");
            }
            ndesk_msg m = {};
            m.op = NDESK_BUFFER;
            m.buffer.id = i;
            send(m);
            AHardwareBuffer_sendHandleToUnixSocket(b.ahb, m_fd);
        }
        return true;
    }

    void freeBuffers()
    {
        static auto destroyImage = eglProc<PFNEGLDESTROYIMAGEKHRPROC>("eglDestroyImageKHR");
        for (Buffer &b : m_buf) {
            // GL objects belong to the context that made them; only free them while one is current.
            if (eglGetCurrentContext() != EGL_NO_CONTEXT) {
                if (b.fbo) glDeleteFramebuffers(1, &b.fbo);
                if (b.depth) glDeleteRenderbuffers(1, &b.depth);
                if (b.tex) glDeleteTextures(1, &b.tex);
            }
            if (b.image != EGL_NO_IMAGE_KHR) destroyImage(eglDisplay(), b.image);
            if (b.ahb) AHardwareBuffer_release(b.ahb);
            b = Buffer();
        }
        m_back = -1;
    }

    int m_fd = -1;
    QSocketNotifier *m_notifier = nullptr;
    Buffer m_buf[N_BUFFERS];
    QSize m_size;
    bool m_gpu = false;
    int m_back = -1;
    bool m_frameReady = true;
    bool m_updatePending = false;
    Qt::MouseButtons m_buttons;
};

class BackingStore : public QPlatformBackingStore
{
public:
    using QPlatformBackingStore::QPlatformBackingStore;

    QPaintDevice *paintDevice() override { return &m_image; }

    void resize(const QSize &size, const QRegion &) override
    {
        if (m_image.size() != size) m_image = QImage(size, QImage::Format_RGBA8888_Premultiplied);
    }

    void flush(QWindow *w, const QRegion &, const QPoint &) override
    {
        if (auto *pw = static_cast<Window *>(w->handle())) pw->presentImage(m_image);
    }

private:
    QImage m_image;
};

class GLContext : public QPlatformOpenGLContext
{
public:
    explicit GLContext(QOpenGLContext *ctx)
    {
        EGLDisplay dpy = eglDisplay();
        m_format = ctx->format();
        m_format.setRenderableType(QSurfaceFormat::OpenGLES);
        if (m_format.majorVersion() < 3) m_format.setVersion(3, 0);
        m_format.setRedBufferSize(8);
        m_format.setGreenBufferSize(8);
        m_format.setBlueBufferSize(8);
        m_format.setAlphaBufferSize(8);
        m_format.setDepthBufferSize(24);
        m_format.setStencilBufferSize(8);
        const EGLint cfgAttr[] = { EGL_SURFACE_TYPE, EGL_PBUFFER_BIT, EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT_KHR,
                                   EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8, EGL_ALPHA_SIZE, 8,
                                   EGL_NONE };
        EGLConfig cfg;
        EGLint n = 0;
        if (!eglChooseConfig(dpy, cfgAttr, &cfg, 1, &n) || n < 1) return;
        auto *share = static_cast<GLContext *>(ctx->shareHandle());
        const EGLint ctxAttr[] = { EGL_CONTEXT_CLIENT_VERSION, m_format.majorVersion(), EGL_NONE };
        m_ctx = eglCreateContext(dpy, cfg, share ? share->m_ctx : EGL_NO_CONTEXT, ctxAttr);
        const EGLint pbAttr[] = { EGL_WIDTH, 1, EGL_HEIGHT, 1, EGL_NONE };
        m_pbuffer = eglCreatePbufferSurface(dpy, cfg, pbAttr);
        m_gles = dlopen("libGLESv3.so", RTLD_NOW | RTLD_LOCAL);
    }

    ~GLContext() override
    {
        if (m_pbuffer != EGL_NO_SURFACE) eglDestroySurface(eglDisplay(), m_pbuffer);
        if (m_ctx != EGL_NO_CONTEXT) eglDestroyContext(eglDisplay(), m_ctx);
    }

    QSurfaceFormat format() const override { return m_format; }
    bool isValid() const override { return m_ctx != EGL_NO_CONTEXT && m_pbuffer != EGL_NO_SURFACE; }

    bool makeCurrent(QPlatformSurface *surface) override
    {
        if (!eglMakeCurrent(eglDisplay(), m_pbuffer, m_pbuffer, m_ctx)) return false;
        if (auto *w = windowOf(surface)) glBindFramebuffer(GL_FRAMEBUFFER, w->backFbo());
        return true;
    }

    void doneCurrent() override { eglMakeCurrent(eglDisplay(), EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT); }

    void swapBuffers(QPlatformSurface *surface) override
    {
        if (auto *w = windowOf(surface)) w->swapGl();
    }

    GLuint defaultFramebufferObject(QPlatformSurface *surface) const override
    {
        auto *w = windowOf(surface);
        return w ? w->backFbo() : 0;
    }

    QFunctionPointer getProcAddress(const char *name) override
    {
        if (m_gles)
            if (void *p = dlsym(m_gles, name)) return reinterpret_cast<QFunctionPointer>(p);
        return reinterpret_cast<QFunctionPointer>(eglGetProcAddress(name));
    }

private:
    static Window *windowOf(QPlatformSurface *s)
    {
        return s && s->surface()->surfaceClass() == QSurface::Window ? static_cast<Window *>(s) : nullptr;
    }

    QSurfaceFormat m_format;
    EGLContext m_ctx = EGL_NO_CONTEXT;
    EGLSurface m_pbuffer = EGL_NO_SURFACE;
    void *m_gles = nullptr;
};

// The compositor doesn't describe its display yet, so this is a fixed 1080p screen.
class Screen : public QPlatformScreen
{
public:
    QRect geometry() const override { return QRect(0, 0, 1920, 1080); }
    int depth() const override { return 32; }
    QImage::Format format() const override { return QImage::Format_RGBA8888_Premultiplied; }
    qreal refreshRate() const override { return 120; }
    QSizeF physicalSize() const override { return QSizeF(1920 * 25.4 / 160, 1080 * 25.4 / 160); }
};

class Integration : public QPlatformIntegration
{
public:
    void initialize() override { QWindowSystemInterface::handleScreenAdded(new Screen, true); }

    bool hasCapability(Capability cap) const override
    {
        switch (cap) {
        case OpenGL:
        case ThreadedPixmaps:
        case MultipleWindows:
        case NonFullScreenWindows:
            return true;
        default:
            return false;
        }
    }

    QPlatformWindow *createPlatformWindow(QWindow *w) const override { return new Window(w); }
    QPlatformBackingStore *createPlatformBackingStore(QWindow *w) const override { return new BackingStore(w); }
    QPlatformOpenGLContext *createPlatformOpenGLContext(QOpenGLContext *ctx) const override { return new GLContext(ctx); }
    QAbstractEventDispatcher *createEventDispatcher() const override { return new QEventDispatcherUNIX; }
    // Qt's OpenGL code on Android asks it for "AndroidDeviceName" without a null check.
    QPlatformNativeInterface *nativeInterface() const override { return &m_native; }
    // Android's own fonts, found through QT_QPA_FONTDIR=/system/fonts.
    QPlatformFontDatabase *fontDatabase() const override { return &m_fonts; }

private:
    mutable QFreeTypeFontDatabase m_fonts;
    mutable QPlatformNativeInterface m_native;
};

} // namespace

class DeskDroidIntegrationPlugin : public QPlatformIntegrationPlugin
{
    Q_OBJECT
    Q_PLUGIN_METADATA(IID QPlatformIntegrationFactoryInterface_iid FILE "deskdroid.json")
public:
    QPlatformIntegration *create(const QString &key, const QStringList &) override
    {
        return key.compare(QLatin1String("deskdroid"), Qt::CaseInsensitive) == 0 ? new Integration : nullptr;
    }
};

#include "qpa.moc"

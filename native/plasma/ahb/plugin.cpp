/*
 * "deskdroid-ahb": Qt Wayland client buffer integration for KWin's
 * deskdroid_ahb_v1 (deskdroid_ahb.h). It stands in for Qt's "wayland-egl",
 * which needs an EGL with a Wayland platform; Android's EGL has none.
 *
 * An OpenGL window (every Qt Quick window: plasmashell, Kirigami apps) draws
 * into one of three AHardwareBuffers through an EGLImage-backed framebuffer,
 * which Qt takes for the window's default framebuffer; on swap the buffer
 * goes to KWin as a wl_buffer and KWin samples it as a texture. The GPU draws
 * everything and nothing is copied. Contexts render offscreen (a 1x1 pbuffer)
 * since there is no EGL window surface to draw to.
 *
 * Qt picks this with QT_WAYLAND_CLIENT_BUFFER_INTEGRATION=deskdroid-ahb.
 * Without the global (KWin compositing on the CPU), the integration is
 * invalid and Qt falls back to shared memory and its software renderer.
 */
#include <android/hardware_buffer.h>
#include <dlfcn.h>
#include <sys/socket.h>
#include <unistd.h>

#include <QtGui/QOpenGLContext>
#include <QtGui/QWindow>
#include <QtWaylandClient/private/qwaylandbuffer_p.h>
#include <QtWaylandClient/private/qwaylandclientbufferintegration_p.h>
#include <QtWaylandClient/private/qwaylandclientbufferintegrationplugin_p.h>
#include <QtWaylandClient/private/qwaylanddisplay_p.h>
#include <QtWaylandClient/private/qwaylandwindow_p.h>
#include <qpa/qplatformopenglcontext.h>

#define EGL_EGLEXT_PROTOTYPES
#define GL_GLEXT_PROTOTYPES
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES3/gl3.h>
#include <GLES2/gl2ext.h>

#include <wayland-client.h>

#include <memory>

#include "deskdroid_ahb.h"

QT_BEGIN_NAMESPACE

namespace QtWaylandClient {

namespace {

constexpr int BufferCount = 3;

EGLDisplay eglDisplay()
{
    static EGLDisplay dpy = [] {
        EGLDisplay d = eglGetDisplay(EGL_DEFAULT_DISPLAY);
        if (d != EGL_NO_DISPLAY && !eglInitialize(d, nullptr, nullptr)) {
            d = EGL_NO_DISPLAY;
        }
        return d;
    }();
    return dpy;
}

template<typename T>
T eglProc(const char *name)
{
    return reinterpret_cast<T>(eglGetProcAddress(name));
}

// Makes a context current for a moment (to free its objects) and back.
class ContextSwitch
{
public:
    ContextSwitch(EGLContext ctx, EGLSurface surface)
        : m_dpy(eglGetCurrentDisplay())
        , m_ctx(eglGetCurrentContext())
        , m_draw(eglGetCurrentSurface(EGL_DRAW))
        , m_read(eglGetCurrentSurface(EGL_READ))
    {
        m_ok = ctx == m_ctx || (ctx != EGL_NO_CONTEXT && eglMakeCurrent(eglDisplay(), surface, surface, ctx));
        m_switched = m_ok && ctx != m_ctx;
    }
    ~ContextSwitch()
    {
        if (m_switched) {
            if (m_ctx != EGL_NO_CONTEXT) {
                eglMakeCurrent(m_dpy, m_draw, m_read, m_ctx);
            } else {
                eglMakeCurrent(eglDisplay(), EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
            }
        }
    }
    bool ok() const { return m_ok; }

private:
    EGLDisplay m_dpy;
    EGLContext m_ctx;
    EGLSurface m_draw, m_read;
    bool m_ok = false;
    bool m_switched = false;
};

// One AHardwareBuffer: a framebuffer for the app, a wl_buffer for KWin.
class AhbBuffer : public QWaylandBuffer
{
public:
    AhbBuffer(wl_proxy *manager, const QSize &size)
        : m_size(size)
        , m_ctx(eglGetCurrentContext())
    {
        static auto getClientBuffer = eglProc<PFNEGLGETNATIVECLIENTBUFFERANDROIDPROC>("eglGetNativeClientBufferANDROID");
        static auto imageTarget = eglProc<PFNGLEGLIMAGETARGETTEXTURE2DOESPROC>("glEGLImageTargetTexture2DOES");
        if (!getClientBuffer || !imageTarget) {
            return;
        }
        AHardwareBuffer_Desc d = {};
        d.width = size.width();
        d.height = size.height();
        d.layers = 1;
        d.format = AHARDWAREBUFFER_FORMAT_R8G8B8A8_UNORM;
        d.usage = AHARDWAREBUFFER_USAGE_GPU_SAMPLED_IMAGE | AHARDWAREBUFFER_USAGE_GPU_FRAMEBUFFER;
        if (AHardwareBuffer_allocate(&d, &m_ahb) != 0) {
            qWarning("deskdroid-ahb: can't allocate a %dx%d buffer", size.width(), size.height());
            m_ahb = nullptr;
            return;
        }
        const EGLint attr[] = {EGL_IMAGE_PRESERVED_KHR, EGL_TRUE, EGL_NONE};
        m_image = eglCreateImageKHR(eglDisplay(), EGL_NO_CONTEXT, EGL_NATIVE_BUFFER_ANDROID, getClientBuffer(m_ahb), attr);
        if (m_image == EGL_NO_IMAGE_KHR) {
            qWarning("deskdroid-ahb: can't make an EGLImage (0x%x)", eglGetError());
            return;
        }
        GLint oldFbo = 0, oldTex = 0, oldRb = 0;
        glGetIntegerv(GL_FRAMEBUFFER_BINDING, &oldFbo);
        glGetIntegerv(GL_TEXTURE_BINDING_2D, &oldTex);
        glGetIntegerv(GL_RENDERBUFFER_BINDING, &oldRb);
        glGenTextures(1, &m_tex);
        glBindTexture(GL_TEXTURE_2D, m_tex);
        imageTarget(GL_TEXTURE_2D, m_image);
        glGenRenderbuffers(1, &m_depth);
        glBindRenderbuffer(GL_RENDERBUFFER, m_depth);
        glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH24_STENCIL8, size.width(), size.height());
        glGenFramebuffers(1, &m_fbo);
        glBindFramebuffer(GL_FRAMEBUFFER, m_fbo);
        glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, m_tex, 0);
        glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_STENCIL_ATTACHMENT, GL_RENDERBUFFER, m_depth);
        const bool complete = glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE;
        glBindFramebuffer(GL_FRAMEBUFFER, oldFbo);
        glBindTexture(GL_TEXTURE_2D, oldTex);
        glBindRenderbuffer(GL_RENDERBUFFER, oldRb);
        if (!complete) {
            qWarning("deskdroid-ahb: a framebuffer on a hardware buffer is incomplete");
            freeGl();
            return;
        }

        // KWin reads the buffer from a socket: send it into one end, pass the other.
        int sv[2];
        if (socketpair(AF_UNIX, SOCK_SEQPACKET | SOCK_CLOEXEC, 0, sv) != 0) {
            freeGl();
            return;
        }
        if (AHardwareBuffer_sendHandleToUnixSocket(m_ahb, sv[0]) != 0) {
            qWarning("deskdroid-ahb: can't send a buffer");
            close(sv[0]);
            close(sv[1]);
            freeGl();
            return;
        }
        auto *buffer = reinterpret_cast<wl_buffer *>(wl_proxy_marshal_flags(manager, DESKDROID_AHB_V1_CREATE_BUFFER, &wl_buffer_interface,
                                                                            wl_proxy_get_version(manager), 0, nullptr, sv[1], 1u /* row 0 at the bottom */));
        close(sv[0]);
        close(sv[1]);
        init(buffer);
    }

    ~AhbBuffer() override
    {
        freeGl();
        if (m_image != EGL_NO_IMAGE_KHR) {
            eglDestroyImageKHR(eglDisplay(), m_image);
        }
        if (m_ahb) {
            AHardwareBuffer_release(m_ahb);
        }
    }

    QSize size() const override { return m_size; }
    bool isValid() const { return mBuffer && m_fbo; }
    GLuint fbo() const { return m_fbo; }

private:
    // Only with the context that made them current (the caller sees to it).
    void freeGl()
    {
        if (eglGetCurrentContext() != m_ctx) {
            return;
        }
        if (m_fbo) glDeleteFramebuffers(1, &m_fbo);
        if (m_depth) glDeleteRenderbuffers(1, &m_depth);
        if (m_tex) glDeleteTextures(1, &m_tex);
        m_fbo = m_depth = m_tex = 0;
    }

    QSize m_size;
    EGLContext m_ctx;
    AHardwareBuffer *m_ahb = nullptr;
    EGLImageKHR m_image = EGL_NO_IMAGE_KHR;
    GLuint m_tex = 0, m_depth = 0, m_fbo = 0;
};

class AhbContext;

class AhbWindow : public QWaylandWindow
{
public:
    AhbWindow(QWindow *window, QWaylandDisplay *display, wl_proxy *manager)
        : QWaylandWindow(window, display)
        , m_manager(manager)
    {
        m_format = window->requestedFormat();
        m_format.setRenderableType(QSurfaceFormat::OpenGLES);
        m_format.setRedBufferSize(8);
        m_format.setGreenBufferSize(8);
        m_format.setBlueBufferSize(8);
        m_format.setAlphaBufferSize(8);
        m_format.setDepthBufferSize(24);
        m_format.setStencilBufferSize(8);
    }

    ~AhbWindow() override { freeBuffers(); }

    WindowType windowType() const override { return Egl; }
    QSurfaceFormat format() const override { return m_format; }

    // The framebuffer Qt draws the frame into, on the given context.
    GLuint backFbo(EGLContext ctx, EGLSurface ctxSurface)
    {
        if (!isExposed()) {
            return 0; // a hidden helper window (QOffscreenSurface's): the context's own pbuffer
        }
        const QSize size = bufferSize();
        if (size != m_size || ctx != m_ctx) {
            freeBuffers();
            m_size = size;
            m_ctx = ctx;
            m_ctxSurface = ctxSurface;
        }
        if (!m_back) {
            m_back = acquire();
        }
        return m_back ? m_back->fbo() : 0;
    }

    void swap()
    {
        if (!m_back) {
            return;
        }
        glFlush();
        if (m_format.swapInterval() > 0) {
            waitForFrameSync(100); // one frame per frame callback, as wayland-egl does
        }
        // KWin samples the buffer as soon as it is committed.
        glFinish();
        handleUpdate();
        m_back->setBusy(true);
        safeCommit(m_back, QRegion(QRect(QPoint(), geometry().size())));
        m_back = nullptr;
    }

private:
    QSize bufferSize() const
    {
        const QMargins m = clientSideMargins();
        const QSize logical = geometry().size() + QSize(m.left() + m.right(), m.top() + m.bottom());
        return (QSizeF(logical) * scale()).toSize().expandedTo(QSize(1, 1));
    }

    AhbBuffer *acquire()
    {
        for (auto &b : m_buffers) {
            if (b && !b->busy()) {
                return b.get();
            }
        }
        for (auto &b : m_buffers) {
            if (!b) {
                b = std::make_unique<AhbBuffer>(m_manager, m_size);
                if (!b->isValid()) {
                    b.reset();
                    return nullptr;
                }
                return b.get();
            }
        }
        // All three with KWin: let its releases in.
        mDisplay->forceRoundTrip();
        for (auto &b : m_buffers) {
            if (!b->busy()) {
                return b.get();
            }
        }
        static bool warned = false;
        if (!warned) {
            qWarning("deskdroid-ahb: KWin kept every buffer, drawing into one it holds");
            warned = true;
        }
        AhbBuffer *b = m_buffers[m_reuse++ % BufferCount].get();
        b->setBusy(false);
        return b;
    }

    void freeBuffers()
    {
        if (!m_buffers[0] && !m_buffers[1] && !m_buffers[2]) {
            return;
        }
        ContextSwitch current(m_ctx, m_ctxSurface);
        for (auto &b : m_buffers) {
            if (b && !current.ok()) {
                qWarning("deskdroid-ahb: freeing buffers without their context");
            }
            b.reset();
        }
        m_back = nullptr;
    }

    wl_proxy *m_manager;
    QSurfaceFormat m_format;
    std::unique_ptr<AhbBuffer> m_buffers[BufferCount];
    AhbBuffer *m_back = nullptr;
    QSize m_size;
    EGLContext m_ctx = EGL_NO_CONTEXT;
    EGLSurface m_ctxSurface = EGL_NO_SURFACE;
    int m_reuse = 0;
};

class AhbContext : public QPlatformOpenGLContext
{
public:
    AhbContext(const QSurfaceFormat &requested, QPlatformOpenGLContext *share)
    {
        EGLDisplay dpy = eglDisplay();
        const EGLint cfgAttr[] = {EGL_SURFACE_TYPE, EGL_PBUFFER_BIT, EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT_KHR,
                                  EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8, EGL_ALPHA_SIZE, 8, EGL_NONE};
        EGLConfig cfg;
        EGLint n = 0;
        if (!eglChooseConfig(dpy, cfgAttr, &cfg, 1, &n) || n < 1) {
            qWarning("deskdroid-ahb: no EGL config");
            return;
        }
        EGLContext shareCtx = share ? static_cast<AhbContext *>(share)->m_ctx : EGL_NO_CONTEXT;
        // The newest OpenGL ES there is, down to 3.0.
        for (int minor : {2, 1, 0}) {
            const EGLint ctxAttr[] = {EGL_CONTEXT_MAJOR_VERSION_KHR, 3, EGL_CONTEXT_MINOR_VERSION_KHR, minor, EGL_NONE};
            m_ctx = eglCreateContext(dpy, cfg, shareCtx, ctxAttr);
            if (m_ctx != EGL_NO_CONTEXT) {
                m_format = requested;
                m_format.setRenderableType(QSurfaceFormat::OpenGLES);
                m_format.setVersion(3, minor);
                m_format.setProfile(QSurfaceFormat::NoProfile);
                break;
            }
        }
        if (m_ctx == EGL_NO_CONTEXT) {
            qWarning("deskdroid-ahb: can't make an OpenGL ES 3 context (0x%x)", eglGetError());
            return;
        }
        m_format.setRedBufferSize(8);
        m_format.setGreenBufferSize(8);
        m_format.setBlueBufferSize(8);
        m_format.setAlphaBufferSize(8);
        m_format.setDepthBufferSize(24);
        m_format.setStencilBufferSize(8);
        const EGLint pbAttr[] = {EGL_WIDTH, 1, EGL_HEIGHT, 1, EGL_NONE};
        m_pbuffer = eglCreatePbufferSurface(dpy, cfg, pbAttr);
        m_gles = dlopen("libGLESv3.so", RTLD_NOW | RTLD_LOCAL);
        m_shared = shareCtx != EGL_NO_CONTEXT;
        static bool said = false;
        if (!said && m_pbuffer != EGL_NO_SURFACE && eglMakeCurrent(dpy, m_pbuffer, m_pbuffer, m_ctx)) {
            qInfo("deskdroid-ahb: drawing on the GPU: %s, %s", glGetString(GL_RENDERER), glGetString(GL_VERSION));
            eglMakeCurrent(dpy, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
            said = true;
        }
    }

    ~AhbContext() override
    {
        if (m_pbuffer != EGL_NO_SURFACE) eglDestroySurface(eglDisplay(), m_pbuffer);
        if (m_ctx != EGL_NO_CONTEXT) eglDestroyContext(eglDisplay(), m_ctx);
    }

    QSurfaceFormat format() const override { return m_format; }
    bool isValid() const override { return m_ctx != EGL_NO_CONTEXT && m_pbuffer != EGL_NO_SURFACE; }
    bool isSharing() const override { return m_shared; }

    bool makeCurrent(QPlatformSurface *surface) override
    {
        if (!eglMakeCurrent(eglDisplay(), m_pbuffer, m_pbuffer, m_ctx)) {
            qWarning("deskdroid-ahb: eglMakeCurrent failed (0x%x)", eglGetError());
            return false;
        }
        glBindFramebuffer(GL_FRAMEBUFFER, defaultFramebufferObject(surface));
        return true;
    }

    void doneCurrent() override { eglMakeCurrent(eglDisplay(), EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT); }

    void swapBuffers(QPlatformSurface *surface) override
    {
        if (auto *w = windowOf(surface)) {
            w->swap();
        }
    }

    GLuint defaultFramebufferObject(QPlatformSurface *surface) const override
    {
        auto *w = windowOf(surface);
        return w ? w->backFbo(m_ctx, m_pbuffer) : 0;
    }

    QFunctionPointer getProcAddress(const char *name) override
    {
        if (m_gles) {
            if (void *p = dlsym(m_gles, name)) {
                return reinterpret_cast<QFunctionPointer>(p);
            }
        }
        return reinterpret_cast<QFunctionPointer>(eglGetProcAddress(name));
    }

    EGLContext eglContext() const { return m_ctx; }

private:
    static AhbWindow *windowOf(QPlatformSurface *s)
    {
        return s && s->surface()->surfaceClass() == QSurface::Window ? static_cast<AhbWindow *>(s) : nullptr;
    }

    QSurfaceFormat m_format;
    EGLContext m_ctx = EGL_NO_CONTEXT;
    EGLSurface m_pbuffer = EGL_NO_SURFACE;
    void *m_gles = nullptr;
    bool m_shared = false;
};

class AhbIntegration : public QWaylandClientBufferIntegration
{
public:
    void initialize(QWaylandDisplay *display) override
    {
        m_display = display;
        if (eglDisplay() == EGL_NO_DISPLAY) {
            qWarning("deskdroid-ahb: no EGL display");
            return;
        }
        display->addRegistryListener(&AhbIntegration::global, this);
        if (!m_manager) {
            qInfo("deskdroid-ahb: KWin takes no GPU buffers (compositing on the CPU), drawing in software");
        }
    }

    bool isValid() const override { return m_manager && eglDisplay() != EGL_NO_DISPLAY; }
    bool supportsThreadedOpenGL() const override { return false; }

    QWaylandWindow *createEglWindow(QWindow *window) override { return new AhbWindow(window, m_display, m_manager); }

    QPlatformOpenGLContext *createPlatformOpenGLContext(const QSurfaceFormat &format, QPlatformOpenGLContext *share) const override
    {
        return new AhbContext(format, share);
    }

    void *nativeResource(NativeResource resource) override
    {
        return resource == EglDisplay ? eglDisplay() : nullptr;
    }

    void *nativeResourceForContext(NativeResource resource, QPlatformOpenGLContext *context) override
    {
        if (resource == EglDisplay) return eglDisplay();
        if (resource == EglContext && context) return static_cast<AhbContext *>(context)->eglContext();
        return nullptr;
    }

private:
    static void global(void *data, wl_registry *registry, uint32_t id, const QString &interface, uint32_t)
    {
        auto *self = static_cast<AhbIntegration *>(data);
        if (!self->m_manager && interface == QLatin1String("deskdroid_ahb_v1")) {
            self->m_manager = static_cast<wl_proxy *>(wl_registry_bind(registry, id, &deskdroid_ahb_v1_interface, 1));
        }
    }

    QWaylandDisplay *m_display = nullptr;
    wl_proxy *m_manager = nullptr;
};

} // namespace

class DeskDroidAhbPlugin : public QWaylandClientBufferIntegrationPlugin
{
    Q_OBJECT
    Q_PLUGIN_METADATA(IID QWaylandClientBufferIntegrationFactoryInterface_iid FILE "deskdroid-ahb.json")
public:
    QWaylandClientBufferIntegration *create(const QString &, const QStringList &) override { return new AhbIntegration; }
};

}

QT_END_NAMESPACE

#include "plugin.moc"

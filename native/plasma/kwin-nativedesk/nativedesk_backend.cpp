/*
    KWin backend for DeskDroid's native Android compositor; see the header.

    SPDX-License-Identifier: GPL-2.0-or-later
*/
#include "nativedesk_backend.h"

#include "core/outputconfiguration.h"
#include "compositor.h"
#include "scene/workspacescene.h"
#include "core/renderloop.h"
#include "input.h"
#include "deskdroid_ahb_server.h"
#include "opengl/eglcontext.h"
#include "opengl/egldisplay.h"
#include "opengl/eglimagetexture.h"
#include "opengl/eglnativefence.h"
#include "opengl/glframebuffer.h"
#include "opengl/glrendertimequery.h"
#include "opengl/glutils.h"
#include "window.h"
#include "wayland/display.h"
#include "wayland_server.h"
#include "workspace.h"

#include <QSocketNotifier>
#include <QTimer>

#include <android/hardware_buffer.h>
#include <epoxy/egl.h>
#include <epoxy/gl.h>
#include <linux/input-event-codes.h>
#include <poll.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

#include <chrono>
#include <cmath>

#include "protocol.h"

// Set in KWin's InputMethod::refreshActive (add-to-kwin.py): whether the
// focused surface has an enabled text input.
namespace KWin { extern void (*deskdroidTextInputHook)(bool); }

namespace KWin
{

static std::chrono::microseconds now()
{
    return std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now().time_since_epoch());
}

// ---- output ------------------------------------------------------------------

NativeDeskOutput::NativeDeskOutput(NativeDeskBackend *backend, const QSize &pixelSize, qreal scale)
    : Output(backend)
    , m_renderLoop(std::make_unique<RenderLoop>(this))
{
    // The compositor shows one frame per display refresh; the Pixel runs at 120 Hz.
    const uint32_t refresh = 120000;
    auto mode = std::make_shared<OutputMode>(pixelSize, refresh, OutputMode::Flag::Preferred);
    m_renderLoop->setRefreshRate(refresh);
    setInformation(Information{
        .name = QStringLiteral("NativeDesk-1"),
        .manufacturer = QStringLiteral("DeskDroid"),
        .model = QStringLiteral("Android screen"),
        // KWin picks each screen's scale from its size in millimetres (phone
        // screens aim at 150 dpi of logical pixels); a size that comes out at
        // the requested scale keeps it, where no size would mean scale 1.
        .physicalSize = (QSizeF(pixelSize) / (scale * 150.0) * 25.4).toSize(),
        .internal = true,
    });
    setState(State{
        .position = QPoint(0, 0),
        .scale = scale,
        .modes = {mode},
        .currentMode = mode,
        .enabled = true,
    });
}

NativeDeskOutput::~NativeDeskOutput() = default;

RenderLoop *NativeDeskOutput::renderLoop() const
{
    return m_renderLoop.get();
}

void NativeDeskOutput::present(const std::shared_ptr<OutputFrame> &frame)
{
    m_frame = frame;
    Q_EMIT outputChange(frame->damage());
}

// The compositor's FRAME event: it took the last commit and wants the next one.
void NativeDeskOutput::framePresented()
{
    if (m_frame) {
        m_frame->presented(std::chrono::steady_clock::now().time_since_epoch(), PresentationMode::VSync);
        m_frame.reset();
    }
}

// The phone turned (or the window changed size): the screen gets a new mode
// of the new size, at the scale it has now, and KWin lays everything out
// again as for a rotated monitor.
void NativeDeskOutput::setPixelSize(const QSize &pixelSize)
{
    if (pixelSize == modeSize()) {
        return;
    }
    const uint32_t refresh = 120000;
    auto mode = std::make_shared<OutputMode>(pixelSize, refresh, OutputMode::Flag::Preferred);
    setInformation(Information{
        .name = QStringLiteral("NativeDesk-1"),
        .manufacturer = QStringLiteral("DeskDroid"),
        .model = QStringLiteral("Android screen"),
        .physicalSize = (QSizeF(pixelSize) / (scale() * 150.0) * 25.4).toSize(),
        .internal = true,
    });
    State next = m_state;
    next.modes = {mode};
    next.currentMode = mode;
    setState(next);
    qInfo("nativedesk: screen now %dx%d", pixelSize.width(), pixelSize.height());
}

// The user picked another scale in DeskDroid's menu: applied now, as KDE's
// display settings would.
void NativeDeskOutput::setUserScale(qreal scale)
{
    if (qFuzzyCompare(scale, this->scale())) {
        return;
    }
    State next = m_state;
    next.scale = scale;
    setState(next);
    qInfo("nativedesk: scale now %.2f", scale);
}

// ---- input -------------------------------------------------------------------

NativeDeskInputDevice::NativeDeskInputDevice(bool keyboard)
    : m_keyboard(keyboard)
{
}

QString NativeDeskInputDevice::name() const
{
    return m_keyboard ? QStringLiteral("DeskDroid keyboard") : QStringLiteral("DeskDroid pointer");
}

bool NativeDeskInputDevice::isEnabled() const { return true; }
void NativeDeskInputDevice::setEnabled(bool) { }
bool NativeDeskInputDevice::isKeyboard() const { return m_keyboard; }
bool NativeDeskInputDevice::isPointer() const { return !m_keyboard; }
bool NativeDeskInputDevice::isTouchpad() const { return false; }
bool NativeDeskInputDevice::isTouch() const { return false; }
bool NativeDeskInputDevice::isTabletTool() const { return false; }
bool NativeDeskInputDevice::isTabletPad() const { return false; }
bool NativeDeskInputDevice::isTabletModeSwitch() const { return false; }
bool NativeDeskInputDevice::isLidSwitch() const { return false; }

// Plasma's popups (Kickoff, the clock's calendar...) hide when they lose the
// keyboard focus, which here they don't always get: a press outside one, other
// than on a panel (where Kickoff's button toggles it) or in one of its menus,
// closes it too.
// A plasmoid's popup (Kickoff, the calendar...). On this phone Plasma's popups
// reach KWin as ordinary windows of plasmashell (build 232's log: type 0,
// class org.kde.plasmashell), not with the applet-popup role, so those count.
// The desktop and panels are plasmashell's too but have their own types.
static bool isPlasmoidPopup(Window *w)
{
    return w->isAppletPopup()
        || (w->resourceClass() == QLatin1String("org.kde.plasmashell") && w->windowType() == WindowType::Normal);
}

static void closeAppletPopups(const QPointF &pos)
{
    if (!workspace() || !input()) {
        return;
    }
    QList<Window *> popups;
    const auto windows = workspace()->windows();
    for (Window *w : windows) {
        if (isPlasmoidPopup(w) && !w->isDeleted() && !w->isHidden()) {
            popups << w;
        }
    }
    if (popups.isEmpty()) {
        // What is on screen instead (a popup Plasma didn't mark as one?), once
        // per set of windows, to find out what stays open.
        QStringList seen;
        for (Window *w : windows) {
            if (!w->isDeleted() && !w->isHidden() && !w->isDesktop()) {
                seen << QStringLiteral("%1[type %2%3]").arg(w->resourceClass()).arg(int(w->windowType()))
                            .arg(w->isPopupWindow() ? QStringLiteral(" popup") : QString());
            }
        }
        static QString last;
        const QString line = seen.join(QStringLiteral(", "));
        if (line != last) {
            last = line;
            qInfo("nativedesk: press with no plasmoid popup; windows: %s", qPrintable(line));
        }
        return;
    }
    Window *target = input()->findToplevel(pos);
    // A press inside a popup (or its menus), or on the panel, whose buttons
    // open and close popups themselves, leaves them.
    if (target && (popups.contains(target) || target->isDock() || target->isPopupWindow())) {
        return;
    }
    qInfo("nativedesk: press outside %lld plasmoid popup(s), on %s; closing them", qlonglong(popups.size()),
          target ? qPrintable(target->resourceClass() + QLatin1Char(' ') + target->caption()) : "nothing");
    for (Window *w : popups) {
        w->closeWindow();
    }
    // Plasma also hides its popups when they lose focus: give focus to what
    // was pressed (the desktop, a window), as a desktop session would.
    if (target && target->wantsInput()) {
        workspace()->activateWindow(target, true);
    }
}

// Plasma hides a plasmoid's popup (Kickoff, the calendar...) when the popup
// loses focus, which is the cue a press elsewhere gives. That needs the popup
// to have had focus: give it focus when it opens, and log it.
static void focusAppletPopupsWhenShown()
{
    static bool connected = false;
    if (connected || !workspace()) {
        return;
    }
    connected = true;
    QObject::connect(workspace(), &Workspace::windowAdded, workspace(), [](Window *w) {
        qInfo("nativedesk: window opened: %s [type %d]%s", qPrintable(w->resourceClass()), int(w->windowType()),
              isPlasmoidPopup(w) ? " plasmoid popup, focusing it" : "");
        if (isPlasmoidPopup(w)) {
            workspace()->activateWindow(w, true);
        }
    });
    QObject::connect(workspace(), &Workspace::windowActivated, workspace(), [](Window *w) {
        qInfo("nativedesk: focus on %s", w ? qPrintable(w->resourceClass() + QStringLiteral(" [type %1]").arg(int(w->windowType()))) : "nothing");
    });
}

void NativeDeskInputDevice::pointer(const QPointF &pos, uint32_t buttons)
{
    focusAppletPopupsWhenShown();
    const auto time = now();
    Q_EMIT pointerMotionAbsolute(pos, time, this);
    static const struct { uint32_t bit, button; } map[] = {{1, BTN_LEFT}, {2, BTN_RIGHT}, {4, BTN_MIDDLE}};
    if (buttons & ~m_buttons) {
        closeAppletPopups(pos);
    }
    for (const auto &b : map) {
        if ((buttons ^ m_buttons) & b.bit) {
            Q_EMIT pointerButtonChanged(b.button, (buttons & b.bit) ? PointerButtonState::Pressed : PointerButtonState::Released, time, this);
        }
    }
    m_buttons = buttons;
    Q_EMIT pointerFrame(this);
}

void NativeDeskInputDevice::scroll(qreal dx, qreal dy)
{
    // The compositor sends pixels, positive when content should move up (like
    // a wheel turned towards the user); KWin's axis deltas use the same sign.
    const auto time = now();
    if (dy != 0) {
        Q_EMIT pointerAxisChanged(PointerAxis::Vertical, dy, 0, PointerAxisSource::Finger, false, time, this);
    }
    if (dx != 0) {
        Q_EMIT pointerAxisChanged(PointerAxis::Horizontal, dx, 0, PointerAxisSource::Finger, false, time, this);
    }
    Q_EMIT pointerFrame(this);
}

void NativeDeskInputDevice::evdevKey(uint32_t key, bool down)
{
    Q_EMIT keyChanged(key, down ? KeyboardKeyState::Pressed : KeyboardKeyState::Released, now(), this);
}

// Android key codes (android/keycodes.h) to Linux evdev codes, which is what
// KWin and xkbcommon speak.
static uint32_t evdevFromAndroid(int code)
{
    if (code >= 29 && code <= 54) { // KEYCODE_A..Z
        static const uint32_t letters[] = {KEY_A, KEY_B, KEY_C, KEY_D, KEY_E, KEY_F, KEY_G, KEY_H, KEY_I, KEY_J, KEY_K, KEY_L, KEY_M,
                                           KEY_N, KEY_O, KEY_P, KEY_Q, KEY_R, KEY_S, KEY_T, KEY_U, KEY_V, KEY_W, KEY_X, KEY_Y, KEY_Z};
        return letters[code - 29];
    }
    if (code >= 8 && code <= 16) { // KEYCODE_1..9
        return KEY_1 + (code - 8);
    }
    if (code >= 131 && code <= 140) { // KEYCODE_F1..F10
        return KEY_F1 + (code - 131);
    }
    switch (code) {
    case 7: return KEY_0;
    case 141: return KEY_F11;
    case 142: return KEY_F12;
    case 19: return KEY_UP;
    case 20: return KEY_DOWN;
    case 21: return KEY_LEFT;
    case 22: return KEY_RIGHT;
    case 55: return KEY_COMMA;
    case 56: return KEY_DOT;
    case 57: return KEY_LEFTALT;
    case 58: return KEY_RIGHTALT;
    case 59: return KEY_LEFTSHIFT;
    case 60: return KEY_RIGHTSHIFT;
    case 61: return KEY_TAB;
    case 62: return KEY_SPACE;
    case 66: return KEY_ENTER;
    case 67: return KEY_BACKSPACE;
    case 68: return KEY_GRAVE;
    case 69: return KEY_MINUS;
    case 70: return KEY_EQUAL;
    case 71: return KEY_LEFTBRACE;
    case 72: return KEY_RIGHTBRACE;
    case 73: return KEY_BACKSLASH;
    case 74: return KEY_SEMICOLON;
    case 75: return KEY_APOSTROPHE;
    case 76: return KEY_SLASH;
    case 92: return KEY_PAGEUP;
    case 93: return KEY_PAGEDOWN;
    case 111: return KEY_ESC;
    case 112: return KEY_DELETE;
    case 113: return KEY_LEFTCTRL;
    case 114: return KEY_RIGHTCTRL;
    case 115: return KEY_CAPSLOCK;
    case 117: return KEY_LEFTMETA;
    case 118: return KEY_RIGHTMETA;
    case 122: return KEY_HOME;
    case 123: return KEY_END;
    case 124: return KEY_INSERT;
    case 160: return KEY_KPENTER;
    }
    return 0;
}

// Characters the on-screen keyboard sends without a key code, as the US
// layout keys (and whether Shift is needed) that type them.
static uint32_t evdevFromChar(char32_t c, bool *shift)
{
    *shift = false;
    if (c >= 'a' && c <= 'z') {
        return evdevFromAndroid(29 + int(c - 'a'));
    }
    if (c >= 'A' && c <= 'Z') {
        *shift = true;
        return evdevFromAndroid(29 + int(c - 'A'));
    }
    if (c >= '1' && c <= '9') {
        return KEY_1 + (c - '1');
    }
    static const char plain[] = "0 \n\t`-=[]\;',./";
    static const uint32_t plainKeys[] = {KEY_0, KEY_SPACE, KEY_ENTER, KEY_TAB, KEY_GRAVE, KEY_MINUS, KEY_EQUAL, KEY_LEFTBRACE,
                                         KEY_RIGHTBRACE, KEY_BACKSLASH, KEY_SEMICOLON, KEY_APOSTROPHE, KEY_COMMA, KEY_DOT, KEY_SLASH};
    static const char shifted[] = ")!@#$%^&*(~_+{}|:\"<>?";
    static const uint32_t shiftedKeys[] = {KEY_0, KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9, KEY_GRAVE,
                                           KEY_MINUS, KEY_EQUAL, KEY_LEFTBRACE, KEY_RIGHTBRACE, KEY_BACKSLASH, KEY_SEMICOLON,
                                           KEY_APOSTROPHE, KEY_COMMA, KEY_DOT, KEY_SLASH};
    if (c < 128) {
        if (const char *p = strchr(plain, int(c)); p && c) {
            return plainKeys[p - plain];
        }
        if (const char *p = strchr(shifted, int(c)); p && c) {
            *shift = true;
            return shiftedKeys[p - shifted];
        }
    }
    return 0;
}

void NativeDeskInputDevice::key(int androidKeyCode, int unicode, bool down)
{
    if (uint32_t k = evdevFromAndroid(androidKeyCode)) {
        if (k == KEY_LEFTSHIFT || k == KEY_RIGHTSHIFT) {
            m_shiftHeld = down;
        }
        evdevKey(k, down);
        return;
    }
    // No key code (typed on the on-screen keyboard): press the key that types
    // the character, with Shift around it when needed. Text outside US ASCII
    // needs an input method, which comes later.
    bool shift = false;
    const uint32_t k = unicode > 0 ? evdevFromChar(char32_t(unicode), &shift) : 0;
    if (!k) {
        return;
    }
    const bool addShift = shift && !m_shiftHeld;
    if (down && addShift) {
        evdevKey(KEY_LEFTSHIFT, true);
    }
    evdevKey(k, down);
    if (!down && addShift) {
        evdevKey(KEY_LEFTSHIFT, false);
    }
}

NativeDeskInputBackend::NativeDeskInputBackend(NativeDeskBackend *backend)
    : m_backend(backend)
{
}

void NativeDeskInputBackend::initialize()
{
    Q_EMIT deviceAdded(m_backend->pointerDevice());
    Q_EMIT deviceAdded(m_backend->keyboardDevice());
}

// ---- rendering (QPainter) ------------------------------------------------------

NativeDeskQPainterLayer::NativeDeskQPainterLayer(NativeDeskOutput *output, NativeDeskBackend *backend)
    : OutputLayer(output)
    , m_backend(backend)
{
}

std::optional<OutputLayerBeginFrameInfo> NativeDeskQPainterLayer::doBeginFrame()
{
    // The whole frame is painted every time, as KWin's virtual backend does:
    // repainting only what changed left trails behind the cursor at
    // fractional scales (the damage, in logical pixels, didn't cover what
    // had been drawn in screen pixels). The region is the screen's pixel
    // size, which covers the screen in either kind of pixel.
    const QSize size = m_output->modeSize();
    if (m_image.size() != size) {
        m_image = QImage(size, QImage::Format_RGBA8888_Premultiplied);
        m_image.fill(Qt::black);
    }
    m_renderTime = std::make_unique<CpuRenderTimeQuery>();
    return OutputLayerBeginFrameInfo{
        .renderTarget = RenderTarget(&m_image),
        .repaint = QRegion(QRect(QPoint(0, 0), size)),
    };
}

bool NativeDeskQPainterLayer::doEndFrame(const QRegion &renderedRegion, const QRegion &damagedRegion, OutputFrame *frame)
{
    m_renderTime->end();
    frame->addRenderTimeQuery(std::move(m_renderTime));
    m_backend->submit(m_image);
    return true;
}

DrmDevice *NativeDeskQPainterLayer::scanoutDevice() const
{
    return nullptr;
}

QHash<uint32_t, QList<uint64_t>> NativeDeskQPainterLayer::supportedDrmFormats() const
{
    return {};
}

NativeDeskQPainterBackend::NativeDeskQPainterBackend(NativeDeskBackend *backend)
    : m_backend(backend)
    , m_layer(std::make_unique<NativeDeskQPainterLayer>(backend->output(), backend))
{
}

NativeDeskQPainterBackend::~NativeDeskQPainterBackend() = default;

OutputLayer *NativeDeskQPainterBackend::primaryLayer(Output *output)
{
    return m_layer.get();
}

bool NativeDeskQPainterBackend::present(Output *output, const std::shared_ptr<OutputFrame> &frame)
{
    static_cast<NativeDeskOutput *>(output)->present(frame);
    return true;
}

// ---- rendering (OpenGL ES on the phone's GPU) -------------------------------------

static_assert(NativeDeskBackend::BufferCount == 3, "NativeDeskEglLayer::m_targets");

// EGL_ANDROID_get_native_client_buffer, looked up at run time.
using GetNativeClientBuffer = EGLClientBuffer (*)(const AHardwareBuffer *);
static GetNativeClientBuffer getNativeClientBuffer()
{
    static auto fn = reinterpret_cast<GetNativeClientBuffer>(eglGetProcAddress("eglGetNativeClientBufferANDROID"));
    return fn;
}

NativeDeskEglLayer::NativeDeskEglLayer(NativeDeskOutput *output, NativeDeskEglBackend *backend)
    : OutputLayer(output)
    , m_backend(backend)
{
}

NativeDeskEglLayer::~NativeDeskEglLayer()
{
    m_backend->openglContext()->makeCurrent();
    freeTargets();
}

void NativeDeskEglLayer::freeTargets()
{
    for (Target &t : m_targets) {
        t.framebuffer.reset();
        t.texture.reset(); // destroys its EGLImage
        t.ahb = nullptr;
    }
    m_current = -1;
}

bool NativeDeskEglLayer::prepareTarget(int id)
{
    AHardwareBuffer *ahb = m_backend->backend()->buffer(id);
    Target &t = m_targets[id];
    if (t.ahb == ahb && t.framebuffer) {
        return true;
    }
    t.framebuffer.reset();
    t.texture.reset();
    t.ahb = ahb;
    AHardwareBuffer_Desc d;
    AHardwareBuffer_describe(ahb, &d);
    EglDisplay *display = m_backend->eglDisplayObject();
    const EGLint attribs[] = {EGL_IMAGE_PRESERVED_KHR, EGL_TRUE, EGL_NONE};
    EGLImageKHR image = eglCreateImageKHR(display->handle(), EGL_NO_CONTEXT, EGL_NATIVE_BUFFER_ANDROID, getNativeClientBuffer()(ahb), attribs);
    if (image == EGL_NO_IMAGE_KHR) {
        qWarning("nativedesk: can't make an EGLImage of buffer %d (0x%x)", id, eglGetError());
        return false;
    }
    t.texture = EGLImageTexture::create(display, image, GL_RGBA8, QSize(d.width, d.height), false);
    if (!t.texture) {
        qWarning("nativedesk: can't make a texture of buffer %d", id);
        return false;
    }
    t.texture->setFilter(GL_LINEAR);
    t.texture->setWrapMode(GL_CLAMP_TO_EDGE);
    t.framebuffer = std::make_unique<GLFramebuffer>(t.texture.get());
    if (!t.framebuffer->valid()) {
        qWarning("nativedesk: buffer %d can't be drawn into", id);
        t.framebuffer.reset();
        return false;
    }
    return true;
}

std::optional<OutputLayerBeginFrameInfo> NativeDeskEglLayer::doBeginFrame()
{
    if (!m_backend->openglContext()->makeCurrent()) {
        return std::nullopt;
    }
    NativeDeskBackend *nd = m_backend->backend();
    const QSize size = m_output->modeSize();
    const quint64 generation = nd->bufferGeneration();
    if (!nd->ensureBuffers(size, true)) {
        return std::nullopt;
    }
    if (nd->bufferGeneration() != generation) {
        freeTargets(); // new buffers: their old images go
    }
    m_current = nd->acquire();
    if (!prepareTarget(m_current)) {
        return std::nullopt;
    }
    m_query = std::make_unique<GLRenderTimeQuery>(m_backend->openglContextRef());
    m_query->begin();
    // The whole frame every time (no buffer age to go by).
    return OutputLayerBeginFrameInfo{
        .renderTarget = RenderTarget(m_targets[m_current].framebuffer.get()),
        .repaint = infiniteRegion(),
    };
}

bool NativeDeskEglLayer::doEndFrame(const QRegion &renderedRegion, const QRegion &damagedRegion, OutputFrame *frame)
{
    m_query->end();
    frame->addRenderTimeQuery(std::move(m_query));
    // The compositor's GPU waits on this fence instead of KWin waiting here.
    EGLNativeFence fence(m_backend->eglDisplayObject());
    int fd = -1;
    if (fence.isValid() && fence.fileDescriptor().isValid()) {
        fd = fence.takeFileDescriptor().take();
    } else {
        glFinish();
    }
    m_backend->backend()->commit(m_current, fd);
    if (fd >= 0) {
        ::close(fd);
    }
    return true;
}

DrmDevice *NativeDeskEglLayer::scanoutDevice() const
{
    return nullptr;
}

QHash<uint32_t, QList<uint64_t>> NativeDeskEglLayer::supportedDrmFormats() const
{
    return {};
}

std::shared_ptr<GLTexture> NativeDeskEglLayer::texture() const
{
    return m_current >= 0 ? m_targets[m_current].texture : nullptr;
}

NativeDeskEglBackend::NativeDeskEglBackend(NativeDeskBackend *backend)
    : m_backend(backend)
{
}

NativeDeskEglBackend::~NativeDeskEglBackend()
{
    m_layer.reset();
    cleanup();
}

void NativeDeskEglBackend::init()
{
    initClientExtensions();
    if (!m_backend->sceneEglDisplayObject()) {
        m_backend->setEglDisplay(EglDisplay::create(eglGetDisplay(EGL_DEFAULT_DISPLAY)));
    }
    EglDisplay *display = m_backend->sceneEglDisplayObject();
    if (!display) {
        setFailed(QStringLiteral("nativedesk: no EGL display"));
        return;
    }
    setEglDisplay(display);
    for (const QByteArray &ext : {QByteArrayLiteral("EGL_ANDROID_get_native_client_buffer"), QByteArrayLiteral("EGL_ANDROID_image_native_buffer"), QByteArrayLiteral("EGL_KHR_image_base")}) {
        if (!hasExtension(ext)) {
            setFailed(QStringLiteral("nativedesk: EGL lacks ") + QString::fromLatin1(ext));
            return;
        }
    }
    if (!getNativeClientBuffer()) {
        setFailed(QStringLiteral("nativedesk: no eglGetNativeClientBufferANDROID"));
        return;
    }
    if (!createContext(EGL_NO_CONFIG_KHR) || !openglContext()->makeCurrent()) {
        setFailed(QStringLiteral("nativedesk: can't make an OpenGL ES context"));
        return;
    }
    if (!openglContext()->hasOpenglExtension(QByteArrayLiteral("GL_OES_EGL_image"))) {
        setFailed(QStringLiteral("nativedesk: GLES lacks GL_OES_EGL_image"));
        return;
    }
    qInfo("nativedesk: compositing on the GPU: %s, %s", glGetString(GL_RENDERER), glGetString(GL_VERSION));
    initWayland();
    deskdroidAhbCreateGlobal(*waylandServer()->display());
    m_layer = std::make_unique<NativeDeskEglLayer>(m_backend->output(), this);
}

OutputLayer *NativeDeskEglBackend::primaryLayer(Output *output)
{
    return m_layer.get();
}

bool NativeDeskEglBackend::present(Output *output, const std::shared_ptr<OutputFrame> &frame)
{
    static_cast<NativeDeskOutput *>(output)->present(frame);
    return true;
}

std::pair<std::shared_ptr<GLTexture>, ColorDescription> NativeDeskEglBackend::textureForOutput(Output *output) const
{
    return {m_layer ? m_layer->texture() : nullptr, ColorDescription::sRGB};
}

// ---- backend: the connection to the compositor ----------------------------------

NativeDeskBackend::NativeDeskBackend(const QSize &size, qreal scale)
    : m_size(size)
    , m_scale(scale)
    , m_pointer(std::make_unique<NativeDeskInputDevice>(false))
    , m_keyboard(std::make_unique<NativeDeskInputDevice>(true))
{
}

NativeDeskBackend::~NativeDeskBackend()
{
    delete m_notifier;
    freeBuffers();
    if (m_output) {
        m_output->unref();
    }
    if (m_fd >= 0) {
        ::close(m_fd);
    }
}

bool NativeDeskBackend::initialize()
{
    m_fd = socket(AF_UNIX, SOCK_SEQPACKET | SOCK_CLOEXEC, 0);
    sockaddr_un a = {};
    a.sun_family = AF_UNIX;
    const size_t len = strlen(NDESK_SOCKET);
    memcpy(a.sun_path + 1, NDESK_SOCKET, len);
    const socklen_t alen = offsetof(sockaddr_un, sun_path) + 1 + len;
    if (m_fd < 0 || ::connect(m_fd, reinterpret_cast<sockaddr *>(&a), alen) < 0) {
        qWarning("nativedesk: can't reach the DeskDroid compositor");
        return false;
    }
    // 0x0: the whole screen, no title bar. The answer says how big that is.
    ndesk_msg m = {};
    m.op = NDESK_HELLO;
    m.hello.version = NDESK_VERSION;
    snprintf(m.hello.title, NDESK_TITLE_MAX, "KWin");
    send(m);
    pollfd p = {m_fd, POLLIN, 0};
    if (poll(&p, 1, 5000) <= 0 || recv(m_fd, &m, sizeof m, 0) != sizeof m || m.op != NDESK_CONFIGURE) {
        qWarning("nativedesk: the compositor didn't answer");
        return false;
    }
    if (m.configure.width && m.configure.height) {
        m_size = QSize(m.configure.width, m.configure.height);
    }
    qInfo("nativedesk: screen %dx%d at scale %.2f", m_size.width(), m_size.height(), m_scale);
    m_notifier = new QSocketNotifier(m_fd, QSocketNotifier::Read);
    connect(m_notifier, &QSocketNotifier::activated, this, &NativeDeskBackend::readMessages);

    static NativeDeskBackend *self;
    self = this;
    deskdroidTextInputHook = [](bool active) { self->setTextInputActive(active); };

    m_output = new NativeDeskOutput(this, m_size, m_scale);
    Q_EMIT outputAdded(m_output);
    Q_EMIT outputsQueried();
    return true;
}

std::unique_ptr<InputBackend> NativeDeskBackend::createInputBackend()
{
    return std::make_unique<NativeDeskInputBackend>(this);
}

std::unique_ptr<QPainterBackend> NativeDeskBackend::createQPainterBackend()
{
    return std::make_unique<NativeDeskQPainterBackend>(this);
}

std::unique_ptr<EglBackend> NativeDeskBackend::createOpenGLBackend()
{
    return std::make_unique<NativeDeskEglBackend>(this);
}

EglDisplay *NativeDeskBackend::sceneEglDisplayObject() const
{
    return m_eglDisplay.get();
}

void NativeDeskBackend::setEglDisplay(std::unique_ptr<EglDisplay> &&display)
{
    m_eglDisplay = std::move(display);
}

QList<CompositingType> NativeDeskBackend::supportedCompositors() const
{
    // The GPU first; KWin falls back to the CPU (QPainter) if it can't start.
    // KWIN_COMPOSE picks one: O2ES for the GPU, Q for the CPU.
    return {OpenGLCompositing, QPainterCompositing};
}

Outputs NativeDeskBackend::outputs() const
{
    Outputs outputs;
    if (m_output) {
        outputs.append(m_output);
    }
    return outputs;
}

NativeDeskOutput *NativeDeskBackend::output() const
{
    return m_output;
}

NativeDeskInputDevice *NativeDeskBackend::pointerDevice() const
{
    return m_pointer.get();
}

NativeDeskInputDevice *NativeDeskBackend::keyboardDevice() const
{
    return m_keyboard.get();
}

void NativeDeskBackend::send(const ndesk_msg &m, int passFd)
{
    iovec iov = {const_cast<ndesk_msg *>(&m), sizeof m};
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
    if (sendmsg(m_fd, &h, MSG_NOSIGNAL) < 0) {
        qWarning("nativedesk: the compositor went away");
    }
}

void NativeDeskBackend::setTextInputActive(bool active)
{
    if (active == m_textInputActive) {
        return;
    }
    m_textInputActive = active;
    ndesk_msg m = {};
    m.op = NDESK_IME;
    m.ime.show = active;
    send(m);
}

float deskdroidSafePx[4] = {};

QMargins deskdroidSafeMargins(const Output *output)
{
    const qreal s = output ? output->scale() : 1;
    return QMargins(std::ceil(deskdroidSafePx[0] / s), std::ceil(deskdroidSafePx[1] / s),
                    std::ceil(deskdroidSafePx[2] / s), std::ceil(deskdroidSafePx[3] / s));
}

void NativeDeskBackend::readMessages()
{
    ndesk_msg m;
    while (recv(m_fd, &m, sizeof m, MSG_DONTWAIT) == sizeof m) {
        switch (m.op) {
        case NDESK_RELEASE:
            if (m.release.id < BufferCount) {
                m_buffers[m.release.id].busy = false;
            }
            break;
        case NDESK_FRAME:
            if (m_output) {
                m_output->framePresented();
            }
            break;
        case NDESK_POINTER:
            // The compositor speaks screen pixels, KWin logical ones, at
            // whatever scale KWin's output configuration settled on.
            m_pointer->pointer(QPointF(m.pointer.x, m.pointer.y) / outputScale(), m.pointer.buttons);
            break;
        case NDESK_SCROLL:
            m_pointer->scroll(m.scroll.dx / outputScale(), m.scroll.dy / outputScale());
            break;
        case NDESK_CONFIGURE:
            // After the first one: the screen's size changed (rotation).
            if (m.configure.width && m.configure.height) {
                m_size = QSize(m.configure.width, m.configure.height);
                if (m_output) {
                    m_output->setPixelSize(m_size);
                    // As KWin's nested Wayland backend does on a resize: the
                    // workspace lays out panels, windows and screen edges again.
                    Q_EMIT outputsQueried();
                    // Draw the new layout now, not at the next mouse move: once the
                    // workspace has moved things, and again when panels have followed.
                    for (int ms : {0, 150}) {
                        QTimer::singleShot(ms, this, [] {
                            if (Compositor::self()) {
                                Compositor::self()->scene()->addRepaintFull();
                            }
                        });
                    }
                }
            }
            break;
        case NDESK_SCALE:
            if (m_output && m.scale.scale > 0) {
                m_output->setUserScale(m.scale.scale);
                Q_EMIT outputsQueried();
            }
            break;
        case NDESK_SAFE:
            // Where the cutout and rounded corners are: panels (layer shell)
            // and maximized windows keep out of it, see add-to-kwin.py.
            deskdroidSafePx[0] = m.safe.left;
            deskdroidSafePx[1] = m.safe.top;
            deskdroidSafePx[2] = m.safe.right;
            deskdroidSafePx[3] = m.safe.bottom;
            if (Workspace::self()) {
                Workspace::self()->scheduleRearrange();
            }
            break;
        case NDESK_KEY:
            m_keyboard->key(m.key.keycode, m.key.unicode, m.key.down);
            break;
        }
    }
}

int NativeDeskBackend::acquire()
{
    // Like a real swap: wait for the compositor to give a buffer back.
    for (int tries = 0; tries < 50; tries++) {
        for (int i = 0; i < BufferCount; i++) {
            if (!m_buffers[i].busy) {
                return i;
            }
        }
        pollfd p = {m_fd, POLLIN, 0};
        poll(&p, 1, 20);
        readMessages();
    }
    qWarning("nativedesk: no buffer came back, reusing one");
    return 0;
}

bool NativeDeskBackend::ensureBuffers(const QSize &size, bool gpu)
{
    if (m_buffers[0].ahb && size == m_bufferSize && gpu == m_gpuBuffers) {
        return true;
    }
    freeBuffers();
    m_bufferSize = size;
    m_gpuBuffers = gpu;
    m_generation++;
    for (int i = 0; i < BufferCount; i++) {
        AHardwareBuffer_Desc d = {};
        d.width = size.width();
        d.height = size.height();
        d.layers = 1;
        d.format = AHARDWAREBUFFER_FORMAT_R8G8B8A8_UNORM;
        d.usage = AHARDWAREBUFFER_USAGE_GPU_SAMPLED_IMAGE
            | (gpu ? AHARDWAREBUFFER_USAGE_GPU_FRAMEBUFFER : AHARDWAREBUFFER_USAGE_CPU_WRITE_OFTEN);
        if (AHardwareBuffer_allocate(&d, &m_buffers[i].ahb) != 0) {
            qWarning("nativedesk: can't allocate a %dx%d buffer", size.width(), size.height());
            return false;
        }
        ndesk_msg m = {};
        m.op = NDESK_BUFFER;
        m.buffer.id = i;
        send(m);
        AHardwareBuffer_sendHandleToUnixSocket(m_buffers[i].ahb, m_fd);
    }
    return true;
}

void NativeDeskBackend::freeBuffers()
{
    for (Buffer &b : m_buffers) {
        if (b.ahb) {
            AHardwareBuffer_release(b.ahb);
        }
        b = Buffer();
    }
}

void NativeDeskBackend::submit(const QImage &image)
{
    if (m_fd < 0 || !ensureBuffers(image.size(), false)) {
        return;
    }
    const int id = acquire();
    Buffer &b = m_buffers[id];
    AHardwareBuffer_Desc d;
    AHardwareBuffer_describe(b.ahb, &d);
    void *dst = nullptr;
    if (AHardwareBuffer_lock(b.ahb, AHARDWAREBUFFER_USAGE_CPU_WRITE_OFTEN, -1, nullptr, &dst) != 0) {
        return;
    }
    const int rowBytes = std::min<int>(image.width(), d.width) * 4;
    for (int y = 0; y < std::min<int>(image.height(), d.height); y++) {
        memcpy(static_cast<char *>(dst) + size_t(y) * d.stride * 4, image.constScanLine(y), rowBytes);
    }
    int fence = -1;
    AHardwareBuffer_unlock(b.ahb, &fence);
    commit(id, fence);
    if (fence >= 0) {
        ::close(fence);
    }
}

void NativeDeskBackend::commit(int id, int fence)
{
    ndesk_msg m = {};
    m.op = NDESK_COMMIT;
    m.commit.id = id;
    m.commit.has_fence = fence >= 0;
    m.commit.y_invert = 0;
    send(m, fence);
    m_buffers[id].busy = true;
}

} // namespace KWin

#include "moc_nativedesk_backend.cpp"

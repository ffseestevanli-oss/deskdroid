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
#include "inputmethod.h"
#include "main.h"
#include "deskdroid_ahb_server.h"
#include "nativedesk_bridge.h"
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

#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusVariant>
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
// focused surface has an enabled text input, and its purpose and hints.
namespace KWin { extern void (*deskdroidTextInputHook)(bool, int, int); }
// Set in KWin's InputMethod::surroundingTextChanged: the focused field's text
// around the cursor, with the cursor and the selection's other end (UTF-16).
namespace KWin { extern void (*deskdroidSurroundingHook)(const QString &, int, int); }

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

// The user picked another scale in DeskDroid's menu: applied now, the way
// KDE's display settings do it (an output configuration through the
// workspace, which lays windows, panels and the desktop out again and tells
// the apps; setting the output's state alone changed the number but nothing
// on screen until a restart). Before the workspace exists, the state only.
void NativeDeskOutput::setUserScale(qreal scale)
{
    if (qFuzzyCompare(scale, this->scale())) {
        return;
    }
    if (Workspace::self()) {
        OutputConfiguration config;
        config.changeSet(this)->scale = scale;
        Workspace::self()->applyOutputConfiguration(config);
    } else {
        State next = m_state;
        next.scale = scale;
        setState(next);
    }
    qInfo("nativedesk: scale now %.2f", scale);
}

// ---- input -------------------------------------------------------------------

NativeDeskInputDevice::NativeDeskInputDevice(bool keyboard, bool touch)
    : m_keyboard(keyboard)
    , m_touch(touch)
{
}

QString NativeDeskInputDevice::name() const
{
    return m_keyboard ? QStringLiteral("DeskDroid keyboard")
        : m_touch     ? QStringLiteral("DeskDroid touchscreen")
                      : QStringLiteral("DeskDroid pointer");
}

bool NativeDeskInputDevice::isEnabled() const { return true; }
void NativeDeskInputDevice::setEnabled(bool) { }
bool NativeDeskInputDevice::isKeyboard() const { return m_keyboard; }
bool NativeDeskInputDevice::isPointer() const { return !m_keyboard && !m_touch; }
bool NativeDeskInputDevice::isTouchpad() const { return false; }
bool NativeDeskInputDevice::isTouch() const { return m_touch; }
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

// Closes every open plasmoid popup, for something other than a press (which
// closeAppletPopups handles).
static void closeOpenAppletPopups(const char *why)
{
    if (!workspace()) {
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
        return;
    }
    qInfo("nativedesk: %s; closing %lld plasmoid popup(s)", why, qlonglong(popups.size()));
    for (Window *w : std::as_const(popups)) {
        w->closeWindow();
    }
}

// The task bar and window list minimize and restore windows from a panel,
// which a press there leaves alone (its applet buttons open and close popups
// themselves): a window minimized or restored closes the popups too.
static void closeAppletPopupsOnMinimize(Window *w)
{
    QObject::connect(w, &Window::minimizedChanged, workspace(), [w] {
        closeOpenAppletPopups(w->isMinimized() ? "a window was minimized" : "a window was restored");
    });
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
        } else {
            closeAppletPopupsOnMinimize(w);
        }
    });
    const auto windows = workspace()->windows();
    for (Window *w : windows) {
        if (!isPlasmoidPopup(w)) {
            closeAppletPopupsOnMinimize(w);
        }
    }
    QObject::connect(workspace(), &Workspace::windowActivated, workspace(), [](Window *w) {
        qInfo("nativedesk: focus on %s", w ? qPrintable(w->resourceClass() + QStringLiteral(" [type %1]").arg(int(w->windowType()))) : "nothing");
        // Another window taking focus (a task bar or window list click, a
        // new app) closes the popups, as their losing focus does on a desktop.
        if (w && !isPlasmoidPopup(w) && !w->isDock() && !w->isPopupWindow()) {
            closeOpenAppletPopups("another window took focus");
        }
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

// Direct touch: the fingers reach KWin as a touchscreen's, so KWin and the
// apps (wl_touch) do what they do with touch: lists and pages follow the
// finger and keep going with a flick, two fingers pinch, title bars drag,
// panels and Plasma's popups take taps. No mouse is emulated here.
void NativeDeskInputDevice::touch(uint32_t kind, int32_t id, const QPointF &pos)
{
    focusAppletPopupsWhenShown();
    const auto time = now();
    switch (kind) {
    case NDESK_TOUCH_DOWN:
        if (m_fingers.contains(id)) { // a lift that never came: end that one first
            Q_EMIT touchUp(id, time, this);
        }
        if (m_fingers.isEmpty()) {
            closeAppletPopups(pos);
        }
        m_fingers.insert(id);
        Q_EMIT touchDown(id, pos, time, this);
        break;
    case NDESK_TOUCH_MOTION:
        if (m_fingers.contains(id)) {
            Q_EMIT touchMotion(id, pos, time, this);
        }
        break;
    case NDESK_TOUCH_UP:
        if (m_fingers.remove(id)) {
            Q_EMIT touchUp(id, time, this);
        }
        break;
    case NDESK_TOUCH_CANCEL:
        if (!m_fingers.isEmpty()) {
            m_fingers.clear();
            Q_EMIT touchCanceled(this);
        }
        break;
    case NDESK_TOUCH_FRAME:
        Q_EMIT touchFrame(this);
        break;
    }
}

void NativeDeskInputDevice::scroll(qreal dx, qreal dy, bool wheel)
{
    // The compositor sends pixels, positive when content should move up (like
    // a wheel turned towards the user); KWin's axis deltas use the same sign.
    // A wheel's steps come in 120ths of a click: apps scroll by lines, like
    // with a mouse (libinput: 15 degrees a click), and a browser doesn't take
    // them for touchpad swipes (back, forward).
    const auto time = now();
    const auto source = wheel ? PointerAxisSource::Wheel : PointerAxisSource::Finger;
    if (dy != 0) {
        Q_EMIT pointerAxisChanged(PointerAxis::Vertical, wheel ? dy * 15 / 120 : dy, wheel ? dy : 0, source, false, time, this);
    }
    if (dx != 0) {
        Q_EMIT pointerAxisChanged(PointerAxis::Horizontal, wheel ? dx * 15 / 120 : dx, wheel ? dx : 0, source, false, time, this);
    }
    Q_EMIT pointerFrame(this);
}

void NativeDeskInputDevice::evdevKey(uint32_t key, bool down)
{
    if (down ? m_down.contains(key) : !m_down.contains(key)) {
        return; // already down (Android's auto-repeat), or not down
    }
    if (down) {
        m_down.insert(key);
    } else {
        m_down.remove(key);
    }
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
    // Media keys, for the focused window when no MPRIS player takes them.
    case 79: return KEY_PLAYPAUSE; // KEYCODE_HEADSETHOOK
    case 85: return KEY_PLAYPAUSE;
    case 86: return KEY_STOPCD;
    case 87: return KEY_NEXTSONG;
    case 88: return KEY_PREVIOUSSONG;
    case 89: return KEY_REWIND;
    case 90: return KEY_FASTFORWARD;
    case 126: return KEY_PLAYCD;
    case 127: return KEY_PAUSECD;
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
        evdevKey(k, down);
        return;
    }
    // No key code (typed on the on-screen keyboard): press the key that types
    // the character, with Shift around it when needed. Text outside US ASCII
    // needs an input method, which comes later. The release undoes what the
    // press did (the character can differ by then, if Shift went up first).
    if (!down) {
        const auto typed = m_typed.take(androidKeyCode ? androidKeyCode : unicode);
        if (typed.first) {
            evdevKey(typed.first, false);
            if (typed.second) {
                evdevKey(KEY_LEFTSHIFT, false);
            }
            return;
        }
    }
    if (down && m_typed.contains(androidKeyCode ? androidKeyCode : unicode)) {
        return; // Android's auto-repeat: still held from the first press
    }
    bool shift = false;
    const uint32_t k = unicode > 0 ? evdevFromChar(char32_t(unicode), &shift) : 0;
    if (!k) {
        return;
    }
    const bool addShift = shift && !m_down.contains(KEY_LEFTSHIFT) && !m_down.contains(KEY_RIGHTSHIFT);
    if (!down) {
        evdevKey(k, false);
        return;
    }
    if (addShift) {
        evdevKey(KEY_LEFTSHIFT, true);
    }
    evdevKey(k, true);
    m_typed.insert(androidKeyCode ? androidKeyCode : unicode, qMakePair(k, addShift));
}

NativeDeskInputBackend::NativeDeskInputBackend(NativeDeskBackend *backend)
    : m_backend(backend)
{
}

void NativeDeskInputBackend::initialize()
{
    Q_EMIT deviceAdded(m_backend->pointerDevice());
    Q_EMIT deviceAdded(m_backend->keyboardDevice());
    Q_EMIT deviceAdded(m_backend->touchDevice());
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
    , m_touch(std::make_unique<NativeDeskInputDevice>(false, true))
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
    deskdroidTextInputHook = [](bool active, int purpose, int hints) { self->setTextInputActive(active, purpose, hints); };
    deskdroidSurroundingHook = [](const QString &text, int cursor, int anchor) { self->setSurrounding(text, cursor, anchor); };

    // The clipboard and media keys shared with the phone (nativedesk_bridge.h).
    m_clipboard = std::make_unique<NativeDeskClipboard>(
        [this](int fd) {
            ndesk_msg c = {};
            c.op = NDESK_CLIP;
            c.clip.kind = NDESK_CLIP_DESKTOP;
            send(c, fd);
        },
        [this](int fd) {
            ndesk_msg c = {};
            c.op = NDESK_CLIP;
            c.clip.kind = NDESK_CLIP_PASTE;
            send(c, fd);
        });
    m_media = std::make_unique<NativeDeskMedia>([this](uint32_t state) {
        ndesk_msg p = {};
        p.op = NDESK_PLAYING;
        p.playing.state = state;
        send(p);
    });

    m_output = new NativeDeskOutput(this, m_size, m_scale);
    Q_EMIT outputAdded(m_output);
    Q_EMIT outputsQueried();
    // KWin restores the scale it saved last (now that changes go through its
    // output configuration, which saves them); DeskDroid's menu has the say,
    // so its scale goes on again once the workspace is up.
    connect(kwinApp(), &Application::workspaceCreated, this, [this] {
        QTimer::singleShot(0, this, [this] {
            if (m_output) {
                m_output->setUserScale(m_scale);
            }
            m_clipboard->start();
            m_media->start();
        });
    });
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

NativeDeskInputDevice *NativeDeskBackend::touchDevice() const
{
    return m_touch.get();
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

void NativeDeskBackend::setTextInputActive(bool active, int purpose, int hints)
{
    if (!active) {
        purpose = hints = 0;
    }
    if (active == m_textInputActive && purpose == m_textInputPurpose && hints == m_textInputHints) {
        return;
    }
    m_textInputActive = active;
    m_textInputPurpose = purpose;
    m_textInputHints = hints;
    ndesk_msg m = {};
    m.op = NDESK_IME;
    m.ime.show = active;
    m.ime.purpose = purpose;
    m.ime.hints = hints;
    send(m);
}

void NativeDeskBackend::setSurrounding(const QString &text, int cursor, int anchor)
{
    // Apps report it after every change; the phone hears the latest, a moment later.
    m_surrounding = text.toUtf8();
    m_surroundingCursor = cursor;
    m_surroundingAnchor = anchor;
    if (!m_surroundingPending) {
        m_surroundingPending = true;
        QTimer::singleShot(30, this, &NativeDeskBackend::sendSurrounding);
    }
}

void NativeDeskBackend::sendSurrounding()
{
    m_surroundingPending = false;
    const QByteArray &u = m_surrounding;
    qsizetype off = 0;
    do {
        qsizetype piece = u.size() - off;
        if (piece > NDESK_TEXT_CHUNK) {
            piece = NDESK_TEXT_CHUNK;
            while (piece > 1 && (uchar(u[off + piece]) & 0xC0) == 0x80) {
                piece--; // whole characters
            }
        }
        ndesk_msg m = {};
        m.op = NDESK_TEXT;
        m.text.kind = NDESK_TEXT_SURROUNDING;
        m.text.more = off + piece < u.size();
        m.text.len = uint16_t(piece);
        m.text.a = m_surroundingCursor;
        m.text.b = m_surroundingAnchor;
        memcpy(m.text.text, u.constData() + off, piece);
        send(m);
        off += piece;
    } while (off < u.size());
}

void NativeDeskBackend::text(const ndesk_msg &m)
{
    // Text longer than a packet comes in pieces; the last one has more unset.
    const int len = std::min<int>(m.text.len, NDESK_TEXT_CHUNK);
    m_text.append(m.text.text, len);
    if (m.text.more) {
        return;
    }
    const QString text = QString::fromUtf8(m_text);
    m_text.clear();
    if (InputMethod *im = kwinApp()->inputMethod()) {
        im->deskdroidText(m.text.kind == NDESK_TEXT_COMMIT ? 1 : 2, text, m.text.a);
    }
}

float deskdroidSafePx[4] = {};

// ---- the phone's keyboard ------------------------------------------------------

// A window worth fitting above the keyboard: an app's own window that can be
// moved and resized, not a panel, a plasmoid's popup or a fullscreen game.
static bool dodgeable(Window *w)
{
    return w && !w->isDeleted() && w->isNormalWindow() && !w->isFullScreen() && w->isMovable()
        && w->isResizable() && !isPlasmoidPopup(w);
}

// While the phone's keyboard is up in portrait, the active window is
// maximized into the space above it, so what's typed stays in sight; when
// the keyboard goes (or another window becomes active) it goes back where it
// was, maximized or not. Landscape leaves windows alone: too little height
// is left above a keyboard there.
void NativeDeskBackend::updateKeyboardDodge()
{
    if (!workspace() || !m_output) {
        return;
    }
    if (!m_dodgeConnected) {
        m_dodgeConnected = true;
        connect(workspace(), &Workspace::windowActivated, this, [this] {
            if (m_keyboardPx > 0 || m_dodged) {
                updateKeyboardDodge();
            }
        });
    }
    const QSize px = m_output->pixelSize();
    Window *target = nullptr;
    if (m_keyboardPx > 0 && px.height() > px.width()) {
        target = workspace()->activeWindow();
        if (!dodgeable(target)) {
            target = nullptr;
        }
    }
    if (m_dodged && m_dodged != target) {
        restoreDodged();
    }
    if (!target) {
        return;
    }
    const QRectF screen = m_output->geometryF();
    QRectF area = workspace()->clientArea(MaximizeArea, target);
    area.setBottom(std::min(area.bottom(), screen.bottom() - m_keyboardPx / outputScale()));
    if (area.height() < 120) {
        return; // no room worth having
    }
    if (m_dodged != target) {
        m_dodged = target;
        m_dodgeBefore = target->moveResizeGeometry();
        m_dodgeMaximize = int(target->maximizeMode());
        m_dodgeRestore = target->geometryRestore();
        if (target->maximizeMode() != MaximizeRestore) {
            target->maximize(MaximizeRestore);
        }
        qInfo("nativedesk: keyboard up, fitting %s above it", qPrintable(target->resourceClass()));
    }
    m_dodgeGeometry = area;
    target->moveResize(area);
}

void NativeDeskBackend::restoreDodged()
{
    Window *w = m_dodged;
    m_dodged = nullptr;
    if (!w || w->isDeleted()) {
        return;
    }
    // Moved, resized or maximized by hand meanwhile: it stays as the user left it.
    if (w->moveResizeGeometry() != m_dodgeGeometry || w->maximizeMode() != MaximizeRestore) {
        return;
    }
    if (m_dodgeMaximize != MaximizeRestore) {
        w->maximize(MaximizeMode(m_dodgeMaximize), m_dodgeRestore);
    } else {
        w->moveResize(m_dodgeBefore);
    }
    qInfo("nativedesk: keyboard gone, %s back", qPrintable(w->resourceClass()));
}

QMargins deskdroidSafeMargins(const Output *output)
{
    const qreal s = output ? output->scale() : 1;
    // Sideways only: panels may still touch the top and bottom edges.
    return QMargins(std::ceil(deskdroidSafePx[0] / s), 0, std::ceil(deskdroidSafePx[2] / s), 0);
}

// Windows (maximized, placed) keep out of the same margins as the panels,
// in landscape only: upright, the sides' margins are the rounded corners'
// radius, too much to lose from a narrow screen for corners alone.
QMargins deskdroidWindowMargins(const Output *output)
{
    if (!output) {
        return QMargins();
    }
    const QSize px = output->pixelSize();
    return px.width() > px.height() ? deskdroidSafeMargins(output) : QMargins();
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
            // A click in a text field: the phone's keyboard hears the field's
            // text again once the click has landed, even if it didn't change
            // (it forgets it on a click: the cursor may have moved).
            if (m.pointer.buttons && !m_pointerButtons && m_textInputActive) {
                QTimer::singleShot(150, this, [this] {
                    if (m_textInputActive && !m_surroundingPending) {
                        sendSurrounding();
                    }
                });
            }
            m_pointerButtons = m.pointer.buttons;
            // The compositor speaks screen pixels, KWin logical ones, at
            // whatever scale KWin's output configuration settled on.
            m_pointer->pointer(QPointF(m.pointer.x, m.pointer.y) / outputScale(), m.pointer.buttons);
            break;
        case NDESK_TOUCH:
            // A tap in a text field, as for a click: the phone's keyboard
            // hears the field's text again, once the finger lifts (apps move
            // the cursor on the lift: a report before it had the old one).
            if (m.touch.kind == NDESK_TOUCH_UP && m_textInputActive) {
                QTimer::singleShot(150, this, [this] {
                    if (m_textInputActive && !m_surroundingPending) {
                        sendSurrounding();
                    }
                });
            }
            m_touch->touch(m.touch.kind, m.touch.id, QPointF(m.touch.x, m.touch.y) / outputScale());
            break;
        case NDESK_SCROLL:
            if (m.scroll.wheel) {
                m_pointer->scroll(m.scroll.dx, m.scroll.dy, true);
            } else {
                m_pointer->scroll(m.scroll.dx / outputScale(), m.scroll.dy / outputScale(), false);
            }
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
            if (m.safe.keyboard != m_keyboardPx) {
                m_keyboardPx = m.safe.keyboard;
                updateKeyboardDodge();
            }
            break;
        case NDESK_KEY:
            // Media keys (an earpiece, a remote, a keyboard's) go to the
            // desktop's media players; with none, to the focused window.
            if (m_media && NativeDeskMedia::isMediaKey(m.key.keycode) && m_media->hasPlayers()) {
                if (m.key.down) {
                    m_media->key(m.key.keycode);
                }
                break;
            }
            m_keyboard->key(m.key.keycode, m.key.unicode, m.key.down);
            break;
        case NDESK_CLIPBOARD:
            if (m.clip.kind == NDESK_CLIP_PHONE && m_clipboard) {
                m_clipboard->phoneChanged();
            }
            break;
        case NDESK_TEXT:
            text(m);
            break;
        case NDESK_ACTION:
            // Home on the phone: every window out of the way (Show Desktop),
            // and back again on a second press, like Plasma's own button.
            if (m.action.action == NDESK_ACTION_SHOW_DESKTOP && Workspace::self()) {
                Workspace::self()->setShowingDesktop(!Workspace::self()->showingDesktop());
            } else if (m.action.action == NDESK_ACTION_BACK) {
                back();
            }
            break;
        }
    }
}

void NativeDeskBackend::back()
{
    // Escape doesn't leave the desktop's edit mode (only a panel's), so ask
    // plasmashell first; anything else Back closes (a popup, the start menu,
    // a dialog, a window's menu) takes Escape. Asked without blocking: KWin
    // mustn't wait on plasmashell.
    static const QString service = QStringLiteral("org.kde.plasmashell");
    static const QString path = QStringLiteral("/PlasmaShell");
    static const QString properties = QStringLiteral("org.freedesktop.DBus.Properties");
    static const QString shell = QStringLiteral("org.kde.PlasmaShell");
    static const QString editMode = QStringLiteral("editMode");
    QDBusMessage get = QDBusMessage::createMethodCall(service, path, properties, QStringLiteral("Get"));
    get << shell << editMode;
    auto *watcher = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(get, 500), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *w) {
        w->deleteLater();
        QDBusPendingReply<QDBusVariant> reply = *w;
        if (!reply.isError() && reply.value().variant().toBool()) {
            QDBusMessage set = QDBusMessage::createMethodCall(service, path, properties, QStringLiteral("Set"));
            set << shell << editMode << QVariant::fromValue(QDBusVariant(false));
            QDBusConnection::sessionBus().asyncCall(set);
            return;
        }
        if (m_keyboard) {
            m_keyboard->key(111, 0, true); // Android's KEYCODE_ESCAPE
            m_keyboard->key(111, 0, false);
        }
    });
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

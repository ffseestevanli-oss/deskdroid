/*
    KWin backend for DeskDroid's native Android compositor; see the header.

    SPDX-License-Identifier: GPL-2.0-or-later
*/
#include "nativedesk_backend.h"

#include "core/outputconfiguration.h"
#include "core/renderloop.h"

#include <QSocketNotifier>

#include <android/hardware_buffer.h>
#include <linux/input-event-codes.h>
#include <poll.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

#include <chrono>

#include "protocol.h"

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

void NativeDeskInputDevice::pointer(const QPointF &pos, uint32_t buttons)
{
    const auto time = now();
    Q_EMIT pointerMotionAbsolute(pos, time, this);
    static const struct { uint32_t bit, button; } map[] = {{1, BTN_LEFT}, {2, BTN_RIGHT}, {4, BTN_MIDDLE}};
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
    // One image kept across frames, so only what changed is painted again.
    QRegion repaint;
    const QSize size = m_output->modeSize();
    if (m_image.size() != size) {
        m_image = QImage(size, QImage::Format_RGBA8888_Premultiplied);
        m_image.fill(Qt::black);
        repaint = QRegion(QRect(QPoint(0, 0), size));
    }
    m_renderTime = std::make_unique<CpuRenderTimeQuery>();
    return OutputLayerBeginFrameInfo{
        .renderTarget = RenderTarget(&m_image),
        .repaint = repaint,
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
    ndesk_msg m = {};
    m.op = NDESK_HELLO;
    m.hello.version = NDESK_VERSION;
    m.hello.width = m_size.width();
    m.hello.height = m_size.height();
    snprintf(m.hello.title, NDESK_TITLE_MAX, "KWin");
    send(m);
    m_notifier = new QSocketNotifier(m_fd, QSocketNotifier::Read);
    connect(m_notifier, &QSocketNotifier::activated, this, &NativeDeskBackend::readMessages);

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

EglDisplay *NativeDeskBackend::sceneEglDisplayObject() const
{
    return nullptr;
}

QList<CompositingType> NativeDeskBackend::supportedCompositors() const
{
    return {QPainterCompositing};
}

Outputs NativeDeskBackend::outputs() const
{
    return m_output ? Outputs{m_output} : Outputs{};
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
            m_pointer->pointer(QPointF(m.pointer.x, m.pointer.y) / m_scale, m.pointer.buttons);
            break;
        case NDESK_SCROLL:
            m_pointer->scroll(m.scroll.dx / m_scale, m.scroll.dy / m_scale);
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

bool NativeDeskBackend::ensureBuffers(const QSize &size)
{
    if (m_buffers[0].ahb && size == m_bufferSize) {
        return true;
    }
    freeBuffers();
    m_bufferSize = size;
    for (int i = 0; i < BufferCount; i++) {
        AHardwareBuffer_Desc d = {};
        d.width = size.width();
        d.height = size.height();
        d.layers = 1;
        d.format = AHARDWAREBUFFER_FORMAT_R8G8B8A8_UNORM;
        d.usage = AHARDWAREBUFFER_USAGE_GPU_SAMPLED_IMAGE | AHARDWAREBUFFER_USAGE_CPU_WRITE_OFTEN;
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
    if (m_fd < 0 || !ensureBuffers(image.size())) {
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

    ndesk_msg m = {};
    m.op = NDESK_COMMIT;
    m.commit.id = id;
    m.commit.has_fence = fence >= 0;
    m.commit.y_invert = 0;
    send(m, fence);
    if (fence >= 0) {
        ::close(fence);
    }
    b.busy = true;
}

} // namespace KWin

#include "moc_nativedesk_backend.cpp"

/*
    KWin backend for DeskDroid's native Android compositor ("nativedesk").

    KWin runs as an ordinary Android process and shows its whole desktop as
    one fullscreen window of the nativedesk compositor: frames go out as
    AHardwareBuffers over the nativedesk socket (native/nativedesk/protocol.h),
    and the compositor's pointer and key events come back as KWin input
    devices. No DRM, no libinput, no logind.

    SPDX-License-Identifier: GPL-2.0-or-later
*/
#pragma once

#include "core/inputbackend.h"
#include "core/inputdevice.h"
#include "core/output.h"
#include "core/outputbackend.h"
#include "core/outputlayer.h"
#include "core/renderbackend.h"
#include "opengl/eglbackend.h"
#include "qpainter/qpainterbackend.h"

#include <QImage>
#include <QPointF>
#include <QSize>

#include <memory>

struct AHardwareBuffer;
struct ndesk_msg;
class QSocketNotifier;

namespace KWin
{

class NativeDeskBackend;
class RenderLoop;
class OutputFrame;

class NativeDeskOutput : public Output
{
    Q_OBJECT

public:
    NativeDeskOutput(NativeDeskBackend *backend, const QSize &pixelSize, qreal scale);
    ~NativeDeskOutput() override;

    RenderLoop *renderLoop() const override;
    void present(const std::shared_ptr<OutputFrame> &frame);
    void framePresented();
    void setPixelSize(const QSize &pixelSize);
    void setUserScale(qreal scale);

private:
    std::unique_ptr<RenderLoop> m_renderLoop;
    std::shared_ptr<OutputFrame> m_frame;
};

class NativeDeskInputDevice : public InputDevice
{
    Q_OBJECT

public:
    explicit NativeDeskInputDevice(bool keyboard);

    QString name() const override;
    bool isEnabled() const override;
    void setEnabled(bool enabled) override;
    bool isKeyboard() const override;
    bool isPointer() const override;
    bool isTouchpad() const override;
    bool isTouch() const override;
    bool isTabletTool() const override;
    bool isTabletPad() const override;
    bool isTabletModeSwitch() const override;
    bool isLidSwitch() const override;

    void pointer(const QPointF &pos, uint32_t buttons);
    void scroll(qreal dx, qreal dy);
    void key(int androidKeyCode, int unicode, bool down);

private:
    void evdevKey(uint32_t key, bool down);

    const bool m_keyboard;
    uint32_t m_buttons = 0;
    bool m_shiftHeld = false;
};

class NativeDeskInputBackend : public InputBackend
{
    Q_OBJECT

public:
    explicit NativeDeskInputBackend(NativeDeskBackend *backend);
    void initialize() override;

private:
    NativeDeskBackend *const m_backend;
};

class NativeDeskQPainterBackend;
class NativeDeskEglBackend;
class GLFramebuffer;
class GLTexture;
class GLRenderTimeQuery;
class EGLImageTexture;

// KWin composites with the phone's GPU (OpenGL ES through Android's EGL)
// straight into the AHardwareBuffers the DeskDroid compositor shows: each
// buffer is an EGLImage, a texture and a framebuffer; a native fence tells
// the compositor when the GPU is done with a frame.
class NativeDeskEglLayer : public OutputLayer
{
public:
    NativeDeskEglLayer(NativeDeskOutput *output, NativeDeskEglBackend *backend);
    ~NativeDeskEglLayer() override;

    std::optional<OutputLayerBeginFrameInfo> doBeginFrame() override;
    bool doEndFrame(const QRegion &renderedRegion, const QRegion &damagedRegion, OutputFrame *frame) override;
    DrmDevice *scanoutDevice() const override;
    QHash<uint32_t, QList<uint64_t>> supportedDrmFormats() const override;
    std::shared_ptr<GLTexture> texture() const;

private:
    struct Target
    {
        AHardwareBuffer *ahb = nullptr;
        std::shared_ptr<EGLImageTexture> texture;
        std::unique_ptr<GLFramebuffer> framebuffer;
    };
    bool prepareTarget(int id);
    void freeTargets();

    NativeDeskEglBackend *const m_backend;
    Target m_targets[3];
    int m_current = -1;
    std::unique_ptr<GLRenderTimeQuery> m_query;
};

class NativeDeskEglBackend : public EglBackend
{
    Q_OBJECT
public:
    explicit NativeDeskEglBackend(NativeDeskBackend *backend);
    ~NativeDeskEglBackend() override;

    void init() override;
    OutputLayer *primaryLayer(Output *output) override;
    bool present(Output *output, const std::shared_ptr<OutputFrame> &frame) override;
    std::pair<std::shared_ptr<GLTexture>, ColorDescription> textureForOutput(Output *output) const override;
    NativeDeskBackend *backend() const { return m_backend; }

private:
    NativeDeskBackend *const m_backend;
    std::unique_ptr<NativeDeskEglLayer> m_layer;
};


class NativeDeskQPainterLayer : public OutputLayer
{
public:
    NativeDeskQPainterLayer(NativeDeskOutput *output, NativeDeskBackend *backend);

    std::optional<OutputLayerBeginFrameInfo> doBeginFrame() override;
    bool doEndFrame(const QRegion &renderedRegion, const QRegion &damagedRegion, OutputFrame *frame) override;
    DrmDevice *scanoutDevice() const override;
    QHash<uint32_t, QList<uint64_t>> supportedDrmFormats() const override;

private:
    NativeDeskBackend *const m_backend;
    QImage m_image; // KWin paints here; each frame is copied into a free buffer
    std::unique_ptr<CpuRenderTimeQuery> m_renderTime;
};

class NativeDeskQPainterBackend : public QPainterBackend
{
    Q_OBJECT

public:
    explicit NativeDeskQPainterBackend(NativeDeskBackend *backend);
    ~NativeDeskQPainterBackend() override;

    OutputLayer *primaryLayer(Output *output) override;
    bool present(Output *output, const std::shared_ptr<OutputFrame> &frame) override;

private:
    NativeDeskBackend *const m_backend;
    std::unique_ptr<NativeDeskQPainterLayer> m_layer;
};

class KWIN_EXPORT NativeDeskBackend : public OutputBackend
{
    Q_OBJECT

public:
    NativeDeskBackend(const QSize &size, qreal scale);
    ~NativeDeskBackend() override;

    bool initialize() override;
    std::unique_ptr<InputBackend> createInputBackend() override;
    std::unique_ptr<QPainterBackend> createQPainterBackend() override;
    std::unique_ptr<EglBackend> createOpenGLBackend() override;
    EglDisplay *sceneEglDisplayObject() const override;
    QList<CompositingType> supportedCompositors() const override;
    Outputs outputs() const override;

    NativeDeskOutput *output() const;
    NativeDeskInputDevice *pointerDevice() const;
    NativeDeskInputDevice *keyboardDevice() const;

    // Copies a finished frame into a free buffer and shows it.
    void submit(const QImage &image);
    // For the GPU: buffers KWin renders into (gpu: GPU framebuffer usage
    // instead of CPU writes), a free one, and showing it once fence signals.
    bool ensureBuffers(const QSize &size, bool gpu);
    int acquire();
    AHardwareBuffer *buffer(int id) const { return m_buffers[id].ahb; }
    quint64 bufferGeneration() const { return m_generation; }
    void commit(int id, int fence);
    void setEglDisplay(std::unique_ptr<EglDisplay> &&display);
    static constexpr int BufferCount = 3;
    // A text field took (true) or lost the keyboard focus: the phone's keyboard.
    void setTextInputActive(bool active);

private:
    struct Buffer
    {
        AHardwareBuffer *ahb = nullptr;
        bool busy = false;
    };

    void send(const ndesk_msg &m, int passFd = -1);
    void readMessages();
    void freeBuffers();
    qreal outputScale() const { return m_output ? m_output->scale() : m_scale; }

    QSize m_size;
    qreal m_scale;
    int m_fd = -1;
    QSocketNotifier *m_notifier = nullptr;
    Buffer m_buffers[BufferCount];
    QSize m_bufferSize;
    bool m_gpuBuffers = false;
    quint64 m_generation = 0;
    std::unique_ptr<EglDisplay> m_eglDisplay;
    NativeDeskOutput *m_output = nullptr;
    std::unique_ptr<NativeDeskInputDevice> m_pointer;
    std::unique_ptr<NativeDeskInputDevice> m_keyboard;
    bool m_textInputActive = false;
};

} // namespace KWin

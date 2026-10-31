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
    EglDisplay *sceneEglDisplayObject() const override;
    QList<CompositingType> supportedCompositors() const override;
    Outputs outputs() const override;

    NativeDeskOutput *output() const;
    NativeDeskInputDevice *pointerDevice() const;
    NativeDeskInputDevice *keyboardDevice() const;

    // Copies a finished frame into a free buffer and shows it.
    void submit(const QImage &image);

private:
    struct Buffer
    {
        AHardwareBuffer *ahb = nullptr;
        bool busy = false;
    };

    void send(const ndesk_msg &m, int passFd = -1);
    void readMessages();
    int acquire();
    bool ensureBuffers(const QSize &size);
    void freeBuffers();

    QSize m_size;
    qreal m_scale;
    int m_fd = -1;
    QSocketNotifier *m_notifier = nullptr;
    static constexpr int BufferCount = 3;
    Buffer m_buffers[BufferCount];
    QSize m_bufferSize;
    NativeDeskOutput *m_output = nullptr;
    std::unique_ptr<NativeDeskInputDevice> m_pointer;
    std::unique_ptr<NativeDeskInputDevice> m_keyboard;
};

} // namespace KWin

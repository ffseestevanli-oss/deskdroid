/*
 * KWin's side of deskdroid_ahb_v1 (native/plasma/ahb/deskdroid_ahb.h): apps
 * hand KWin the GPU buffers they drew into, and KWin samples them as
 * textures. surfaceitem.cpp and display.cpp call in here (add-to-kwin.py).
 */
#pragma once

#include "core/graphicsbuffer.h"

#include <epoxy/egl.h>

struct AHardwareBuffer;
struct wl_client;
struct wl_display;
struct wl_resource;

namespace KWin
{

class EglDisplay;

class AhbClientBuffer : public GraphicsBuffer
{
public:
    AhbClientBuffer(AHardwareBuffer *buffer, bool yInverted, wl_client *client, uint32_t id);
    ~AhbClientBuffer() override;

    QSize size() const override;
    bool hasAlphaChannel() const override;

    // The buffer as an EGLImage on the scene's display, made on first use.
    EGLImageKHR image(EglDisplay *display);
    // Row 0 is the bottom row: no flip when drawn.
    bool yInverted() const;

    static AhbClientBuffer *get(wl_resource *resource);
    static AhbClientBuffer *from(GraphicsBuffer *buffer);

private:
    static void destroyResource(wl_resource *resource);

    AHardwareBuffer *m_buffer;
    QSize m_size;
    bool m_alpha;
    bool m_yInverted;
    wl_resource *m_resource;
    EGLDisplay m_eglDisplay = EGL_NO_DISPLAY;
    EGLImageKHR m_image = EGL_NO_IMAGE_KHR;
};

// Offers deskdroid_ahb_v1 to apps; called once KWin draws with the GPU.
void deskdroidAhbCreateGlobal(wl_display *display);

}

#include "deskdroid_ahb_server.h"

#include "opengl/egldisplay.h"

#include <QDebug>

#include <android/hardware_buffer.h>
#include <fcntl.h>
#include <unistd.h>
#include <wayland-server.h>

#include "deskdroid_ahb.h"

namespace KWin
{

using GetNativeClientBuffer = EGLClientBuffer (*)(const AHardwareBuffer *);

static const struct wl_buffer_interface s_bufferImplementation = {
    .destroy = [](wl_client *, wl_resource *resource) {
        wl_resource_destroy(resource);
    },
};

AhbClientBuffer::AhbClientBuffer(AHardwareBuffer *buffer, bool yInverted, wl_client *client, uint32_t id)
    : m_buffer(buffer)
    , m_yInverted(yInverted)
    , m_resource(wl_resource_create(client, &wl_buffer_interface, 1, id))
{
    AHardwareBuffer_Desc d{};
    AHardwareBuffer_describe(buffer, &d);
    m_size = QSize(d.width, d.height);
    m_alpha = d.format != AHARDWAREBUFFER_FORMAT_R8G8B8X8_UNORM && d.format != AHARDWAREBUFFER_FORMAT_R8G8B8_UNORM && d.format != AHARDWAREBUFFER_FORMAT_R5G6B5_UNORM;
    connect(this, &GraphicsBuffer::released, this, [this]() {
        if (m_resource) {
            wl_buffer_send_release(m_resource);
        }
    });
    wl_resource_set_implementation(m_resource, &s_bufferImplementation, this, destroyResource);
}

AhbClientBuffer::~AhbClientBuffer()
{
    if (m_image != EGL_NO_IMAGE_KHR) {
        eglDestroyImageKHR(m_eglDisplay, m_image);
    }
    AHardwareBuffer_release(m_buffer);
}

void AhbClientBuffer::destroyResource(wl_resource *resource)
{
    auto buffer = static_cast<AhbClientBuffer *>(wl_resource_get_user_data(resource));
    buffer->m_resource = nullptr;
    buffer->drop();
}

QSize AhbClientBuffer::size() const
{
    return m_size;
}

bool AhbClientBuffer::hasAlphaChannel() const
{
    return m_alpha;
}

bool AhbClientBuffer::yInverted() const
{
    return m_yInverted;
}

EGLImageKHR AhbClientBuffer::image(EglDisplay *display)
{
    if (m_image != EGL_NO_IMAGE_KHR && m_eglDisplay == display->handle()) {
        return m_image;
    }
    if (m_image != EGL_NO_IMAGE_KHR) {
        eglDestroyImageKHR(m_eglDisplay, m_image);
        m_image = EGL_NO_IMAGE_KHR;
    }
    static auto getNativeClientBuffer = reinterpret_cast<GetNativeClientBuffer>(eglGetProcAddress("eglGetNativeClientBufferANDROID"));
    if (!getNativeClientBuffer) {
        return EGL_NO_IMAGE_KHR;
    }
    const EGLint attribs[] = {EGL_IMAGE_PRESERVED_KHR, EGL_TRUE, EGL_NONE};
    m_eglDisplay = display->handle();
    m_image = eglCreateImageKHR(m_eglDisplay, EGL_NO_CONTEXT, EGL_NATIVE_BUFFER_ANDROID, getNativeClientBuffer(m_buffer), attribs);
    if (m_image == EGL_NO_IMAGE_KHR) {
        qWarning("deskdroid_ahb: can't make an EGLImage of a %dx%d buffer (0x%x)", m_size.width(), m_size.height(), eglGetError());
    }
    return m_image;
}

AhbClientBuffer *AhbClientBuffer::get(wl_resource *resource)
{
    if (wl_resource_instance_of(resource, &wl_buffer_interface, &s_bufferImplementation)) {
        return static_cast<AhbClientBuffer *>(wl_resource_get_user_data(resource));
    }
    return nullptr;
}

AhbClientBuffer *AhbClientBuffer::from(GraphicsBuffer *buffer)
{
    return dynamic_cast<AhbClientBuffer *>(buffer);
}

struct AhbManagerImplementation
{
    void (*create_buffer)(wl_client *client, wl_resource *resource, uint32_t id, int32_t fd, uint32_t yInverted);
    void (*destroy)(wl_client *client, wl_resource *resource);
};

static void createBuffer(wl_client *client, wl_resource *resource, uint32_t id, int32_t fd, uint32_t yInverted)
{
    // The app sent the buffer into its end of a socket pair and passed us the
    // other end. Never wait on it: a buffer that isn't there is an error.
    fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK);
    AHardwareBuffer *buffer = nullptr;
    const int ret = AHardwareBuffer_recvHandleFromUnixSocket(fd, &buffer);
    close(fd);
    if (ret != 0 || !buffer) {
        wl_resource_post_error(resource, 0, "no AHardwareBuffer in the socket (%d)", ret);
        return;
    }
    new AhbClientBuffer(buffer, yInverted != 0, client, id);
}

static const AhbManagerImplementation s_managerImplementation = {
    .create_buffer = createBuffer,
    .destroy = [](wl_client *, wl_resource *resource) {
        wl_resource_destroy(resource);
    },
};

static void bindManager(wl_client *client, void *, uint32_t version, uint32_t id)
{
    wl_resource *resource = wl_resource_create(client, &deskdroid_ahb_v1_interface, version, id);
    if (!resource) {
        wl_client_post_no_memory(client);
        return;
    }
    wl_resource_set_implementation(resource, &s_managerImplementation, nullptr, nullptr);
}

void deskdroidAhbCreateGlobal(wl_display *display)
{
    static wl_global *global = nullptr;
    if (!global) {
        global = wl_global_create(display, &deskdroid_ahb_v1_interface, 1, nullptr, bindManager);
        qInfo("deskdroid_ahb: apps can hand KWin GPU buffers");
    }
}

}

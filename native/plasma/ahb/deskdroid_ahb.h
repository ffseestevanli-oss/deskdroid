/*
 * deskdroid_ahb_v1: a Wayland extension for apps that draw with the phone's
 * GPU. An app renders into an AHardwareBuffer (Android's GPU memory) and
 * hands it to KWin as a wl_buffer, which KWin samples as a texture: no copy,
 * no CPU. Android's EGL has no Wayland platform and no dma-buf import, so
 * this stands in for wayland-egl and linux-dmabuf.
 *
 *   deskdroid_ahb_v1 (global, version 1)
 *     create_buffer(new_id wl_buffer, fd handle, uint y_inverted)
 *         handle: one end of a unix socket that the AHardwareBuffer was
 *         sent into with AHardwareBuffer_sendHandleToUnixSocket; KWin reads
 *         it from there. y_inverted: row 0 is the bottom row (what OpenGL
 *         rendering into a texture gives). The buffer is released with
 *         wl_buffer.release as usual. The app finishes drawing (glFinish)
 *         before it commits.
 *     destroy()
 *
 * The interface is written out here instead of generated from XML, so KWin
 * (server) and the Qt plugin (client) share this one header.
 */
#pragma once

#include <wayland-util.h>

#ifdef __cplusplus
extern "C" {
#endif

extern const struct wl_interface wl_buffer_interface;

static const struct wl_interface *deskdroid_ahb_v1_create_buffer_types[] = {
    &wl_buffer_interface,
    NULL,
    NULL,
};

static const struct wl_message deskdroid_ahb_v1_requests[] = {
    {"create_buffer", "nhu", deskdroid_ahb_v1_create_buffer_types},
    {"destroy", "", NULL},
};

static const struct wl_interface deskdroid_ahb_v1_interface = {
    "deskdroid_ahb_v1", 1, 2, deskdroid_ahb_v1_requests, 0, NULL,
};

enum {
    DESKDROID_AHB_V1_CREATE_BUFFER = 0,
    DESKDROID_AHB_V1_DESTROY = 1,
};

#ifdef __cplusplus
}
#endif

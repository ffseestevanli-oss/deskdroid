/*
 * nativedesk wire protocol: how a native app hands its window contents to the
 * native desktop compositor (compositor.c) without copying them.
 *
 * Apps and the compositor are plain Android processes of the DeskDroid app (no
 * proot, no Linux libc). They talk over a SOCK_SEQPACKET unix socket in the
 * abstract namespace (NDESK_SOCKET), one message per packet:
 *
 *   app -> compositor
 *     HELLO   window size and title; the compositor answers CONFIGURE.
 *             A size of 0x0 asks for the whole screen with no title bar:
 *             a desktop such as KWin, which draws its own windows
 *     BUFFER  announces buffer <id>; the next packet is the AHardwareBuffer
 *             itself (AHardwareBuffer_sendHandleToUnixSocket)
 *     COMMIT  show buffer <id>; if has_fence, the packet carries one fd, an
 *             Android native fence the compositor's GPU waits on. Row 0 of a
 *             buffer is the window's top row, unless y_invert is set (what
 *             OpenGL's default framebuffer orientation gives). The window
 *             takes the buffer's size, so resizing is committing a new size.
 *   compositor -> app
 *     CONFIGURE  the window's id, and the screen size for a 0x0 HELLO
 *     RELEASE    the compositor no longer reads buffer <id>
 *     FRAME      draw the next frame now (pacing, like wl_surface.frame).
 *                The compositor queues up to two commits and shows one per
 *                refresh; FRAME comes right after a commit while the queue
 *                has room, otherwise once a refresh takes one from it. So an
 *                app has a frame of slack, and three buffers are enough.
 *     POINTER    pointer position (window coordinates) and buttons
 *     KEY        Android key code, Unicode character, down/up
 *     SCROLL     scroll by dx, dy pixels (wheel or two-finger drag), at the
 *                last POINTER position
 *
 * Buffers are GPU memory owned by the app (AHardwareBuffer), drawn by the app
 * with the phone's own GLES/Vulkan driver and sampled by the compositor with
 * the same driver: nothing is forwarded, copied or translated.
 */
#ifndef NDESK_PROTOCOL_H
#define NDESK_PROTOCOL_H

#include <stdint.h>

#define NDESK_SOCKET "deskdroid-nativedesk" /* abstract: leading NUL */
#define NDESK_VERSION 1
#define NDESK_MAX_BUFFERS 4
#define NDESK_TITLE_MAX 64

enum ndesk_op {
    NDESK_HELLO = 1,
    NDESK_BUFFER,
    NDESK_COMMIT,
    NDESK_CONFIGURE = 100,
    NDESK_RELEASE,
    NDESK_FRAME,
    NDESK_POINTER,
    NDESK_KEY,
    NDESK_SCROLL,
};

struct ndesk_msg {
    uint32_t op;
    union {
        struct { uint32_t version, width, height; char title[NDESK_TITLE_MAX]; } hello;
        struct { uint32_t id; } buffer;
        struct { uint32_t id, has_fence, y_invert; } commit;
        struct { uint32_t window, width, height; } configure;
        struct { uint32_t id; } release;
        struct { uint64_t time_ns; } frame;
        struct { float x, y; uint32_t buttons, inside; } pointer;
        struct { int32_t keycode, unicode; uint32_t down; } key;
        struct { float dx, dy; } scroll;
    };
};

#endif

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
 *     TEXT    desktops: the focused text field's text around the cursor
 *             (SURROUNDING, in pieces like the TEXT below; a the cursor and b
 *             the selection's other end, in UTF-16 units), so the phone's
 *             keyboard knows what's there
 *     IME     show (1) or hide (0) the phone's on-screen keyboard: a text
 *             field in the desktop took or lost the keyboard focus. With it,
 *             the field's kind (purpose, NDESK_PURPOSE_*) and hints
 *             (NDESK_HINT_*), Wayland text-input's, so the phone's keyboard
 *             can offer swipe typing, corrections and suggestions where they
 *             fit (and not in a password field)
 *     CLIP    desktops: the shared clipboard (NDESK_CLIP_*). DESKTOP: a desktop
 *             app copied text; the packet carries one fd, a pipe the text
 *             comes out of (UTF-8), for the phone's clipboard. PASTE: a
 *             desktop app pastes the phone's clipboard; the packet carries
 *             one fd that the phone writes the text into and then closes
 *     PLAYING desktops: whether desktop media players (MPRIS) are playing
 *             (NDESK_PLAYING_*), so the phone's media buttons (Bluetooth
 *             earpieces, remotes) can reach them
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
 *     TOUCH      desktops: the touchscreen's fingers, as they are (Direct touch):
 *                DOWN, MOTION and UP of finger <id> at x, y (window
 *                coordinates), CANCEL (the phone took the touch back: every
 *                finger is gone) and FRAME after each set of changes, like
 *                wl_touch. The desktop hands them on as real touch events, so
 *                its apps scroll, flick and pinch with the fingers themselves
 *     SCROLL     scroll by dx, dy pixels (two-finger drag), at the last POINTER
 *                position; with wheel set, dx, dy are mouse-wheel steps in
 *                120ths of a click instead (a wheel: apps scroll by lines)
 *     SCALE      desktops: the user picked a new scale (1.5 = 150%), for now
 *     SAFE       desktops: screen pixels at each edge that the camera cutout or
 *                rounded corners hide (0 when dodging is off); panels and
 *                maximized windows keep out, the wallpaper still fills.
 *                With it, keyboard: screen pixels the phone's on-screen
 *                keyboard covers at the bottom (0 when it's down)
 *     ACTION     desktops: a desktop action from the phone (NDESK_ACTION_*),
 *                such as Home minimizing every window
 *     TEXT       desktops: text from the phone's keyboard for the focused text
 *                field (NDESK_TEXT_*): COMMIT types text, PREEDIT shows the
 *                word being composed (swipe typing, corrections) underlined
 *                in the field, with the cursor <a> characters into it, and an
 *                empty one takes it away. Text longer than one packet comes in
 *                pieces: <more> is set on every piece but the last
 *     CLIPBOARD  desktops: the phone's clipboard has new text (NDESK_CLIP_PHONE).
 *                Nothing is sent with it: the desktop asks for the text with
 *                CLIP PASTE when an app actually pastes, so Android reads its
 *                clipboard (and says so) only then
 *
 * Media keys (play/pause, next, previous, stop...) arrive as KEY with their
 * Android key codes; a desktop sends them to its MPRIS players.
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
    NDESK_IME,
    NDESK_CLIP,
    NDESK_PLAYING,
    NDESK_CONFIGURE = 100,
    NDESK_RELEASE,
    NDESK_FRAME,
    NDESK_POINTER,
    NDESK_KEY,
    NDESK_SCROLL,
    NDESK_SCALE,
    NDESK_SAFE,
    NDESK_ACTION,
    NDESK_TEXT,
    NDESK_CLIPBOARD,
    NDESK_TOUCH,
};

enum ndesk_touch {
    NDESK_TOUCH_DOWN = 1,
    NDESK_TOUCH_MOTION = 2,
    NDESK_TOUCH_UP = 3,
    NDESK_TOUCH_CANCEL = 4,
    NDESK_TOUCH_FRAME = 5,
};

enum ndesk_clip {
    NDESK_CLIP_DESKTOP = 1, /* app -> compositor, with a pipe to read the text from */
    NDESK_CLIP_PASTE = 2,   /* app -> compositor, with a pipe to write the phone's text into */
    NDESK_CLIP_PHONE = 3,   /* compositor -> app: the phone's clipboard changed */
};

enum ndesk_playing {
    NDESK_PLAYING_NONE = 0,   /* no desktop media player */
    NDESK_PLAYING_PAUSED = 1, /* players, none playing */
    NDESK_PLAYING_PLAYING = 2,
};

enum ndesk_action {
    NDESK_ACTION_SHOW_DESKTOP = 1, /* minimize every window (KWin's Show Desktop) */
    /* 2 and 3 were the phone's screen going off and on (the browser's
     * windows minimized meanwhile); the compositor slows down instead now
     * (nativeSetSleeping) and KWin isn't told. Not to be reused. */
    NDESK_ACTION_BACK = 4, /* the phone's Back: leave Plasma's edit mode, else Escape */
};

enum ndesk_text {
    NDESK_TEXT_COMMIT = 1,
    NDESK_TEXT_PREEDIT = 2,
    NDESK_TEXT_SURROUNDING = 3, /* app -> compositor */
};

/* Wayland text-input's content purpose and the hints DeskDroid uses. */
enum ndesk_purpose {
    NDESK_PURPOSE_NORMAL = 0, NDESK_PURPOSE_ALPHA, NDESK_PURPOSE_DIGITS, NDESK_PURPOSE_NUMBER,
    NDESK_PURPOSE_PHONE, NDESK_PURPOSE_URL, NDESK_PURPOSE_EMAIL, NDESK_PURPOSE_NAME,
    NDESK_PURPOSE_PASSWORD, NDESK_PURPOSE_DATE, NDESK_PURPOSE_TIME, NDESK_PURPOSE_DATETIME,
    NDESK_PURPOSE_TERMINAL, NDESK_PURPOSE_PIN,
};
#define NDESK_HINT_AUTO_CAPITALIZATION (1u << 2)
#define NDESK_HINT_UPPERCASE (1u << 4)
#define NDESK_HINT_HIDDEN (1u << 6)
#define NDESK_HINT_SENSITIVE (1u << 7)
#define NDESK_HINT_MULTILINE (1u << 9)

/* UTF-8 bytes in one TEXT packet: the union stays HELLO's size. */
#define NDESK_TEXT_CHUNK 64

struct ndesk_msg {
    uint32_t op;
    union {
        struct { uint32_t version, width, height; char title[NDESK_TITLE_MAX]; } hello;
        struct { uint32_t id; } buffer;
        struct { uint32_t id, has_fence, y_invert; } commit;
        struct { uint32_t show, purpose, hints; } ime;
        struct { uint32_t kind; } clip;
        struct { uint32_t state; } playing;
        struct { uint32_t window, width, height; } configure;
        struct { uint32_t id; } release;
        struct { uint64_t time_ns; } frame;
        struct { float x, y; uint32_t buttons, inside; } pointer;
        struct { int32_t keycode, unicode; uint32_t down; } key;
        struct { float dx, dy; uint32_t wheel; } scroll;
        struct { uint32_t kind; int32_t id; float x, y; } touch;
        struct { float scale; } scale;
        struct { float left, top, right, bottom, keyboard; } safe;
        struct { uint32_t action; } action;
        struct { uint8_t kind, more; uint16_t len; int32_t a, b; char text[NDESK_TEXT_CHUNK]; } text;
    };
};

#endif

/*
 * nativedesk compositor: the test bed for a native DeskDroid desktop (no proot,
 * no Linux libc, no GPU forwarding). Loaded into the app by NativeDesk.kt as
 * libnativedesk.so.
 *
 * Draws app windows into the activity's Surface with the phone's own EGL/GLES
 * driver. Apps (testclient.c) are separate processes that render into
 * AHardwareBuffers and share them over protocol.h; the compositor samples them
 * directly as EGLImages, waiting on the apps' native fences on the GPU. This is
 * the path KWin's Android backend would use; the window management here
 * (title-bar drag, click to raise) is just enough to measure it.
 */
#include <android/hardware_buffer.h>
#include <android/log.h>
#include <android/native_window_jni.h>
#include <errno.h>
#include <jni.h>
#include <poll.h>
#include <stddef.h>
#include <pthread.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/eventfd.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <time.h>
#include <unistd.h>

#define EGL_EGLEXT_PROTOTYPES
#define GL_GLEXT_PROTOTYPES
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES2/gl2.h>
#include <GLES2/gl2ext.h>

#include "protocol.h"

#define TAG "nativedesk"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, TAG, __VA_ARGS__)

#define MAX_CLIENTS 8
#define TITLE_H 36
#define INPUT_QUEUE 256

struct buffer {
    AHardwareBuffer *ahb;
    EGLImageKHR image;
    GLuint tex;
    uint32_t width, height;
};

struct client {
    int fd;
    uint32_t window;
    char title[NDESK_TITLE_MAX];
    float x, y;
    uint32_t w, h;
    struct buffer buf[NDESK_MAX_BUFFERS];
    int current;            /* buffer on screen, -1 before the first commit */
    bool y_invert;
    int to_release[NDESK_MAX_BUFFERS];
    int n_release;
    bool wants_frame;       /* committed since the last frame went out */
    unsigned commits, commits_last;
    float color[3];
};

struct input {
    enum { IN_POINTER, IN_KEY, IN_SCROLL } type;
    float x, y;     /* pointer position, or scroll amount */
    int buttons;
    int keycode, unicode, down;
};

static struct {
    pthread_t thread;
    bool running;
    ANativeWindow *window;
    int wake, listen_fd;

    EGLDisplay dpy;
    EGLSurface surf;
    EGLContext ctx;
    GLuint prog_tex, prog_solid, vbo;
    GLint tex_rect, tex_screen, tex_flip, solid_rect, solid_screen, solid_color;

    struct client *clients[MAX_CLIENTS];
    int order[MAX_CLIENTS];   /* indexes into clients, bottom to top */
    int n_order;
    uint32_t next_window;

    pthread_mutex_t lock;     /* guards input and stats */
    struct input input[INPUT_QUEUE];
    int n_input;
    char stats[512];

    float px, py;
    int buttons;
    int grab;                 /* client index being dragged, -1 if none */
    int focus;                /* client index under a held button, -1 if none */
    float grab_dx, grab_dy;
    bool dirty;
} C = { .listen_fd = -1, .wake = -1, .grab = -1, .focus = -1, .lock = PTHREAD_MUTEX_INITIALIZER };

static PFNEGLGETNATIVECLIENTBUFFERANDROIDPROC pGetNativeClientBuffer;
static PFNEGLCREATEIMAGEKHRPROC pCreateImage;
static PFNEGLDESTROYIMAGEKHRPROC pDestroyImage;
static PFNEGLCREATESYNCKHRPROC pCreateSync;
static PFNEGLWAITSYNCKHRPROC pWaitSync;
static PFNEGLDESTROYSYNCKHRPROC pDestroySync;
static PFNGLEGLIMAGETARGETTEXTURE2DOESPROC pImageTargetTexture;

static uint64_t clock_ns(clockid_t id)
{
    struct timespec t;
    clock_gettime(id, &t);
    return (uint64_t)t.tv_sec * 1000000000u + t.tv_nsec;
}

static uint64_t now_ns(void) { return clock_ns(CLOCK_MONOTONIC); }

/* ---- GL ---- */

static const char *VS =
    "attribute vec2 corner;\n"
    "uniform vec4 rect;\n"      /* x, y, w, h in pixels, y down */
    "uniform vec2 screen;\n"
    "uniform float flip;\n"    /* 1 for y_invert buffers */
    "varying vec2 uv;\n"
    "void main() {\n"
    "  vec2 p = (rect.xy + corner * rect.zw) / screen;\n"
    "  gl_Position = vec4(p.x * 2.0 - 1.0, 1.0 - p.y * 2.0, 0.0, 1.0);\n"
    "  uv = vec2(corner.x, mix(corner.y, 1.0 - corner.y, flip));\n"
    "}\n";
static const char *FS_TEX =
    "#extension GL_OES_EGL_image_external : require\n"
    "precision mediump float;\n"
    "uniform samplerExternalOES tex;\n"
    "varying vec2 uv;\n"
    "void main() { gl_FragColor = texture2D(tex, uv); }\n";
static const char *FS_SOLID =
    "precision mediump float;\n"
    "uniform vec4 color;\n"
    "varying vec2 uv;\n"
    "void main() { gl_FragColor = color; }\n";

static GLuint shader(GLenum type, const char *src)
{
    GLuint s = glCreateShader(type);
    glShaderSource(s, 1, &src, NULL);
    glCompileShader(s);
    GLint ok;
    glGetShaderiv(s, GL_COMPILE_STATUS, &ok);
    if (!ok) {
        char log[512];
        glGetShaderInfoLog(s, sizeof log, NULL, log);
        LOGE("shader: %s", log);
    }
    return s;
}

static GLuint program(const char *fs)
{
    GLuint p = glCreateProgram();
    glAttachShader(p, shader(GL_VERTEX_SHADER, VS));
    glAttachShader(p, shader(GL_FRAGMENT_SHADER, fs));
    glBindAttribLocation(p, 0, "corner");
    glLinkProgram(p);
    return p;
}

static bool egl_init(void)
{
    C.dpy = eglGetDisplay(EGL_DEFAULT_DISPLAY);
    if (!eglInitialize(C.dpy, NULL, NULL)) return false;
    const EGLint cfg_attr[] = {
        EGL_SURFACE_TYPE, EGL_WINDOW_BIT, EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT,
        EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8, EGL_ALPHA_SIZE, 8, EGL_NONE
    };
    EGLConfig cfg;
    EGLint n;
    if (!eglChooseConfig(C.dpy, cfg_attr, &cfg, 1, &n) || n < 1) return false;
    const EGLint ctx_attr[] = { EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE };
    C.ctx = eglCreateContext(C.dpy, cfg, EGL_NO_CONTEXT, ctx_attr);
    C.surf = eglCreateWindowSurface(C.dpy, cfg, C.window, NULL);
    if (C.ctx == EGL_NO_CONTEXT || C.surf == EGL_NO_SURFACE) return false;
    if (!eglMakeCurrent(C.dpy, C.surf, C.surf, C.ctx)) return false;
    eglSwapInterval(C.dpy, 1);

    pGetNativeClientBuffer = (void *)eglGetProcAddress("eglGetNativeClientBufferANDROID");
    pCreateImage = (void *)eglGetProcAddress("eglCreateImageKHR");
    pDestroyImage = (void *)eglGetProcAddress("eglDestroyImageKHR");
    pCreateSync = (void *)eglGetProcAddress("eglCreateSyncKHR");
    pWaitSync = (void *)eglGetProcAddress("eglWaitSyncKHR");
    pDestroySync = (void *)eglGetProcAddress("eglDestroySyncKHR");
    pImageTargetTexture = (void *)eglGetProcAddress("glEGLImageTargetTexture2DOES");
    if (!pGetNativeClientBuffer || !pCreateImage || !pImageTargetTexture) {
        LOGE("driver lacks EGL_ANDROID_get_native_client_buffer or EGL images");
        return false;
    }
    LOGI("GL: %s / %s", glGetString(GL_VENDOR), glGetString(GL_RENDERER));

    C.prog_tex = program(FS_TEX);
    C.tex_rect = glGetUniformLocation(C.prog_tex, "rect");
    C.tex_screen = glGetUniformLocation(C.prog_tex, "screen");
    C.tex_flip = glGetUniformLocation(C.prog_tex, "flip");
    C.prog_solid = program(FS_SOLID);
    C.solid_rect = glGetUniformLocation(C.prog_solid, "rect");
    C.solid_screen = glGetUniformLocation(C.prog_solid, "screen");
    C.solid_color = glGetUniformLocation(C.prog_solid, "color");
    static const float quad[] = { 0, 0, 1, 0, 0, 1, 1, 1 };
    glGenBuffers(1, &C.vbo);
    glBindBuffer(GL_ARRAY_BUFFER, C.vbo);
    glBufferData(GL_ARRAY_BUFFER, sizeof quad, quad, GL_STATIC_DRAW);
    glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, 0);
    glEnableVertexAttribArray(0);
    return true;
}

static void egl_fini(void)
{
    if (C.dpy == EGL_NO_DISPLAY) return;
    eglMakeCurrent(C.dpy, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    if (C.surf != EGL_NO_SURFACE) eglDestroySurface(C.dpy, C.surf);
    if (C.ctx != EGL_NO_CONTEXT) eglDestroyContext(C.dpy, C.ctx);
    eglTerminate(C.dpy);
    C.dpy = EGL_NO_DISPLAY;
    C.surf = EGL_NO_SURFACE;
    C.ctx = EGL_NO_CONTEXT;
}

/* ---- clients ---- */

static void send_msg(struct client *cl, const struct ndesk_msg *m)
{
    if (send(cl->fd, m, sizeof *m, MSG_NOSIGNAL | MSG_DONTWAIT) < 0 && errno != EAGAIN)
        LOGE("send to window %u: %s", cl->window, strerror(errno));
}

static void free_buffer(struct buffer *b)
{
    if (b->tex) glDeleteTextures(1, &b->tex);
    if (b->image) pDestroyImage(C.dpy, b->image);
    if (b->ahb) AHardwareBuffer_release(b->ahb);
    memset(b, 0, sizeof *b);
}

static void drop_client(int i)
{
    struct client *cl = C.clients[i];
    LOGI("window %u (%s) closed", cl->window, cl->title);
    for (int b = 0; b < NDESK_MAX_BUFFERS; b++) free_buffer(&cl->buf[b]);
    close(cl->fd);
    free(cl);
    C.clients[i] = NULL;
    int k = 0;
    for (int j = 0; j < C.n_order; j++)
        if (C.order[j] != i) C.order[k++] = C.order[j];
    C.n_order = k;
    if (C.grab == i) C.grab = -1;
    if (C.focus == i) C.focus = -1;
    C.dirty = true;
}

static void accept_client(void)
{
    int fd = accept4(C.listen_fd, NULL, NULL, SOCK_CLOEXEC);
    if (fd < 0) return;
    for (int i = 0; i < MAX_CLIENTS; i++) {
        if (C.clients[i]) continue;
        struct client *cl = calloc(1, sizeof *cl);
        cl->fd = fd;
        cl->current = -1;
        cl->window = ++C.next_window;
        /* Cascade new windows and give each a title-bar colour. */
        cl->x = 60 + 70 * (cl->window % 6);
        cl->y = 60 + 60 * (cl->window % 6);
        static const float palette[][3] = {
            { 0.95f, 0.36f, 0.62f }, { 0.25f, 0.78f, 0.92f }, { 0.98f, 0.66f, 0.20f },
            { 0.62f, 0.45f, 0.96f }, { 0.40f, 0.85f, 0.48f },
        };
        memcpy(cl->color, palette[cl->window % 5], sizeof cl->color);
        C.clients[i] = cl;
        C.order[C.n_order++] = i;
        return;
    }
    LOGE("too many windows");
    close(fd);
}

/* Reads one packet; returns false when the client is gone. */
static bool read_client(int i)
{
    struct client *cl = C.clients[i];
    struct ndesk_msg m;
    char ctrl[CMSG_SPACE(sizeof(int))];
    struct iovec iov = { &m, sizeof m };
    struct msghdr h = { .msg_iov = &iov, .msg_iovlen = 1, .msg_control = ctrl, .msg_controllen = sizeof ctrl };
    ssize_t n = recvmsg(cl->fd, &h, MSG_CMSG_CLOEXEC);
    if (n <= 0) return false;
    int fence = -1;
    for (struct cmsghdr *c = CMSG_FIRSTHDR(&h); c; c = CMSG_NXTHDR(&h, c))
        if (c->cmsg_level == SOL_SOCKET && c->cmsg_type == SCM_RIGHTS)
            memcpy(&fence, CMSG_DATA(c), sizeof fence);
    if (n != sizeof m) {
        if (fence >= 0) close(fence);
        return false;
    }

    switch (m.op) {
    case NDESK_HELLO: {
        if (m.hello.version != NDESK_VERSION) return false;
        cl->w = m.hello.width;
        cl->h = m.hello.height;
        memcpy(cl->title, m.hello.title, NDESK_TITLE_MAX);
        cl->title[NDESK_TITLE_MAX - 1] = 0;
        LOGI("window %u: %s, %ux%u", cl->window, cl->title, cl->w, cl->h);
        struct ndesk_msg r = { .op = NDESK_CONFIGURE, .configure = { cl->window } };
        send_msg(cl, &r);
        break;
    }
    case NDESK_BUFFER: {
        uint32_t id = m.buffer.id;
        if (id >= NDESK_MAX_BUFFERS) return false;
        struct buffer *b = &cl->buf[id];
        free_buffer(b);
        if (AHardwareBuffer_recvHandleFromUnixSocket(cl->fd, &b->ahb) != 0) return false;
        AHardwareBuffer_Desc d;
        AHardwareBuffer_describe(b->ahb, &d);
        b->width = d.width;
        b->height = d.height;
        const EGLint attr[] = { EGL_IMAGE_PRESERVED_KHR, EGL_TRUE, EGL_NONE };
        b->image = pCreateImage(C.dpy, EGL_NO_CONTEXT, EGL_NATIVE_BUFFER_ANDROID,
                                pGetNativeClientBuffer(b->ahb), attr);
        if (b->image == EGL_NO_IMAGE_KHR) {
            LOGE("window %u: can't import buffer %u (0x%x)", cl->window, id, eglGetError());
            return false;
        }
        glGenTextures(1, &b->tex);
        glBindTexture(GL_TEXTURE_EXTERNAL_OES, b->tex);
        glTexParameteri(GL_TEXTURE_EXTERNAL_OES, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_EXTERNAL_OES, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        pImageTargetTexture(GL_TEXTURE_EXTERNAL_OES, b->image);
        break;
    }
    case NDESK_COMMIT: {
        uint32_t id = m.commit.id;
        if (id >= NDESK_MAX_BUFFERS || !cl->buf[id].image) {
            if (fence >= 0) close(fence);
            return false;
        }
        if (fence >= 0) {
            /* The GPU waits for the app's rendering; this thread doesn't. */
            const EGLint attr[] = { EGL_SYNC_NATIVE_FENCE_FD_ANDROID, fence, EGL_NONE };
            EGLSyncKHR s = pCreateSync && pWaitSync ? pCreateSync(C.dpy, EGL_SYNC_NATIVE_FENCE_ANDROID, attr) : EGL_NO_SYNC_KHR;
            if (s != EGL_NO_SYNC_KHR) {
                pWaitSync(C.dpy, s, 0);
                pDestroySync(C.dpy, s);
            } else {
                close(fence);
                glFinish();
            }
        }
        if (cl->current >= 0 && cl->current != (int)id && cl->n_release < NDESK_MAX_BUFFERS)
            cl->to_release[cl->n_release++] = cl->current;
        cl->current = id;
        cl->y_invert = m.commit.y_invert;
        cl->w = cl->buf[id].width;
        cl->h = cl->buf[id].height;
        cl->wants_frame = true;
        cl->commits++;
        C.dirty = true;
        break;
    }
    default:
        if (fence >= 0) close(fence);
        return false;
    }
    return true;
}

/* ---- input ---- */

static int client_at(float x, float y, bool *title)
{
    for (int j = C.n_order - 1; j >= 0; j--) {
        struct client *cl = C.clients[C.order[j]];
        if (x >= cl->x && x < cl->x + cl->w && y >= cl->y - TITLE_H && y < cl->y + cl->h) {
            *title = y < cl->y;
            return C.order[j];
        }
    }
    return -1;
}

static void raise_client(int i)
{
    int k = 0;
    for (int j = 0; j < C.n_order; j++)
        if (C.order[j] != i) C.order[k++] = C.order[j];
    C.order[k] = i;
    C.dirty = true;
}

static void send_pointer(int i, bool inside)
{
    struct client *cl = C.clients[i];
    struct ndesk_msg m = { .op = NDESK_POINTER,
        .pointer = { C.px - cl->x, C.py - cl->y, (uint32_t)C.buttons, inside } };
    send_msg(cl, &m);
}

static void handle_input(const struct input *in)
{
    if (in->type == IN_SCROLL) {
        bool title;
        int i = client_at(C.px, C.py, &title);
        if (i < 0 || title) return;
        send_pointer(i, true); /* where the scroll happens */
        struct ndesk_msg m = { .op = NDESK_SCROLL, .scroll = { in->x, in->y } };
        send_msg(C.clients[i], &m);
        return;
    }
    if (in->type == IN_KEY) {
        int i = C.n_order ? C.order[C.n_order - 1] : -1; /* keyboard goes to the top window */
        if (i < 0) return;
        struct ndesk_msg m = { .op = NDESK_KEY, .key = { in->keycode, in->unicode, (uint32_t)in->down } };
        send_msg(C.clients[i], &m);
        return;
    }
    bool pressed = in->buttons && !C.buttons;
    C.px = in->x;
    C.py = in->y;
    C.buttons = in->buttons;
    if (pressed) {
        bool title = false;
        int i = client_at(C.px, C.py, &title);
        if (i >= 0) {
            raise_client(i);
            if (title) {
                C.grab = i;
                C.grab_dx = C.px - C.clients[i]->x;
                C.grab_dy = C.py - C.clients[i]->y;
            } else {
                C.focus = i;
            }
        }
    }
    if (C.grab >= 0) {
        C.clients[C.grab]->x = C.px - C.grab_dx;
        C.clients[C.grab]->y = C.py - C.grab_dy;
        C.dirty = true;
    } else if (C.focus >= 0) {
        send_pointer(C.focus, true); /* a held button keeps the window that got the press */
    } else {
        bool title;
        int i = client_at(C.px, C.py, &title);
        if (i >= 0 && !title) send_pointer(i, true);
    }
    if (!C.buttons) C.grab = C.focus = -1;
}

/* ---- frame ---- */

static void solid(float x, float y, float w, float h, float r, float g, float b, float a, int sw, int sh)
{
    glUniform4f(C.solid_rect, x, y, w, h);
    glUniform2f(C.solid_screen, sw, sh);
    glUniform4f(C.solid_color, r, g, b, a);
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
}

static void draw(void)
{
    EGLint sw, sh;
    eglQuerySurface(C.dpy, C.surf, EGL_WIDTH, &sw);
    eglQuerySurface(C.dpy, C.surf, EGL_HEIGHT, &sh);
    glViewport(0, 0, sw, sh);
    glClearColor(0.06f, 0.07f, 0.14f, 1);
    glClear(GL_COLOR_BUFFER_BIT);
    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

    int top = C.n_order ? C.order[C.n_order - 1] : -1;
    for (int j = 0; j < C.n_order; j++) {
        struct client *cl = C.clients[C.order[j]];
        if (cl->current < 0) continue;
        float dim = C.order[j] == top ? 1.0f : 0.55f;
        glUseProgram(C.prog_solid);
        solid(cl->x + 8, cl->y - TITLE_H + 10, cl->w, cl->h + TITLE_H, 0, 0, 0, 0.35f, sw, sh); /* shadow */
        solid(cl->x, cl->y - TITLE_H, cl->w, TITLE_H,
              cl->color[0] * dim, cl->color[1] * dim, cl->color[2] * dim, 1, sw, sh);
        struct buffer *b = &cl->buf[cl->current];
        glUseProgram(C.prog_tex);
        glActiveTexture(GL_TEXTURE0);
        glBindTexture(GL_TEXTURE_EXTERNAL_OES, b->tex);
        glUniform4f(C.tex_rect, cl->x, cl->y, cl->w, cl->h);
        glUniform2f(C.tex_screen, sw, sh);
        glUniform1f(C.tex_flip, cl->y_invert ? 1.0f : 0.0f);
        glDisable(GL_BLEND);
        glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
        glEnable(GL_BLEND);
    }
    /* Pointer, so mouse and touch are visible. */
    glUseProgram(C.prog_solid);
    solid(C.px - 6, C.py - 6, 12, 12, 1, 1, 1, 0.9f, sw, sh);
}

/*
 * Tells apps whose commit this frame latched to start their next one. Sent as
 * soon as the frame is recorded, before the swap: the app then renders while
 * the compositor waits for vsync, and its commit makes the next frame. Sending
 * it after the swap left apps a frame behind, at half the refresh rate.
 */
static void send_frames(void)
{
    uint64_t t = now_ns();
    for (int i = 0; i < MAX_CLIENTS; i++) {
        struct client *cl = C.clients[i];
        if (!cl || !cl->wants_frame) continue;
        struct ndesk_msg m = { .op = NDESK_FRAME, .frame = { t } };
        send_msg(cl, &m);
        cl->wants_frame = false;
    }
}

/* Buffers replaced in a frame that is now queued for display go back to their apps. */
static void send_releases(void)
{
    for (int i = 0; i < MAX_CLIENTS; i++) {
        struct client *cl = C.clients[i];
        if (!cl) continue;
        for (int r = 0; r < cl->n_release; r++) {
            struct ndesk_msg m = { .op = NDESK_RELEASE, .release = { (uint32_t)cl->to_release[r] } };
            send_msg(cl, &m);
        }
        cl->n_release = 0;
    }
}

static void update_stats(unsigned frames, double secs, double draw_ms)
{
    char s[512];
    int n = snprintf(s, sizeof s, "Compositor: %.0f fps, %.2f ms CPU per frame, GPU %s\n",
                     frames / secs, draw_ms, (const char *)glGetString(GL_RENDERER));
    for (int i = 0; i < MAX_CLIENTS && n < (int)sizeof s; i++) {
        struct client *cl = C.clients[i];
        if (!cl) continue;
        n += snprintf(s + n, sizeof s - n, "%s: %.0f fps\n", cl->title,
                      (cl->commits - cl->commits_last) / secs);
        cl->commits_last = cl->commits;
    }
    pthread_mutex_lock(&C.lock);
    memcpy(C.stats, s, sizeof s);
    pthread_mutex_unlock(&C.lock);
}

static void *loop(void *unused)
{
    (void)unused;
    if (!egl_init()) {
        LOGE("EGL setup failed (0x%x)", eglGetError());
        egl_fini();
        return NULL;
    }
    C.dirty = true;
    uint64_t stat_start = now_ns();
    unsigned frames = 0;
    double draw_total = 0;

    while (__atomic_load_n(&C.running, __ATOMIC_ACQUIRE)) {
        struct pollfd p[2 + MAX_CLIENTS];
        int idx[2 + MAX_CLIENTS], n = 0;
        p[n++] = (struct pollfd){ C.wake, POLLIN, 0 };
        p[n++] = (struct pollfd){ C.listen_fd, POLLIN, 0 };
        for (int i = 0; i < MAX_CLIENTS; i++)
            if (C.clients[i]) {
                idx[n] = i;
                p[n++] = (struct pollfd){ C.clients[i]->fd, POLLIN, 0 };
            }
        /* Idle until something happens; once dirty, the swap paces the loop. */
        if (poll(p, n, C.dirty ? 0 : 1000) < 0 && errno != EINTR) break;
        if (p[0].revents) {
            uint64_t v;
            read(C.wake, &v, sizeof v);
        }
        if (p[1].revents & POLLIN) accept_client();
        for (int k = 2; k < n; k++)
            if (p[k].revents && C.clients[idx[k]] && !read_client(idx[k])) drop_client(idx[k]);

        struct input in[INPUT_QUEUE];
        pthread_mutex_lock(&C.lock);
        int n_in = C.n_input;
        memcpy(in, C.input, n_in * sizeof in[0]);
        C.n_input = 0;
        pthread_mutex_unlock(&C.lock);
        for (int k = 0; k < n_in; k++) handle_input(&in[k]);
        if (n_in) C.dirty = true;

        if (C.dirty) {
            /* Thread CPU time, so waiting for a free screen buffer or vsync doesn't count. */
            uint64_t t0 = clock_ns(CLOCK_THREAD_CPUTIME_ID);
            draw();
            send_frames();
            if (!eglSwapBuffers(C.dpy, C.surf)) LOGE("swap failed (0x%x)", eglGetError());
            send_releases();
            draw_total += (clock_ns(CLOCK_THREAD_CPUTIME_ID) - t0) / 1e6;
            C.dirty = false;
            frames++;
        }
        uint64_t t = now_ns();
        if (t - stat_start >= 1000000000u) {
            double secs = (t - stat_start) / 1e9;
            update_stats(frames, secs, frames ? draw_total / frames : 0);
            stat_start = t;
            frames = 0;
            draw_total = 0;
        }
    }

    for (int i = 0; i < MAX_CLIENTS; i++)
        if (C.clients[i]) drop_client(i);
    egl_fini();
    return NULL;
}

/* ---- JNI: io.deskdroid.app.NativeDesk ---- */

static int listen_socket(void)
{
    int fd = socket(AF_UNIX, SOCK_SEQPACKET | SOCK_CLOEXEC, 0);
    struct sockaddr_un a = { .sun_family = AF_UNIX };
    size_t len = strlen(NDESK_SOCKET);
    memcpy(a.sun_path + 1, NDESK_SOCKET, len); /* abstract namespace */
    socklen_t alen = offsetof(struct sockaddr_un, sun_path) + 1 + len;
    if (fd < 0 || bind(fd, (struct sockaddr *)&a, alen) < 0 || listen(fd, 8) < 0) {
        LOGE("socket: %s", strerror(errno));
        if (fd >= 0) close(fd);
        return -1;
    }
    return fd;
}

JNIEXPORT jboolean JNICALL
Java_io_deskdroid_app_NativeDesk_nativeStart(JNIEnv *env, jclass cls, jobject surface)
{
    (void)cls;
    if (C.running) return JNI_TRUE;
    C.window = ANativeWindow_fromSurface(env, surface);
    C.listen_fd = listen_socket();
    C.wake = eventfd(0, EFD_CLOEXEC | EFD_NONBLOCK);
    if (!C.window || C.listen_fd < 0 || C.wake < 0) goto fail;
    C.dpy = EGL_NO_DISPLAY;
    C.running = true;
    if (pthread_create(&C.thread, NULL, loop, NULL) == 0) return JNI_TRUE;
    C.running = false;
fail:
    if (C.window) ANativeWindow_release(C.window);
    if (C.listen_fd >= 0) close(C.listen_fd);
    if (C.wake >= 0) close(C.wake);
    C.window = NULL;
    C.listen_fd = C.wake = -1;
    return JNI_FALSE;
}

static void wake(void)
{
    uint64_t one = 1;
    if (C.wake >= 0) write(C.wake, &one, sizeof one);
}

JNIEXPORT void JNICALL
Java_io_deskdroid_app_NativeDesk_nativeStop(JNIEnv *env, jclass cls)
{
    (void)env; (void)cls;
    if (!C.running) return;
    __atomic_store_n(&C.running, false, __ATOMIC_RELEASE);
    wake();
    pthread_join(C.thread, NULL);
    close(C.listen_fd);
    close(C.wake);
    ANativeWindow_release(C.window);
    C.window = NULL;
    C.listen_fd = C.wake = -1;
    C.n_input = 0;
    C.stats[0] = 0;
}

static void queue(struct input in)
{
    pthread_mutex_lock(&C.lock);
    if (C.n_input < INPUT_QUEUE) C.input[C.n_input++] = in;
    else if (in.type == IN_POINTER) C.input[INPUT_QUEUE - 1] = in; /* keep the latest position */
    pthread_mutex_unlock(&C.lock);
    wake();
}

JNIEXPORT void JNICALL
Java_io_deskdroid_app_NativeDesk_nativePointer(JNIEnv *env, jclass cls, jfloat x, jfloat y, jint buttons)
{
    (void)env; (void)cls;
    queue((struct input){ .type = IN_POINTER, .x = x, .y = y, .buttons = buttons });
}

JNIEXPORT void JNICALL
Java_io_deskdroid_app_NativeDesk_nativeKey(JNIEnv *env, jclass cls, jint keycode, jint unicode, jboolean down)
{
    (void)env; (void)cls;
    queue((struct input){ .type = IN_KEY, .keycode = keycode, .unicode = unicode, .down = down });
}

JNIEXPORT void JNICALL
Java_io_deskdroid_app_NativeDesk_nativeScroll(JNIEnv *env, jclass cls, jfloat dx, jfloat dy)
{
    (void)env; (void)cls;
    queue((struct input){ .type = IN_SCROLL, .x = dx, .y = dy });
}

JNIEXPORT jstring JNICALL
Java_io_deskdroid_app_NativeDesk_nativeStats(JNIEnv *env, jclass cls)
{
    (void)cls;
    char s[512];
    pthread_mutex_lock(&C.lock);
    memcpy(s, C.stats, sizeof s);
    pthread_mutex_unlock(&C.lock);
    return (*env)->NewStringUTF(env, s);
}

/*
 * nativedesk test app: a window for the native compositor (compositor.c),
 * standing in for a natively built Qt/KDE app. Started by NativeDesk.kt from
 * nativeLibraryDir as libnativedesk_client.so.
 *
 * Renders with the phone's GLES driver into AHardwareBuffers it shares with the
 * compositor (protocol.h), paced by the compositor's FRAME events. The scene is
 * a grid of spinning squares: --load sets how many (a GPU load knob), + and -
 * on the keyboard change it, and a crosshair follows the pointer.
 *
 *   libnativedesk_client.so [--title T] [--size WxH] [--load N]
 */
#include <android/hardware_buffer.h>
#include <errno.h>
#include <math.h>
#include <poll.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
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

#define N_BUFFERS 3

static EGLDisplay dpy;
static PFNEGLGETNATIVECLIENTBUFFERANDROIDPROC pGetNativeClientBuffer;
static PFNEGLCREATEIMAGEKHRPROC pCreateImage;
static PFNEGLCREATESYNCKHRPROC pCreateSync;
static PFNEGLDESTROYSYNCKHRPROC pDestroySync;
static PFNEGLDUPNATIVEFENCEFDANDROIDPROC pDupFence;
static PFNGLEGLIMAGETARGETTEXTURE2DOESPROC pImageTargetTexture;

struct target {
    AHardwareBuffer *ahb;
    GLuint tex, fbo;
    bool busy; /* the compositor may be reading it */
};

static double now(void)
{
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return t.tv_sec + t.tv_nsec / 1e9;
}

static void die(const char *what)
{
    fprintf(stderr, "nativedesk-client: %s (errno %d, EGL 0x%x)\n", what, errno, eglGetError());
    exit(1);
}

static const char *VS =
    "attribute vec2 corner;\n"
    "uniform vec4 rect;\n"     /* centre x, y, half size, angle; pixels, y down */
    "uniform vec2 size;\n"
    "void main() {\n"
    "  vec2 c = corner * 2.0 - 1.0;\n"
    "  float s = sin(rect.w), k = cos(rect.w);\n"
    "  vec2 p = rect.xy + rect.z * vec2(c.x * k - c.y * s, c.x * s + c.y * k);\n"
    /* Row 0 of the buffer is the window's top, and row 0 of an FBO is clip y -1. */
    "  gl_Position = vec4(p.x / size.x * 2.0 - 1.0, p.y / size.y * 2.0 - 1.0, 0.0, 1.0);\n"
    "}\n";
static const char *FS =
    "precision mediump float;\n"
    "uniform vec4 color;\n"
    "void main() { gl_FragColor = color; }\n";

static GLuint shader(GLenum type, const char *src)
{
    GLuint s = glCreateShader(type);
    glShaderSource(s, 1, &src, NULL);
    glCompileShader(s);
    return s;
}

static void egl_init(void)
{
    dpy = eglGetDisplay(EGL_DEFAULT_DISPLAY);
    if (!eglInitialize(dpy, NULL, NULL)) die("eglInitialize");
    const EGLint cfg_attr[] = { EGL_SURFACE_TYPE, EGL_PBUFFER_BIT, EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT,
                                EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8, EGL_ALPHA_SIZE, 8, EGL_NONE };
    EGLConfig cfg;
    EGLint n;
    if (!eglChooseConfig(dpy, cfg_attr, &cfg, 1, &n) || n < 1) die("no EGL config");
    const EGLint ctx_attr[] = { EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE };
    EGLContext ctx = eglCreateContext(dpy, cfg, EGL_NO_CONTEXT, ctx_attr);
    const EGLint pb_attr[] = { EGL_WIDTH, 1, EGL_HEIGHT, 1, EGL_NONE };
    EGLSurface pb = eglCreatePbufferSurface(dpy, cfg, pb_attr);
    if (ctx == EGL_NO_CONTEXT || !eglMakeCurrent(dpy, pb, pb, ctx)) die("EGL context");

    pGetNativeClientBuffer = (void *)eglGetProcAddress("eglGetNativeClientBufferANDROID");
    pCreateImage = (void *)eglGetProcAddress("eglCreateImageKHR");
    pCreateSync = (void *)eglGetProcAddress("eglCreateSyncKHR");
    pDestroySync = (void *)eglGetProcAddress("eglDestroySyncKHR");
    pDupFence = (void *)eglGetProcAddress("eglDupNativeFenceFDANDROID");
    pImageTargetTexture = (void *)eglGetProcAddress("glEGLImageTargetTexture2DOES");
    if (!pGetNativeClientBuffer || !pCreateImage || !pImageTargetTexture) die("driver lacks EGL images");
    printf("GL: %s / %s\n", glGetString(GL_VENDOR), glGetString(GL_RENDERER));
}

static void make_target(struct target *t, uint32_t w, uint32_t h)
{
    AHardwareBuffer_Desc d = {
        .width = w, .height = h, .layers = 1,
        .format = AHARDWAREBUFFER_FORMAT_R8G8B8A8_UNORM,
        .usage = AHARDWAREBUFFER_USAGE_GPU_FRAMEBUFFER | AHARDWAREBUFFER_USAGE_GPU_SAMPLED_IMAGE,
    };
    if (AHardwareBuffer_allocate(&d, &t->ahb) != 0) die("AHardwareBuffer_allocate");
    const EGLint attr[] = { EGL_IMAGE_PRESERVED_KHR, EGL_TRUE, EGL_NONE };
    EGLImageKHR img = pCreateImage(dpy, EGL_NO_CONTEXT, EGL_NATIVE_BUFFER_ANDROID,
                                   pGetNativeClientBuffer(t->ahb), attr);
    if (img == EGL_NO_IMAGE_KHR) die("eglCreateImageKHR");
    glGenTextures(1, &t->tex);
    glBindTexture(GL_TEXTURE_2D, t->tex);
    pImageTargetTexture(GL_TEXTURE_2D, img);
    glGenFramebuffers(1, &t->fbo);
    glBindFramebuffer(GL_FRAMEBUFFER, t->fbo);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, t->tex, 0);
    if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) die("FBO on AHardwareBuffer");
}

static int connect_compositor(void)
{
    int fd = socket(AF_UNIX, SOCK_SEQPACKET | SOCK_CLOEXEC, 0);
    struct sockaddr_un a = { .sun_family = AF_UNIX };
    size_t len = strlen(NDESK_SOCKET);
    memcpy(a.sun_path + 1, NDESK_SOCKET, len);
    socklen_t alen = offsetof(struct sockaddr_un, sun_path) + 1 + len;
    if (fd < 0 || connect(fd, (struct sockaddr *)&a, alen) < 0) die("can't reach the compositor");
    return fd;
}

static void send_msg(int fd, const struct ndesk_msg *m, int pass_fd)
{
    struct iovec iov = { (void *)m, sizeof *m };
    struct msghdr h = { .msg_iov = &iov, .msg_iovlen = 1 };
    char ctrl[CMSG_SPACE(sizeof(int))];
    if (pass_fd >= 0) {
        h.msg_control = ctrl;
        h.msg_controllen = sizeof ctrl;
        struct cmsghdr *c = CMSG_FIRSTHDR(&h);
        c->cmsg_level = SOL_SOCKET;
        c->cmsg_type = SCM_RIGHTS;
        c->cmsg_len = CMSG_LEN(sizeof(int));
        memcpy(CMSG_DATA(c), &pass_fd, sizeof(int));
    }
    if (sendmsg(fd, &h, MSG_NOSIGNAL) < 0) die("compositor went away");
}

int main(int argc, char **argv)
{
    const char *title = "Test app";
    uint32_t w = 640, h = 420;
    int load = 64;
    for (int i = 1; i + 1 < argc; i += 2) {
        if (!strcmp(argv[i], "--title")) title = argv[i + 1];
        else if (!strcmp(argv[i], "--size")) sscanf(argv[i + 1], "%ux%u", &w, &h);
        else if (!strcmp(argv[i], "--load")) load = atoi(argv[i + 1]);
    }
    setvbuf(stdout, NULL, _IOLBF, 0);

    egl_init();
    GLuint prog = glCreateProgram();
    glAttachShader(prog, shader(GL_VERTEX_SHADER, VS));
    glAttachShader(prog, shader(GL_FRAGMENT_SHADER, FS));
    glBindAttribLocation(prog, 0, "corner");
    glLinkProgram(prog);
    glUseProgram(prog);
    GLint u_rect = glGetUniformLocation(prog, "rect");
    GLint u_size = glGetUniformLocation(prog, "size");
    GLint u_color = glGetUniformLocation(prog, "color");
    static const float quad[] = { 0, 0, 1, 0, 0, 1, 1, 1 };
    GLuint vbo;
    glGenBuffers(1, &vbo);
    glBindBuffer(GL_ARRAY_BUFFER, vbo);
    glBufferData(GL_ARRAY_BUFFER, sizeof quad, quad, GL_STATIC_DRAW);
    glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, 0);
    glEnableVertexAttribArray(0);

    int fd = connect_compositor();
    struct ndesk_msg m = { .op = NDESK_HELLO, .hello = { NDESK_VERSION, w, h, { 0 } } };
    snprintf(m.hello.title, NDESK_TITLE_MAX, "%s", title);
    send_msg(fd, &m, -1);

    struct target t[N_BUFFERS] = { 0 };
    for (int i = 0; i < N_BUFFERS; i++) {
        make_target(&t[i], w, h);
        struct ndesk_msg b = { .op = NDESK_BUFFER, .buffer = { (uint32_t)i } };
        send_msg(fd, &b, -1);
        if (AHardwareBuffer_sendHandleToUnixSocket(t[i].ahb, fd) != 0) die("sending a buffer");
    }

    bool frame_ready = true;
    float px = -100, py = -100;
    double start = now(), stat = start;
    unsigned frames = 0;
    for (;;) {
        int next = -1;
        for (int i = 0; i < N_BUFFERS; i++)
            if (!t[i].busy) { next = i; break; }

        if (frame_ready && next >= 0) {
            double tm = now() - start;
            glBindFramebuffer(GL_FRAMEBUFFER, t[next].fbo);
            glViewport(0, 0, w, h);
            glClearColor(0.10f + 0.05f * sinf(tm), 0.11f, 0.20f, 1);
            glClear(GL_COLOR_BUFFER_BIT);
            glUniform2f(u_size, w, h);
            int cols = (int)ceilf(sqrtf(load > 0 ? load : 1));
            float cell = (float)w / cols;
            for (int i = 0; i < load; i++) {
                float cx = (i % cols + 0.5f) * cell, cy = (i / cols + 0.5f) * cell;
                glUniform4f(u_rect, cx, cy, cell * 0.32f, tm * (1 + (i % 5) * 0.4f));
                glUniform4f(u_color, 0.5f + 0.5f * sinf(i * 0.7f), 0.5f + 0.5f * sinf(i * 1.3f + 2),
                            0.5f + 0.5f * sinf(i * 0.9f + 4), 1);
                glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
            }
            glUniform4f(u_color, 1, 1, 1, 1);
            glUniform4f(u_rect, px, py, 10, 0.785f);
            glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);

            /* Hand over with a fence so neither side waits on the CPU. */
            int fence = -1;
            if (pCreateSync && pDupFence) {
                EGLSyncKHR s = pCreateSync(dpy, EGL_SYNC_NATIVE_FENCE_ANDROID, NULL);
                glFlush();
                if (s != EGL_NO_SYNC_KHR) {
                    fence = pDupFence(dpy, s);
                    pDestroySync(dpy, s);
                }
            }
            if (fence < 0) glFinish();
            struct ndesk_msg c = { .op = NDESK_COMMIT, .commit = { (uint32_t)next, fence >= 0, 0 } };
            send_msg(fd, &c, fence);
            if (fence >= 0) close(fence);
            t[next].busy = true;
            frame_ready = false;
        }

        struct pollfd p = { fd, POLLIN, 0 };
        if (poll(&p, 1, 1000) < 0 && errno != EINTR) die("poll");
        while (recv(fd, &m, sizeof m, MSG_DONTWAIT) == sizeof m) {
            switch (m.op) {
            case NDESK_RELEASE:
                if (m.release.id < N_BUFFERS) t[m.release.id].busy = false;
                break;
            case NDESK_FRAME:
                frame_ready = true;
                frames++;
                break;
            case NDESK_POINTER:
                px = m.pointer.x;
                py = m.pointer.y;
                break;
            case NDESK_KEY:
                if (m.key.down && m.key.unicode == '+') load *= 2;
                if (m.key.down && m.key.unicode == '-' && load > 1) load /= 2;
                break;
            }
        }
        if (p.revents & (POLLHUP | POLLERR)) return 0;
        double tn = now();
        if (tn - stat >= 5) {
            printf("%s: %.0f fps at load %d\n", title, frames / (tn - stat), load);
            frames = 0;
            stat = tn;
        }
    }
}

/*
 * ddflatpak-audit: ddflatpak's paths for glibc's loader itself.
 *
 * ddflatpak (ddflatpak.c) maps /app, /usr and the extension folders for the
 * calls a program makes through the C library. glibc's loader doesn't make
 * those calls: it opens the libraries a program needs itself, so a library
 * folder written into a program or library as an absolute path (RUNPATH
 * /app/lib/kid3, /usr/lib/aarch64-linux-gnu/pulseaudio) pointed at nothing,
 * and each app needed its folders added to the library path by hand.
 *
 * This is an audit library for glibc's loader (rtld-audit(7)): the loader
 * asks it about every place a program or library names for its libraries
 * (la_objsearch), and it answers with the folder ddflatpak would map that
 * place to. It reads the
 * same settings as ddflatpak: DDFLATPAK_APP, DDFLATPAK_RUNTIME and
 * DDFLATPAK_MOUNTS. flatpak.sh and the store's Flathub packages load it with
 * DDMASK_GLIBC_LD_AUDIT (DeskDroid's glibc reads DDMASK_GLIBC_LD_* for LD_*).
 *
 * It needs no C library, on purpose: the loader would look for an audit
 * library's libc.so.6 along the program's RUNPATH, find nothing at /app/...,
 * and remember those folders as missing before ever asking about them. So it
 * reads its settings from /proc/self/environ (the environment the program
 * started with) with plain system calls. Build with -nostdlib.
 *
 * Tested on desktop Linux by test/flatpak.sh, with LD_AUDIT.
 */

#define PATH_MAX_ 4096
#define MAX_MOUNTS 32

static long sys3(long nr, long a, long b, long c) {
    long r;
#if defined(__aarch64__)
    register long x8 __asm__("x8") = nr, x0 __asm__("x0") = a, x1 __asm__("x1") = b, x2 __asm__("x2") = c;
    __asm__ volatile("svc 0" : "+r"(x0) : "r"(x8), "r"(x1), "r"(x2) : "memory");
    r = x0;
#elif defined(__x86_64__)
    __asm__ volatile("syscall" : "=a"(r) : "a"(nr), "D"(a), "S"(b), "d"(c) : "rcx", "r11", "memory");
#else
#error "ddflatpak-audit: aarch64 or x86_64"
#endif
    return r;
}
#if defined(__aarch64__)
#define NR_openat 56
#define NR_read 63
#define NR_write 64
#define NR_close 57
#else
#define NR_openat 257
#define NR_read 0
#define NR_write 1
#define NR_close 3
#endif

static unsigned long len(const char *s) { unsigned long n = 0; while (s[n]) n++; return n; }

static int starts(const char *s, const char *p) {
    while (*p) if (*s++ != *p++) return 0;
    return 1;
}

static char env[65536];
static unsigned long env_len;
static const char *app, *rt;
static struct { const char *at, *to; unsigned long n; } mounts[MAX_MOUNTS];
static int n_mounts, debug;

static const char *getenv_(const char *name) {
    unsigned long n = len(name);
    for (unsigned long i = 0; i < env_len; i += len(env + i) + 1)
        if (starts(env + i, name) && env[i + n] == '=') return env + i + n + 1;
    return 0;
}

unsigned int la_version(unsigned int version) {
    long fd = sys3(NR_openat, -100 /* AT_FDCWD */, (long)"/proc/self/environ", 0 /* O_RDONLY */);
    if (fd >= 0) {
        long r;
        while (env_len < sizeof env - 1 && (r = sys3(NR_read, fd, (long)(env + env_len), (long)(sizeof env - 1 - env_len))) > 0)
            env_len += (unsigned long)r;
        sys3(NR_close, fd, 0, 0);
    }
    env[env_len] = 0;
    app = getenv_("DDFLATPAK_APP");
    rt = getenv_("DDFLATPAK_RUNTIME");
    debug = getenv_("DDFLATPAK_DEBUG") != 0;
    /* "<path>=<folder>;..." in place: env is ours. */
    char *m = (char *)getenv_("DDFLATPAK_MOUNTS");
    while (m && *m && n_mounts < MAX_MOUNTS) {
        char *end = m, *eq = 0;
        while (*end && *end != ';') { if (*end == '=' && !eq) eq = end; end++; }
        char *next = *end ? end + 1 : 0;
        *end = 0;
        if (eq && m[0] == '/') {
            *eq = 0;
            mounts[n_mounts].at = m;
            mounts[n_mounts].n = (unsigned long)(eq - m);
            mounts[n_mounts++].to = eq + 1;
        }
        m = next;
    }
    /* The loader's own version: la_objsearch is the same in all of them. */
    return version;
}

/* "/usr" (n = 4) matches "/usr" and "/usr/x", not "/usrx". Returns the rest. */
static const char *under(const char *path, const char *prefix, unsigned long n) {
    for (unsigned long i = 0; i < n; i++) if (path[i] != prefix[i]) return 0;
    return path[n] == 0 || path[n] == '/' ? path + n : 0;
}

static char *put(char *o, char *end, const char *s) {
    while (*s && o < end) *o++ = *s++;
    return o;
}

char *la_objsearch(const char *name, unsigned long *cookie, unsigned int flag) {
    (void)cookie;
    /* Names written into programs and libraries (LA_SER_ORIG: DT_NEEDED,
     * dlopen; LA_SER_RUNPATH: RPATH and RUNPATH folders). Not the library
     * path (real folders already) or the loader's own default folders, which
     * for DeskDroid's glibc are its own. */
    if (!(flag & (0x01 | 0x04))) return (char *)name;
    /* The loader copies the answer before it asks again; a few buffers in turn
     * are plenty. */
    static char bufs[4][PATH_MAX_];
    static unsigned turn;
    if (!name || name[0] != '/' || !rt) return (char *)name;
    const char *rest = 0, *to = 0, *sub = "";
    for (int i = 0; i < n_mounts && !to; i++)
        if ((rest = under(name, mounts[i].at, mounts[i].n))) to = mounts[i].to;
    if (!to && app && (rest = under(name, "/app", 4))) to = app;
    if (!to && (rest = under(name, "/usr", 4))) to = rt;
    if (!to && (rest = under(name, "/lib", 4))) to = rt, sub = "/lib";
    if (!to && (rest = under(name, "/lib64", 6))) to = rt, sub = "/lib64";
    if (!to) return (char *)name;
    char *out = bufs[turn++ % 4], *end = out + PATH_MAX_ - 1;
    char *o = put(put(put(out, end, to), end, sub), end, rest);
    if (o >= end) return (char *)name;
    *o = 0;
    if (debug) {
        char line[2 * PATH_MAX_ + 32], *l = line, *le = line + sizeof line - 1;
        l = put(put(put(put(l, le, "ddflatpak-audit: "), le, name), le, " -> "), le, out);
        *l++ = '\n';
        sys3(NR_write, 2, (long)line, l - line);
    }
    return out;
}

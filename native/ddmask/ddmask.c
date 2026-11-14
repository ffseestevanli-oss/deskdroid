/*
 * ddmask: lets programs that Android won't exec run anyway.
 *
 * Android (targetSdk 29+) refuses execve() on files an app wrote itself: only
 * the APK's library folder and the system's folders may be exec'd. It still
 * lets an app map its own files as code, so a program there can be started
 * through a loader that is allowed to run: Android's own linker
 * (/system/bin/linker64 <program>) loads it the way it loads a library.
 *
 * libddmask.so is preloaded (LD_PRELOAD) into the desktop's processes and
 * wraps the exec family (execve, execv, execvp, execvpe, execl, execlp,
 * execle, execveat, fexecve, posix_spawn, posix_spawnp). When the program to
 * start is outside the folders Android allows, it starts it like this instead:
 *
 *   ELF for this CPU, dynamic  -> its own interpreter (PT_INTERP) as a program:
 *                                 /system/bin/linker64 <program> <args>; glibc's
 *                                 and musl's map to DeskDroid's builds of them in
 *                                 the APK (native/glibc, native/musl), started as
 *                                 <loader> --argv0 <argv[0]> <program> <args>
 *   ELF for this CPU, static   -> libdd_static.so <program> <argv[0]> <args>
 *                                 (ddload.c, next to libddmask.so)
 *   AppImage                   -> libdd_appimage.so <appimage> <argv[0]> <args>
 *                                 (appimage.sh: unpacks it, starts its AppRun)
 *   ELF for x86_64             -> $DDMASK_X86_64 (default: libbox64.so next to
 *                                 libddmask.so, when it's there) <program> <args>
 *   ELF for i386               -> $DDMASK_I386 <program> <args>
 *   #! script                  -> its interpreter, mapped by $DDMASK_MAP, then
 *                                 these same rules for the interpreter
 *   anything else ELF (the
 *   above missing)             -> $DDMASK_FALLBACK <program> <args> (proot...),
 *                                 or EACCES
 *
 * A program started through the linker sees its own argv[0], gets its own
 * name as the process name, and reads its own path from /proc/self/exe
 * (DDMASK_ARGV0 and DDMASK_EXE carry them over the exec; the constructor
 * takes them back out of the environment).
 *
 * Every exec puts libddmask.so back into LD_PRELOAD, so a program that clears
 * its environment still starts its children through ddmask.
 *
 * Beyond exec, it smooths over what keeps breaking Linux programs on Android
 * (README.md, "Compatibility layer"):
 *   - execute bits: zips and Android's storage drop file modes, so an ELF
 *     program or #! script in the app's files runs without its execute bit,
 *     and access(X_OK) says so (shells' PATH searches, [ -x ]);
 *   - the desktop's environment: its Android-side Qt and KDE settings
 *     (bionic plugin folders, styles only it has) are left out when a bionic
 *     program starts a glibc or musl one, and given back when one of those
 *     starts a bionic program again (DDMASK_HOST_<VAR>, below);
 *   - blocked system calls (glibc and musl builds): a few that Android's
 *     seccomp filter blocks are made with the allowed call that does the same
 *     (accept, epoll_pwait2, faccessat2, fchmodat2, close_range); the rest
 *     fail with ENOSYS;
 *   - shared memory (glibc and musl builds): a memfd opened again through
 *     /proc/self/fd, which Android's SELinux refuses, and shm_open without
 *     a /dev/shm (below);
 *   - a journal ($DDMASK_JOURNAL): every program started another way, every one
 *     that can't be started and why, and every blocked system call, so a
 *     program that doesn't open leaves a trace.
 *
 * Settings (environment):
 *   DDMASK_ALLOW     folders exec works in, ':'-separated. Default on Android:
 *                    /system /vendor /apex /product /odm /system_ext and
 *                    libddmask.so's own folder (the APK's library folder).
 *                    Default elsewhere: everything (ddmask does nothing).
 *   DDMASK_MAP       interpreter paths to replace, "from=to:from=to", for #!
 *                    lines and PT_INTERP. On Android /bin/sh, /usr/bin/env and
 *                    /bin/env map to /system/bin by default.
 *   DDMASK_X86_64, DDMASK_I386, DDMASK_FALLBACK   as above
 *   DDMASK_DEBUG=1   log each decision to stderr
 *   DDMASK_JOURNAL   the journal file (kept under 256 KiB: the one before is
 *                    <file>.old); none when unset. The desktop sets
 *                    files/ddmask.log, which Settings' "Save log" includes
 *   DDMASK_STRICT_EXEC=1   files without an execute bit are refused, as before
 *   DDMASK_HOST_<VAR>      the desktop's own value of <VAR> (NativeDesk.kt sets
 *                    them for its Qt and KDE settings): a glibc or musl program
 *                    started from a bionic one doesn't get <VAR> while it still
 *                    has that value, and a bionic program started from one of
 *                    those gets it back
 *   DDMASK_LOG       a file: programs that couldn't be started are noted
 *                    there (with DDMASK_DEBUG, every decision too). For
 *                    children whose stderr goes nowhere (gpgme's).
 *
 * The exec wrappers can run in a vfork() child, so they don't allocate: all
 * buffers are on the stack.
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <elf.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <spawn.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>
#include <sys/prctl.h>
#include <sys/resource.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <time.h>
#include <ucontext.h>
#include <unistd.h>

#define EXPORT __attribute__((visibility("default")))
/* The glibc and musl builds of ddmask (for those programs) run on Android too. */
#if defined(__ANDROID__) || defined(DDMASK_GLIBC) || defined(DDMASK_MUSL)
#define DDMASK_ON_ANDROID 1
#endif

/*
 * The C libraries ddmask knows. Each has its own loader in the APK's library
 * folder (bionic's is the system's linker64), its own build of ddmask there,
 * and its own preload variable: the patched glibc and musl read theirs instead
 * of LD_PRELOAD (native/glibc, native/musl). Every exec puts each build that's
 * there into its variable, so programs of any kind start each other.
 */
struct world {
    const char *shim;    /* ddmask's build for it */
    const char *loader;  /* its loader, in the APK's library folder */
    const char *interp;  /* the PT_INTERP its programs ask for */
    const char *var;     /* its preload variable */
};
static const struct world worlds[] = {
    { "libddmask.so", NULL, NULL, "LD_PRELOAD" },
#if defined(__x86_64__)
    /* A desktop machine standing in for the phone (glibc/test/android-sim.sh). */
    { "libddmask_glibc.so", "libdd_ld-glibc.so", "/lib64/ld-linux-x86-64.so.2", "DDMASK_GLIBC_LD_PRELOAD" },
#else
    { "libddmask_glibc.so", "libdd_ld-glibc.so", "/lib/ld-linux-aarch64.so.1", "DDMASK_GLIBC_LD_PRELOAD" },
#endif
    { "libddmask_musl.so", "libdd_ld-musl.so", "/lib/ld-musl-aarch64.so.1", "DDMASK_MUSL_LD_PRELOAD" },
};
#define WORLDS (int)(sizeof worlds / sizeof worlds[0])
#if defined(DDMASK_GLIBC)
#define SELF_WORLD 1
#elif defined(DDMASK_MUSL)
#define SELF_WORLD 2
#else
#define SELF_WORLD 0
#endif
#define MAX_DEPTH 4           /* #! scripts whose interpreter is a script... */
#define EXTRA_ARGS (2 * MAX_DEPTH + 4)
#define LINE_MAX_SCRIPT 256   /* the kernel reads this much of a #! line too */

extern char **environ;

typedef int (*execve_fn)(const char *, char *const[], char *const[]);
typedef int (*spawn_fn)(pid_t *, const char *, const posix_spawn_file_actions_t *,
                        const posix_spawnattr_t *, char *const[], char *const[]);
typedef ssize_t (*readlink_fn)(const char *, char *, size_t);
typedef ssize_t (*readlinkat_fn)(int, const char *, char *, size_t);

static execve_fn real_execve;
static spawn_fn real_posix_spawn;
static readlink_fn real_readlink;
static readlinkat_fn real_readlinkat;

static char self_path[PATH_MAX];   /* libddmask.so */
static char self_dir[PATH_MAX];    /* its folder */
/* The APK's library folder (DDMASK_LIBS, else self_dir): the loaders and
 * runners ddmask execs, which Android only runs from there. ddmask itself may
 * come from the ddmask module (module.sh) in the app's files instead. */
static char apk_dir[PATH_MAX];
static char shims[WORLDS][PATH_MAX]; /* ddmask's builds that are there, by world */
static char exe_path[PATH_MAX];    /* the program this process really is, when started through a loader */

/* ---- small helpers that don't allocate ---- */

static const char *env_get(char *const envp[], const char *name) {
    size_t n = strlen(name);
    if (!envp) return NULL;
    for (char *const *e = envp; *e; e++)
        if (strncmp(*e, name, n) == 0 && (*e)[n] == '=') return *e + n + 1;
    return NULL;
}

#define JOURNAL_MAX (256 * 1024)
static char journal_path[PATH_MAX]; /* DDMASK_JOURNAL at start, for execs with a cleaned environment */

static const char *journal_file(char *const envp[]) {
    const char *j = env_get(envp, "DDMASK_JOURNAL");
    if (j && *j) return j;
    return journal_path[0] ? journal_path : NULL;
}

/* Appends a line to the journal; past JOURNAL_MAX the file moves to <file>.old
 * first. Only calls that are safe in a vfork child and a signal handler. */
static void journal_write(const char *file, const char *line, size_t n) {
    int fd = (int)syscall(SYS_openat, AT_FDCWD, file, O_WRONLY | O_APPEND | O_CREAT | O_CLOEXEC, 0600);
    if (fd < 0) return;
    struct stat st;
    if (fstat(fd, &st) == 0 && st.st_size > JOURNAL_MAX) {
        char old[PATH_MAX + 8];
        size_t fl = strlen(file);
        if (fl + 5 < sizeof old) {
            memcpy(old, file, fl);
            memcpy(old + fl, ".old", 5);
            close(fd);
            rename(file, old);
            fd = (int)syscall(SYS_openat, AT_FDCWD, file, O_WRONLY | O_APPEND | O_CREAT | O_CLOEXEC, 0600);
            if (fd < 0) return;
        }
    }
    ssize_t w = write(fd, line, n);
    (void)w;
    close(fd);
}

/* What to note, from least to most: */
enum level { L_DEBUG, L_ROUTE, L_FAIL };

/*
 * One decision. With DDMASK_DEBUG, every one goes to stderr. Programs started
 * another way (L_ROUTE) and ones that can't start (L_FAIL) go to the journal,
 * $DDMASK_JOURNAL, with the time; failures also go to $DDMASK_LOG as before
 * (a file flatpak.sh reads back for its own messages).
 */
static void vlog_(char *const envp[], enum level lv, const char *fmt, va_list ap) {
    const char *d = env_get(envp, "DDMASK_DEBUG");
    const char *file = lv == L_FAIL ? env_get(envp, "DDMASK_LOG") : NULL;
    const char *jf = lv >= L_ROUTE ? journal_file(envp) : NULL;
    int debug = d && *d && *d != '0';
    if (file && !*file) file = NULL;
    if (!debug && !file && !jf) return;
    char buf[PATH_MAX + 320];
    int t = 0;
    if (jf) {
        time_t now = time(NULL);
        struct tm tm;
        if (gmtime_r(&now, &tm)) t = (int)strftime(buf, 32, "%Y-%m-%d %H:%M:%S ", &tm);
    }
    int n = t + snprintf(buf + t, sizeof buf - t, "ddmask[%d]: ", (int)getpid());
    n += vsnprintf(buf + n, sizeof buf - n, fmt, ap);
    if (n > (int)sizeof buf - 2) n = sizeof buf - 2;
    buf[n++] = '\n';
    ssize_t w;
    if (debug && !file) w = write(2, buf + t, n - t);
    if (file) {
        int fd = (int)syscall(SYS_openat, AT_FDCWD, file, O_WRONLY | O_APPEND | O_CREAT | O_CLOEXEC, 0600);
        w = write(fd >= 0 ? fd : 2, buf + t, n - t);
        if (fd >= 0) close(fd);
    }
    (void)w;
    if (jf) journal_write(jf, buf, n);
}

static void note(char *const envp[], enum level lv, const char *fmt, ...) {
    int e = errno;
    va_list ap;
    va_start(ap, fmt);
    vlog_(envp, lv, fmt, ap);
    va_end(ap);
    errno = e;
}
#define logf_(envp, ...) note(envp, L_DEBUG, __VA_ARGS__)
/* A program that can't be started, with errno set: why. */
#define fail_(envp, ...) note(envp, L_FAIL, __VA_ARGS__)

static int sys_execve(const char *path, char *const argv[], char *const envp[]) {
    if (real_execve) return real_execve(path, argv, envp);
    return syscall(SYS_execve, path, argv, envp);
}

/* Does `path` (absolute, resolved) start with the folder `dir` (len n)? */
static int in_dir(const char *path, const char *dir, size_t n) {
    while (n > 1 && dir[n - 1] == '/') n--;
    if (n == 0) return 0;
    return strncmp(path, dir, n) == 0 && (path[n] == '/' || path[n] == 0);
}

static int in_list(const char *path, const char *list) {
    while (list && *list) {
        const char *end = strchr(list, ':');
        size_t n = end ? (size_t)(end - list) : strlen(list);
        if (in_dir(path, list, n)) return 1;
        list = end ? end + 1 : NULL;
    }
    return 0;
}

/* May the kernel exec this (resolved) path itself? */
static int exec_allowed(const char *real, char *const envp[]) {
    const char *allow = env_get(envp, "DDMASK_ALLOW");
    if (allow) return in_list(real, allow);
#ifdef DDMASK_ON_ANDROID
    if (in_list(real, "/system:/vendor:/apex:/product:/odm:/system_ext")) return 1;
    return apk_dir[0] && in_dir(real, apk_dir, strlen(apk_dir));
#else
    return 1;
#endif
}

/* DDMASK_STRICT_EXEC=1: files without an execute bit stay refused. */
static int strict_exec(char *const envp[]) {
    const char *s = env_get(envp, "DDMASK_STRICT_EXEC");
    return s && *s && *s != '0';
}

/* The world whose loader from the APK `runner` is (glibc's, musl's), or -1. */
static int loader_world(const char *runner) {
    const char *base = strrchr(runner, '/');
    base = base ? base + 1 : runner;
    for (int w = 0; w < WORLDS; w++)
        if (worlds[w].loader && strcmp(base, worlds[w].loader) == 0) return w;
    return -1;
}
#define is_world_loader(r) (loader_world(r) >= 0)

/* Replaces `path` through DDMASK_MAP (and Android's defaults) into out; returns out or path. */
static const char *map_path(const char *path, char *const envp[], char *out, size_t outsz) {
    const char *map = env_get(envp, "DDMASK_MAP");
#ifdef DDMASK_ON_ANDROID
    static const char defaults[] = "/bin/sh=/system/bin/sh:/usr/bin/env=/system/bin/env:/bin/env=/system/bin/env";
#else
    static const char defaults[] = "";
#endif
    /* glibc and musl programs: their loader from the APK (native/glibc, native/musl). */
    for (int w = 0; w < WORLDS; w++) {
        const struct world *wd = &worlds[w];
        if (!wd->interp || strcmp(path, wd->interp) != 0 || !apk_dir[0] || (map && strstr(map, wd->interp))) continue;
        if ((size_t)snprintf(out, outsz, "%s/%s", apk_dir, wd->loader) < outsz && access(out, F_OK) == 0) return out;
    }
    const char *lists[2] = { map, defaults };
    size_t plen = strlen(path);
    for (int i = 0; i < 2; i++) {
        const char *l = lists[i];
        while (l && *l) {
            const char *end = strchr(l, ':');
            size_t n = end ? (size_t)(end - l) : strlen(l);
            const char *eq = memchr(l, '=', n);
            if (eq && (size_t)(eq - l) == plen && strncmp(l, path, plen) == 0) {
                size_t tn = n - (eq + 1 - l);
                if (tn < outsz) {
                    memcpy(out, eq + 1, tn);
                    out[tn] = 0;
                    return out;
                }
            }
            l = end ? end + 1 : NULL;
        }
    }
    return path;
}

/* ---- what to run ---- */

enum kind { RUN_AS_IS, RUN_LOADER, RUN_STATIC, RUN_EMULATOR, RUN_SCRIPT, RUN_FALLBACK, RUN_NOEXEC };

#if defined(__aarch64__)
#define NATIVE_MACHINE EM_AARCH64
#elif defined(__x86_64__)
#define NATIVE_MACHINE EM_X86_64
#elif defined(__arm__)
#define NATIVE_MACHINE EM_ARM
#elif defined(__i386__)
#define NATIVE_MACHINE EM_386
#else
#define NATIVE_MACHINE EM_NONE
#endif

/* Reads the file's header. For ELF, interp gets PT_INTERP (empty when static);
 * for #!, interp gets the interpreter and arg its one argument (or empty). */
static enum kind classify(const char *path, char *interp, size_t isz, char *arg, size_t asz, int *machine, int *appimage) {
    int fd = open(path, O_RDONLY | O_CLOEXEC);
    if (fd < 0) return RUN_AS_IS;
    unsigned char head[LINE_MAX_SCRIPT];
    ssize_t n = pread(fd, head, sizeof head - 1, 0);
    enum kind k = RUN_NOEXEC;
    interp[0] = arg[0] = 0;
    *machine = EM_NONE;
    *appimage = 0;
    int is_program = 0;
    if (n >= 4 && memcmp(head, ELFMAG, SELFMAG) == 0) {
        /* AppImage (type 1 and 2): "AI" and its type in the ELF header's padding. */
        if (n >= 11 && head[8] == 'A' && head[9] == 'I' && (head[10] == 1 || head[10] == 2)) *appimage = 1;
        if (n >= (ssize_t)sizeof(Elf64_Ehdr) && head[EI_CLASS] == ELFCLASS64) {
            Elf64_Ehdr eh;
            memcpy(&eh, head, sizeof eh);
            *machine = eh.e_machine;
            is_program = eh.e_type == ET_EXEC || eh.e_type == ET_DYN;
            for (int i = 0; i < eh.e_phnum && i < 64; i++) {
                Elf64_Phdr ph;
                if (pread(fd, &ph, sizeof ph, eh.e_phoff + (off_t)i * eh.e_phentsize) != sizeof ph) break;
                if (ph.p_type == PT_INTERP && ph.p_filesz > 0 && ph.p_filesz < isz) {
                    if (pread(fd, interp, ph.p_filesz, ph.p_offset) != (ssize_t)ph.p_filesz) interp[0] = 0;
                    else interp[ph.p_filesz] = 0;
                }
            }
        } else if (n >= (ssize_t)sizeof(Elf32_Ehdr) && head[EI_CLASS] == ELFCLASS32) {
            Elf32_Ehdr eh;
            memcpy(&eh, head, sizeof eh);
            *machine = eh.e_machine;
        }
        if (*machine == NATIVE_MACHINE) k = interp[0] ? RUN_LOADER : is_program ? RUN_STATIC : RUN_FALLBACK;
        else if (*machine == EM_X86_64 || *machine == EM_386) k = RUN_EMULATOR;
        else k = RUN_FALLBACK;
    } else if (n >= 2 && head[0] == '#' && head[1] == '!') {
        head[n] = 0;
        char *p = (char *)head + 2, *nl = strchr(p, '\n');
        if (nl) *nl = 0;
        while (*p == ' ' || *p == '\t') p++;
        char *e = p;
        while (*e && *e != ' ' && *e != '\t') e++;
        size_t pn = e - p;
        if (pn > 0 && pn < isz) {
            memcpy(interp, p, pn);
            interp[pn] = 0;
            while (*e == ' ' || *e == '\t') e++;
            /* Like Linux: everything after the interpreter is one argument. */
            size_t an = strlen(e);
            while (an > 0 && (e[an - 1] == ' ' || e[an - 1] == '\t' || e[an - 1] == '\r')) an--;
            if (an < asz) { memcpy(arg, e, an); arg[an] = 0; }
            k = RUN_SCRIPT;
        }
    }
    close(fd);
    return k;
}

/* Everything one exec needs, kept off the heap. */
struct plan {
    char real[PATH_MAX];
    char interp[MAX_DEPTH][PATH_MAX];
    char arg[MAX_DEPTH][LINE_MAX_SCRIPT];
    char mapped[MAX_DEPTH][PATH_MAX];
    char emu[PATH_MAX];
    char preload[WORLDS][2 * PATH_MAX + 32];
    char env_exe[PATH_MAX + 16];
    char env_argv0[PATH_MAX + 16];
};

static int count(char *const v[]) {
    int n = 0;
    while (v && v[n]) n++;
    return n;
}

/* (snprintf truncating a too-long variable is fine: that's what the size is for.) */
#if defined(__GNUC__) && !defined(__clang__)
#pragma GCC diagnostic ignored "-Wformat-truncation"
#endif
/* Puts `lib` (a full path) first in the ':'-separated list `var` of envp, into buf. */
/* Whether the preload list names lib, by path or as the same file under
 * another (/data/user/0/<app> is /data/data/<app>: the ddmask module's path
 * reaches the list one way and ddmask's own realpath the other). */
static int preloads_lib(const char *list, const char *lib) {
    if (strstr(list, lib)) return 1;
    struct stat want, st;
    if (stat(lib, &want) != 0) return 0;
    char one[PATH_MAX];
    for (const char *s = list; *s; ) {
        size_t n = strcspn(s, ": ");
        if (n && n < sizeof one) {
            memcpy(one, s, n); one[n] = 0;
            if (stat(one, &st) == 0 && st.st_dev == want.st_dev && st.st_ino == want.st_ino) return 1;
        }
        s += n; if (*s) s++;
    }
    return 0;
}

static char *with_preload(char *const envp[], const char *var, const char *lib, char *buf, size_t size) {
    const char *cur = env_get(envp, var);
    if (cur && *cur && preloads_lib(cur, lib)) snprintf(buf, size, "%s=%s", var, cur);
    else if (cur && *cur) snprintf(buf, size, "%s=%s:%s", var, lib, cur);
    else snprintf(buf, size, "%s=%s", var, lib);
    return buf;
}

static int is_var(const char *entry, const char *var) {
    size_t n = strlen(var);
    return strncmp(entry, var, n) == 0 && entry[n] == '=';
}

#define HOST_PREFIX "DDMASK_HOST_"
#define HOST_PREFIX_LEN 12
#define LINUX_PREFIX "DDMASK_LINUX_"
#define LINUX_PREFIX_LEN 13

/* For "VAR=value": the desktop's own value of VAR (DDMASK_HOST_VAR), or NULL. */
static const char *host_value(char *const envp[], const char *entry) {
    const char *eq = strchr(entry, '=');
    char name[HOST_PREFIX_LEN + 128];
    size_t n = eq ? (size_t)(eq - entry) : 0;
    if (!n || n >= sizeof name - HOST_PREFIX_LEN || strncmp(entry, HOST_PREFIX, HOST_PREFIX_LEN) == 0) return NULL;
    memcpy(name, HOST_PREFIX, HOST_PREFIX_LEN);
    memcpy(name + HOST_PREFIX_LEN, entry, n);
    name[HOST_PREFIX_LEN + n] = 0;
    return env_get(envp, name);
}

/*
 * New environment: each of ddmask's builds that's there in its world's preload
 * variable (LD_PRELOAD, DDMASK_GLIBC_LD_PRELOAD, DDMASK_MUSL_LD_PRELOAD);
 * DDMASK_EXE/DDMASK_ARGV0 only when given. Going from a bionic program to a
 * glibc or musl one (world > 0), the desktop's own settings stay behind; going
 * back to a bionic one (world 0), they come back (DDMASK_HOST_<VAR>), and
 * the desktop's settings for Linux programs (DDMASK_LINUX_<VAR>) fill in.
 * nenvp has room for 2 * count(envp) + WORLDS + 3.
 */
static void build_env(char *const envp[], char **nenvp, struct plan *pl, int with_exe, int world) {
    int j = 0;
    int leaving = SELF_WORLD == 0 && world > 0, returning = SELF_WORLD != 0 && world == 0;
    for (char *const *e = envp; e && *e; e++) {
        if (is_var(*e, "DDMASK_EXE") || is_var(*e, "DDMASK_ARGV0")) continue;
        int ours = 0;
        for (int w = 0; w < WORLDS; w++) if (shims[w][0] && is_var(*e, worlds[w].var)) ours = 1;
        if (ours) continue;
        if (leaving || returning) {
            const char *host = host_value(envp, *e);
            if (host && (returning || strcmp(host, strchr(*e, '=') + 1) == 0)) continue;
        }
        nenvp[j++] = *e;
    }
    if (returning)
        for (char *const *e = envp; e && *e; e++)
            if (strncmp(*e, HOST_PREFIX, HOST_PREFIX_LEN) == 0 && strchr(*e, '=') > *e + HOST_PREFIX_LEN)
                nenvp[j++] = *e + HOST_PREFIX_LEN;
    /* The desktop's look for Linux programs (DDMASK_LINUX_<VAR>: KDE's
     * platform theme, the GTK theme), where they don't set their own. */
    if (leaving) {
        int base = j;
        for (char *const *e = envp; e && *e; e++) {
            if (strncmp(*e, LINUX_PREFIX, LINUX_PREFIX_LEN) != 0) continue;
            const char *kv = *e + LINUX_PREFIX_LEN, *eq = strchr(kv, '=');
            if (!eq || eq == kv) continue;
            size_t n = (size_t)(eq - kv) + 1;
            int set = 0;
            for (int k = 0; k < base && !set; k++) set = strncmp(nenvp[k], kv, n) == 0;
            if (!set) nenvp[j++] = (char *)kv;
        }
    }
    for (int w = 0; w < WORLDS; w++)
        if (shims[w][0]) nenvp[j++] = with_preload(envp, worlds[w].var, shims[w], pl->preload[w], sizeof pl->preload[w]);
    if (with_exe) {
        if (pl->env_exe[0]) nenvp[j++] = pl->env_exe;
        if (pl->env_argv0[0]) nenvp[j++] = pl->env_argv0;
    }
    nenvp[j] = NULL;
}

/*
 * Works out how to start `path` with `argv`: fills *npath and nargv (room for
 * count(argv) + EXTRA_ARGS) and nenvp (room for 2 * count(envp) + WORLDS + 3). Returns 0,
 * or -1 with errno set when it can't be started.
 */
static int is_own_exe(const char *path);

static int plan_exec(const char *path, char *const argv[], char *const envp[],
                     const char **npath, char **nargv, char **nenvp, struct plan *pl) {
    int argc = count(argv);
    /* A program started through a loader that execs /proc/self/exe (Chromium
     * starting its helpers) means itself, not the loader. */
    const char *cur = is_own_exe(path) ? exe_path : path;
    /* The argument vector so far; scripts prepend their interpreter. */
    int off = EXTRA_ARGS;   /* nargv[off..] holds the current argv */
    for (int i = 0; i < argc; i++) nargv[off + i] = argv[i];
    nargv[off + argc] = NULL;
    if (argc == 0) { nargv[off] = (char *)path; nargv[off + 1] = NULL; argc = 1; }
    pl->env_exe[0] = pl->env_argv0[0] = 0;
    int with_exe = 0;
    int world = 0;     /* what the program that finally runs is: bionic, glibc, musl; -1 not known */
    int opaque = 0;    /* started by ddload: nothing to say about its world */
    char how[96];      /* the way it starts, for the journal */
    size_t hl = 0;
    how[0] = 0;
#define HOW(s) do { int k_ = snprintf(how + hl, sizeof how - hl, "%s%s", hl ? ", " : "", s); \
                    if (k_ > 0 && hl + k_ < sizeof how) hl += k_; } while (0)

    for (int depth = 0;; depth++) {
        char resolved[PATH_MAX];
        if (!realpath(cur, resolved) || exec_allowed(resolved, envp)) {
            /* Let the kernel do it (or report why it can't). */
            *npath = cur;
            int lw = loader_world(cur);
            world = opaque ? -1 : lw >= 0 ? lw : 0;
            break;
        }
        struct stat st;
        if (stat(resolved, &st) != 0) { fail_(envp, "%s: %s", resolved, strerror(errno)); return -1; }
        if (!S_ISREG(st.st_mode)) {
            errno = EACCES;
            fail_(envp, "%s: not a file (mode %o)", resolved, (unsigned)st.st_mode);
            return -1;
        }
        /* Zips (the store's packages, Flatpak's files after the app unpacks
         * them) and shared storage don't keep execute bits: a program or
         * script runs without one, as it would have with it. */
        int no_x = !(st.st_mode & (S_IXUSR | S_IXGRP | S_IXOTH));
        if (depth >= MAX_DEPTH) { errno = ELOOP; fail_(envp, "%s: too many interpreters", cur); return -1; }
        /* A file opened by fd (fexecve, execveat) may close on exec: name it by its real path. */
        const char *prog = strncmp(cur, "/proc/self/fd/", 14) == 0 ? strcpy(pl->real, resolved) : cur;
        int machine, appimage = 0;
        char *interp = pl->interp[depth], *arg = pl->arg[depth];
        enum kind k = classify(resolved, interp, PATH_MAX, arg, LINE_MAX_SCRIPT, &machine, &appimage);
        if (no_x && (k == RUN_NOEXEC || strict_exec(envp))) {
            errno = EACCES;
            fail_(envp, "%s: no execute bit, and not a program or script (mode %o)", resolved, (unsigned)st.st_mode);
            return -1;
        }
        if (no_x) {
            /* Give it its bits back where the folder keeps them, for programs that look at the mode. */
            chmod(resolved, st.st_mode | ((st.st_mode & 0444) >> 2));
            HOW("no execute bit");
        }
        const char *runner = NULL;
        const char *argv0_opt = NULL; /* glibc's and musl's loaders take the program's argv[0] as --argv0 */
        int keep_argv0 = 0;           /* ddload and the AppImage runner take: <program> <argv[0]> <args> */
        /* An AppImage: unpacked (no FUSE on Android) and its AppRun started, by
         * libdd_appimage.so; which runs the AppImage itself, to unpack it, with
         * DDMASK_APPIMAGE_RAW=1: then it's just a program. */
        const char *raw = env_get(envp, "DDMASK_APPIMAGE_RAW");
        if (appimage && !(raw && *raw && *raw != '0') && apk_dir[0]) {
            snprintf(pl->emu, sizeof pl->emu, "%s/libdd_appimage.so", apk_dir);
            if (access(pl->emu, F_OK) == 0) { runner = pl->emu; keep_argv0 = 1; k = RUN_FALLBACK; HOW("AppImage"); }
        }
        switch (runner ? RUN_FALLBACK : k) {
        case RUN_AS_IS:
            *npath = cur;
            world = -1;
            goto done;
        case RUN_NOEXEC:
            errno = ENOEXEC;
            logf_(envp, "%s: not a program or script (ENOEXEC)", cur);
            return -1;
        case RUN_LOADER:
            runner = map_path(interp, envp, pl->mapped[depth], PATH_MAX);
            if (access(runner, F_OK) != 0) {
                /* glibc's loader on Android... */
                fail_(envp, "%s: its loader %s isn't there", cur, runner);
                runner = NULL;
            }
            if (runner) {
                int lw = loader_world(runner);
                HOW(lw > 0 ? (lw == 1 ? "glibc" : "musl") : strstr(runner, "linker") ? "bionic" : "loader");
                snprintf(pl->env_exe, sizeof pl->env_exe, "DDMASK_EXE=%s", resolved);
                if (is_world_loader(runner)) argv0_opt = nargv[off];
                else if ((size_t)snprintf(pl->env_argv0, sizeof pl->env_argv0, "DDMASK_ARGV0=%s", nargv[off]) >= sizeof pl->env_argv0)
                    pl->env_argv0[0] = 0;
                with_exe = 1;
            }
            break;
        case RUN_STATIC:
            /* No loader to start it through: ddmask's own (ddload.c). */
            if (apk_dir[0]) {
                snprintf(pl->emu, sizeof pl->emu, "%s/libdd_static.so", apk_dir);
                if (access(pl->emu, F_OK) == 0) { runner = pl->emu; keep_argv0 = 1; opaque = 1; HOW("static"); }
            }
            break;
        case RUN_EMULATOR: {
            const char *e = env_get(envp, machine == EM_X86_64 ? "DDMASK_X86_64" : "DDMASK_I386");
            if (!e && machine == EM_X86_64 && apk_dir[0]) {
                snprintf(pl->emu, sizeof pl->emu, "%s/libbox64.so", apk_dir);
                if (access(pl->emu, F_OK) == 0) e = pl->emu;
            }
            runner = e && *e ? e : NULL;
            HOW(machine == EM_X86_64 ? "x86-64" : "i386");
            if (!runner) {
                errno = EACCES;
                fail_(envp, "%s: an %s program, and no emulator is set up for it yet (DeskDroid downloads FEX the first time Steam starts)",
                      cur, machine == EM_X86_64 ? "x86-64" : "i386");
                return -1;
            }
            break;
        }
        case RUN_FALLBACK:
            break;
        case RUN_SCRIPT: {
            const char *in = map_path(interp, envp, pl->mapped[depth], PATH_MAX);
            /* interp [arg] script args... ; the script's own argv[0] is dropped, as Linux does. */
            nargv[off] = (char *)prog;
            if (arg[0]) nargv[--off] = arg;
            nargv[--off] = (char *)in;
            logf_(envp, "%s: script, interpreter %s", cur, in);
            HOW("script");
            cur = in;
            continue;
        }
        }
        if (!runner) {
            keep_argv0 = 0;
            const char *fb = env_get(envp, "DDMASK_FALLBACK");
            if (fb && *fb) runner = fb;
            with_exe = 0;
            pl->env_exe[0] = pl->env_argv0[0] = 0;
        }
        if (!runner) {
            errno = EACCES;
            fail_(envp, "%s: can't be started (no loader for it: machine %d%s)", cur, machine,
                  k == RUN_STATIC ? ", static" : "");
            return -1;
        }
        /* runner [--argv0 name] program args... ; or runner program argv0 args... */
        if (keep_argv0) {
            nargv[--off] = (char *)prog;
        } else if (argv0_opt) {
            nargv[off] = (char *)prog;
            nargv[--off] = (char *)argv0_opt;
            nargv[--off] = "--argv0";
        } else nargv[off] = (char *)prog;
        nargv[--off] = (char *)runner;
        logf_(envp, "%s: through %s", cur, runner);
        cur = runner;
        /* The runner itself must be allowed to run (linker64, the APK's box64...): check it next round. */
    }
done:
    if (hl) note(envp, L_ROUTE, "%s: %s, through %s", path, how, *npath);
#undef HOW
    build_env(envp, nenvp, pl, with_exe, world);
    /* Move argv to the front. */
    int i = 0;
    while (nargv[off + i]) { nargv[i] = nargv[off + i]; i++; }
    nargv[i] = NULL;
    return 0;
}

static int dd_execve(const char *path, char *const argv[], char *const envp[]) {
    if (!path) { errno = EFAULT; return -1; }
    char *nargv[count(argv) + EXTRA_ARGS + 2];
    char *nenvp[2 * count(envp) + WORLDS + 3];
    struct plan pl;
    const char *npath;
    if (plan_exec(path, argv, envp, &npath, nargv, nenvp, &pl) != 0) return -1;
    sys_execve(npath, nargv, nenvp);
    fail_(envp, "%s (as %s): %s", path, npath, strerror(errno));
    return -1;
}

/* execvp's search, as POSIX describes it, through dd_execve. */
static int dd_execvpe(const char *file, char *const argv[], char *const envp[]) {
    if (!file || !*file) { errno = ENOENT; return -1; }
    if (strchr(file, '/')) {
        int r = dd_execve(file, argv, envp);
        if (errno == ENOEXEC) goto shell;
        return r;
    }
    const char *search = getenv("PATH");
    if (!search) search = "/system/bin:/bin:/usr/bin";
    int seen_eacces = 0;
    char buf[PATH_MAX];
    for (const char *p = search;;) {
        const char *end = strchr(p, ':');
        size_t n = end ? (size_t)(end - p) : strlen(p);
        if (n + 1 + strlen(file) < sizeof buf) {
            if (n == 0) snprintf(buf, sizeof buf, "%s", file);
            else snprintf(buf, sizeof buf, "%.*s/%s", (int)n, p, file);
            dd_execve(buf, argv, envp);
            if (errno == ENOEXEC) { file = buf; goto shell; }
            if (errno == EACCES) seen_eacces = 1;
            else if (errno != ENOENT && errno != ENOTDIR) return -1;
        }
        if (!end) break;
        p = end + 1;
    }
    if (seen_eacces) errno = EACCES;
    return -1;
shell: {
        int argc = count(argv);
        char *sargv[argc + 3];
#ifdef DDMASK_ON_ANDROID
        sargv[0] = (char *)"/system/bin/sh";
#else
        sargv[0] = (char *)"/bin/sh";
#endif
        sargv[1] = (char *)file;
        for (int i = 1; i < argc; i++) sargv[i + 1] = argv[i];
        sargv[argc < 1 ? 2 : argc + 1] = NULL;
        return dd_execve(sargv[0], sargv, envp);
    }
}

/* ---- the exported wrappers ---- */

EXPORT int execve(const char *path, char *const argv[], char *const envp[]) {
    return dd_execve(path, argv, envp);
}

EXPORT int execv(const char *path, char *const argv[]) {
    return dd_execve(path, argv, environ);
}

EXPORT int execvpe(const char *file, char *const argv[], char *const envp[]) {
    return dd_execvpe(file, argv, envp);
}

EXPORT int execvp(const char *file, char *const argv[]) {
    return dd_execvpe(file, argv, environ);
}

#define COLLECT_ARGS(first, last_named, extra)                       \
    va_list ap;                                                      \
    int n = 1;                                                       \
    va_start(ap, last_named);                                        \
    while (va_arg(ap, char *)) n++;                                  \
    va_end(ap);                                                      \
    char *argv[n + 1];                                               \
    argv[0] = (char *)(first);                                       \
    va_start(ap, last_named);                                        \
    for (int i = 1; i <= n; i++) argv[i] = va_arg(ap, char *);       \
    extra;                                                           \
    va_end(ap);

EXPORT int execl(const char *path, const char *arg0, ...) {
    COLLECT_ARGS(arg0, arg0, (void)0)
    return dd_execve(path, argv, environ);
}

EXPORT int execlp(const char *file, const char *arg0, ...) {
    COLLECT_ARGS(arg0, arg0, (void)0)
    return dd_execvpe(file, argv, environ);
}

EXPORT int execle(const char *path, const char *arg0, ...) {
    char **envp;
    COLLECT_ARGS(arg0, arg0, envp = va_arg(ap, char **))
    return dd_execve(path, argv, envp);
}

EXPORT int fexecve(int fd, char *const argv[], char *const envp[]) {
    char p[32];
    snprintf(p, sizeof p, "/proc/self/fd/%d", fd);
    return dd_execve(p, argv, envp);
}

EXPORT int execveat(int dirfd, const char *path, char *const argv[], char *const envp[], int flags) {
#ifndef AT_EMPTY_PATH
#define AT_EMPTY_PATH 0x1000
#endif
    char p[PATH_MAX];
    if ((flags & AT_EMPTY_PATH) && !*path) snprintf(p, sizeof p, "/proc/self/fd/%d", dirfd);
    else if (path[0] == '/' || dirfd == AT_FDCWD) return dd_execve(path, argv, envp);
    else snprintf(p, sizeof p, "/proc/self/fd/%d/%s", dirfd, path);
    return dd_execve(p, argv, envp);
}

static int dd_spawn(pid_t *pid, const char *path, const posix_spawn_file_actions_t *fa,
                    const posix_spawnattr_t *attr, char *const argv[], char *const envp[]) {
    if (!real_posix_spawn) return ENOSYS;
    size_t na = count(argv) + EXTRA_ARGS + 2, ne = 2 * count(envp) + WORLDS + 3;
    char **nargv = malloc(na * sizeof *nargv), **nenvp = malloc(ne * sizeof *nenvp);
    struct plan *pl = malloc(sizeof *pl);
    int r;
    const char *npath;
    if (!nargv || !nenvp || !pl) r = ENOMEM;
    else if (plan_exec(path, argv, envp, &npath, nargv, nenvp, pl) != 0) r = errno;
    else r = real_posix_spawn(pid, npath, fa, attr, nargv, nenvp);
    free(nargv);
    free(nenvp);
    free(pl);
    return r;
}

EXPORT int posix_spawn(pid_t *pid, const char *path, const posix_spawn_file_actions_t *fa,
                       const posix_spawnattr_t *attr, char *const argv[], char *const envp[]) {
    return dd_spawn(pid, path, fa, attr, argv, envp);
}

EXPORT int posix_spawnp(pid_t *pid, const char *file, const posix_spawn_file_actions_t *fa,
                        const posix_spawnattr_t *attr, char *const argv[], char *const envp[]) {
    if (strchr(file, '/')) return dd_spawn(pid, file, fa, attr, argv, envp);
    const char *search = getenv("PATH");
    if (!search) search = "/system/bin:/bin:/usr/bin";
    char buf[PATH_MAX];
    for (const char *p = search;;) {
        const char *end = strchr(p, ':');
        size_t n = end ? (size_t)(end - p) : strlen(p);
        if (n == 0) snprintf(buf, sizeof buf, "%s", file);
        else snprintf(buf, sizeof buf, "%.*s/%s", (int)n, p, file);
        if (access(buf, X_OK) == 0) return dd_spawn(pid, buf, fa, attr, argv, envp);
        if (!end) break;
        p = end + 1;
    }
    return ENOENT;
}

/* /proc/self/exe names the loader for a program started through one: give its own path. */
static int is_own_exe(const char *path) {
    if (!exe_path[0] || !path) return 0;
    if (strcmp(path, "/proc/self/exe") == 0 || strcmp(path, "/proc/thread-self/exe") == 0) return 1;
    char p[64];
    snprintf(p, sizeof p, "/proc/%d/exe", (int)getpid());
    return strcmp(path, p) == 0;
}

static ssize_t own_exe(char *buf, size_t size) {
    size_t n = strlen(exe_path);
    if (n > size) n = size;
    memcpy(buf, exe_path, n);
    return n;
}

EXPORT ssize_t readlink(const char *path, char *buf, size_t size) {
    if (is_own_exe(path)) return own_exe(buf, size);
    if (real_readlink) return real_readlink(path, buf, size);
    return syscall(SYS_readlinkat, AT_FDCWD, path, buf, size);
}

EXPORT ssize_t readlinkat(int dirfd, const char *path, char *buf, size_t size) {
    if ((dirfd == AT_FDCWD || path[0] == '/') && is_own_exe(path)) return own_exe(buf, size);
    if (real_readlinkat) return real_readlinkat(dirfd, path, buf, size);
    return syscall(SYS_readlinkat, dirfd, path, buf, size);
}

/* ---- execute bits ---- */

/*
 * access(X_OK) on a file without an execute bit that ddmask starts anyway (an
 * ELF program or #! script in the app's files): yes, so shells find it on PATH
 * and [ -x ] agrees with exec. It also gets its execute bits, where the folder
 * keeps them, so programs that look at the mode (stat) see them next time.
 */
static int runs_anyway(int dirfd, const char *path) {
    if (!path || !*path || strict_exec(environ)) return 0;
    char full[PATH_MAX], resolved[PATH_MAX];
    if (path[0] != '/' && dirfd != AT_FDCWD) {
        if ((size_t)snprintf(full, sizeof full, "/proc/self/fd/%d/%s", dirfd, path) >= sizeof full) return 0;
        path = full;
    }
    if (!realpath(path, resolved) || exec_allowed(resolved, environ)) return 0;
    struct stat st;
    if (stat(resolved, &st) != 0 || !S_ISREG(st.st_mode)) return 0;
    char interp[PATH_MAX], arg[LINE_MAX_SCRIPT];
    int machine, appimage;
    enum kind k = classify(resolved, interp, sizeof interp, arg, sizeof arg, &machine, &appimage);
    if (k == RUN_NOEXEC || k == RUN_AS_IS || (k == RUN_FALLBACK && !appimage)) return 0;
    chmod(resolved, st.st_mode | ((st.st_mode & 0444) >> 2));
    return 1;
}

typedef int (*access_fn)(const char *, int);
typedef int (*faccessat_fn)(int, const char *, int, int);
static access_fn real_access;
static faccessat_fn real_faccessat;

/* After the real check failed (r != 0): whether X_OK was all that was missing. */
static int x_retry(int r, int dirfd, const char *path, int mode, int flags) {
    if (r == 0 || !(mode & X_OK) || errno != EACCES) return r;
    int e = errno;
    int rest = mode & ~X_OK;
    int ok = rest ? (real_faccessat ? real_faccessat(dirfd, path, rest, flags)
                                    : (int)syscall(SYS_faccessat, dirfd, path, rest)) == 0 : 1;
    if (ok && runs_anyway(dirfd, path)) return 0;
    errno = e;
    return r;
}

EXPORT int access(const char *path, int mode) {
    int r = real_access ? real_access(path, mode) : (int)syscall(SYS_faccessat, AT_FDCWD, path, mode);
    return x_retry(r, AT_FDCWD, path, mode, 0);
}

EXPORT int faccessat(int dirfd, const char *path, int mode, int flags) {
    int r = real_faccessat ? real_faccessat(dirfd, path, mode, flags) : (int)syscall(SYS_faccessat, dirfd, path, mode);
    return x_retry(r, dirfd, path, mode, flags);
}

#ifdef __GLIBC__
/* glibc's euidaccess and eaccess (bash's test -x) check through faccessat inside glibc. */
EXPORT int euidaccess(const char *path, int mode) { return faccessat(AT_FDCWD, path, mode, AT_EACCESS); }
EXPORT int eaccess(const char *path, int mode) { return faccessat(AT_FDCWD, path, mode, AT_EACCESS); }
#endif

/* ---- shared memory (glibc and musl programs) ---- */

#if SELF_WORLD != 0
/*
 * Two ways Linux programs share memory between processes, both of which
 * Android gets in the way of:
 *
 *  - memfd: allowed, but Android's SELinux policy lets an app read, write and
 *    map its memfds, not open them again by path. Programs that make a
 *    read-only copy that way (open("/proc/self/fd/N", O_RDONLY): Firefox,
 *    Chromium's read-only regions) get EACCES. They get a copy of the
 *    descriptor instead (dup). Firefox seals the memfd against writes before
 *    handing out that copy, so it stays read-only where it counts.
 *  - shm_open: Android has no /dev/shm, and glibc's and musl's shm_open open
 *    /dev/shm/<name> inside libc, out of reach of path mapping (ddflatpak's
 *    /dev/shm mount). shm_open and shm_unlink here open that path through
 *    open(), which ddflatpak maps when it's loaded; failing that they use
 *    $DDMASK_SHM, or $TMPDIR/ddmask-shm.
 */
typedef int (*open_fn)(const char *, int, ...);
typedef int (*openat_fn)(int, const char *, int, ...);
static open_fn real_open_;
static openat_fn real_openat_;
#ifdef __GLIBC__
static open_fn real_open64_;
static openat_fn real_openat64_;
#endif

/* After a failed open of path: a copy of the memfd it names, or -1 (errno kept). */
static int memfd_reopen(int dirfd, const char *path, int flags) {
    if (errno != EACCES || !path) return -1;
    int e = errno;
    if (dirfd != AT_FDCWD && path[0] != '/') return -1;
    const char *s;
    if (!strncmp(path, "/proc/self/fd/", 14)) s = path + 14;
    else if (!strncmp(path, "/proc/thread-self/fd/", 21)) s = path + 21;
    else if (!strncmp(path, "/proc/", 6)) {
        char *end;
        long pid = strtol(path + 6, &end, 10);
        if (pid != getpid() || strncmp(end, "/fd/", 4)) return -1;
        s = end + 4;
    } else return -1;
    char *end;
    long fd = strtol(s, &end, 10);
    if (end == s || *end || fd < 0 || fd > 1 << 20) return -1;
    if (flags & (O_CREAT | O_TRUNC | O_DIRECTORY)) return -1;
    char p[64], target[PATH_MAX];
    snprintf(p, sizeof p, "/proc/self/fd/%ld", fd);
    ssize_t len = real_readlink ? real_readlink(p, target, sizeof target - 1) : readlink(p, target, sizeof target - 1);
    if (len < 7 || strncmp(target, "/memfd:", 7) != 0) { errno = e; return -1; }
    int copy = fcntl((int)fd, (flags & O_CLOEXEC) ? F_DUPFD_CLOEXEC : F_DUPFD, 0);
    if (copy < 0) { errno = e; return -1; }
    return copy;
}

#define OPEN_MODE(flags) \
    mode_t mode = 0; \
    if (((flags) & O_CREAT) || ((flags) & O_TMPFILE) == O_TMPFILE) { va_list ap; va_start(ap, flags); mode = va_arg(ap, int); va_end(ap); }
#define REAL_OPEN(v, name) if (!v) v = (__typeof__(v))dlsym(RTLD_NEXT, name)

EXPORT int open(const char *path, int flags, ...) {
    OPEN_MODE(flags); REAL_OPEN(real_open_, "open");
    int r = real_open_ ? real_open_(path, flags, mode) : (int)syscall(SYS_openat, AT_FDCWD, path, flags, mode);
    return r >= 0 ? r : memfd_reopen(AT_FDCWD, path, flags);
}
EXPORT int openat(int dirfd, const char *path, int flags, ...) {
    OPEN_MODE(flags); REAL_OPEN(real_openat_, "openat");
    int r = real_openat_ ? real_openat_(dirfd, path, flags, mode) : (int)syscall(SYS_openat, dirfd, path, flags, mode);
    return r >= 0 ? r : memfd_reopen(dirfd, path, flags);
}
#ifdef __GLIBC__
EXPORT int open64(const char *path, int flags, ...) {
    OPEN_MODE(flags); REAL_OPEN(real_open64_, "open64");
    int r = real_open64_ ? real_open64_(path, flags, mode) : (int)syscall(SYS_openat, AT_FDCWD, path, flags | O_LARGEFILE, mode);
    return r >= 0 ? r : memfd_reopen(AT_FDCWD, path, flags);
}
EXPORT int openat64(int dirfd, const char *path, int flags, ...) {
    OPEN_MODE(flags); REAL_OPEN(real_openat64_, "openat64");
    int r = real_openat64_ ? real_openat64_(dirfd, path, flags, mode) : (int)syscall(SYS_openat, dirfd, path, flags | O_LARGEFILE, mode);
    return r >= 0 ? r : memfd_reopen(dirfd, path, flags);
}
/* What _FORTIFY_SOURCE builds call for open(path, flags). */
EXPORT int __open_2(const char *path, int flags) { return open(path, flags); }
EXPORT int __open64_2(const char *path, int flags) { return open64(path, flags); }
EXPORT int __openat_2(int dirfd, const char *path, int flags) { return openat(dirfd, path, flags); }
EXPORT int __openat64_2(int dirfd, const char *path, int flags) { return openat64(dirfd, path, flags); }
#endif

/* /dev/shm/<name> for a shm_open name (one '/' first, none after), or -1 (EINVAL). */
static int shm_path(const char *name, const char *dir, char *out, size_t size) {
    while (*name == '/') name++;
    if (!*name || strchr(name, '/') || !strcmp(name, ".") || !strcmp(name, "..")) { errno = EINVAL; return -1; }
    if ((size_t)snprintf(out, size, "%s/%s", dir, name) >= size) { errno = ENAMETOOLONG; return -1; }
    return 0;
}

/* Where shared memory goes when /dev/shm can't be had, made if needed. */
static const char *shm_fallback(char *buf, size_t size) {
    const char *d = getenv("DDMASK_SHM");
    if (d && *d) snprintf(buf, size, "%s", d);
    else {
        const char *t = getenv("TMPDIR");
        snprintf(buf, size, "%s/ddmask-shm", t && *t ? t : "/tmp");
    }
    mkdir(buf, 0700);
    return buf;
}

EXPORT int shm_open(const char *name, int flags, mode_t mode) {
    char p[PATH_MAX], dir[PATH_MAX];
    flags |= O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK;
    if (shm_path(name, "/dev/shm", p, sizeof p) != 0) return -1;
    int r = open(p, flags, mode);
    if (r >= 0 || (errno != ENOENT && errno != EACCES && errno != EROFS && errno != ENOTDIR)) return r;
    /* ENOENT on a name that should exist: /dev/shm itself, or just the name? */
    if (errno == ENOENT && !(flags & O_CREAT)) {
        struct stat st;
        if (stat("/dev/shm", &st) == 0 && S_ISDIR(st.st_mode)) { errno = ENOENT; return r; }
    }
    if (shm_path(name, shm_fallback(dir, sizeof dir), p, sizeof p) != 0) return -1;
    return open(p, flags, mode);
}

EXPORT int shm_unlink(const char *name) {
    char p[PATH_MAX], dir[PATH_MAX];
    if (shm_path(name, "/dev/shm", p, sizeof p) != 0) return -1;
    int r = unlink(p);
    if (r == 0 || (errno != ENOENT && errno != EACCES && errno != EROFS && errno != ENOTDIR)) return r;
    if (shm_path(name, shm_fallback(dir, sizeof dir), p, sizeof p) != 0) return -1;
    return unlink(p);
}
#endif

/* ---- blocked system calls (glibc and musl programs) ---- */

#if SELF_WORLD != 0 && (defined(__aarch64__) || defined(__x86_64__))
#define DDMASK_SIGSYS 1
#ifndef SYS_faccessat2
#define SYS_faccessat2 439
#endif
#ifndef SYS_epoll_pwait2
#define SYS_epoll_pwait2 441
#endif
#ifndef SYS_close_range
#define SYS_close_range 436
#endif
#ifndef SYS_fchmodat2
#define SYS_fchmodat2 452
#endif
#ifndef DDMASK_GLIBC_PREFIX
#define DDMASK_GLIBC_PREFIX "/data/data/io.deskdroid.app/files/glibc"
#endif
static char sigsys_log[PATH_MAX];       /* the numbers, one a line, as glibc's loader notes them */
static unsigned char sigsys_seen[128];  /* calls already in the journal */
static int sigsys_on;                   /* on_sigsys is installed */
/* The SIGSYS action the program asked for. It is recorded rather than
 * installed (see the wrappers after catch_sigsys), and on_sigsys passes it
 * any SIGSYS that seccomp did not send. */
static struct sigaction prog_sigsys;

static size_t put_num(char *p, unsigned long v) {
    char t[24];
    size_t n = 0, i = 0;
    do t[n++] = (char)('0' + v % 10); while ((v /= 10) && n < sizeof t);
    while (n) p[i++] = t[--n];
    return i;
}

static size_t put_str(char *p, size_t room, const char *s) {
    size_t n = strlen(s);
    if (n > room) n = room;
    memcpy(p, s, n);
    return n;
}

static long call_or_errno(long r) { return r == -1 ? -errno : r; }

/*
 * Android's seccomp filter traps a system call an app may not make (SIGSYS).
 * glibc's loader (native/glibc/patch.py) already makes them fail with ENOSYS;
 * this handler, installed once the program's libraries are loaded, first
 * makes the ones that have an allowed twin with that twin, so the program gets
 * what it asked for. Each call is noted in the journal once per process.
 */
static void on_sigsys(int sig, siginfo_t *si, void *ctx) {
    (void)sig;
    ucontext_t *uc = ctx;
    int e = errno;
#if defined(__aarch64__)
    unsigned long long *rg = (unsigned long long *)uc->uc_mcontext.regs;
#define ARG(i) ((long)rg[i])
#define SET_RET(v) (rg[0] = (unsigned long long)(v))
#else
    greg_t *g = uc->uc_mcontext.gregs;
    static const int argreg[6] = { REG_RDI, REG_RSI, REG_RDX, REG_R10, REG_R8, REG_R9 };
#define ARG(i) ((long)g[argreg[i]])
#define SET_RET(v) (g[REG_RAX] = (greg_t)(v))
#endif
    /* The program's own: sent by kill() rather than seccomp (SYS_SECCOMP, 1),
     * or by a seccomp filter of its own. Android's filter traps with no data
     * (SECCOMP_RET_DATA, in si_errno); the program's sandbox (Firefox's,
     * Chromium's) traps with its own, and answers in its handler. Without a
     * handler: ENOSYS, as glibc's loader answers (its test sends one). */
    if ((si->si_code != 1 || si->si_errno != 0)
        && prog_sigsys.sa_handler != SIG_DFL && prog_sigsys.sa_handler != SIG_IGN) {
        errno = e;
        if (prog_sigsys.sa_flags & SA_SIGINFO) prog_sigsys.sa_sigaction(sig, si, ctx);
        else prog_sigsys.sa_handler(sig);
        return;
    }
    long nr = si->si_code == 1 ? si->si_syscall : -1, ret = -ENOSYS;
    const char *as = NULL;
    switch (nr) {
#ifdef SYS_accept
    case SYS_accept:
        ret = call_or_errno(syscall(SYS_accept4, ARG(0), ARG(1), ARG(2), 0));
        as = "accept4";
        break;
#endif
    case SYS_epoll_pwait2: {
        const struct timespec *ts = (const struct timespec *)ARG(3);
        long ms = ts ? ts->tv_sec * 1000 + (ts->tv_nsec + 999999) / 1000000 : -1;
        if (ms > 0x7fffffffL) ms = 0x7fffffffL;
        ret = call_or_errno(syscall(SYS_epoll_pwait, ARG(0), ARG(1), ARG(2), ms, ARG(4), ARG(5)));
        as = "epoll_pwait";
        break;
    }
    case SYS_faccessat2:
        if (ARG(3) == 0) {
            ret = call_or_errno(syscall(SYS_faccessat, ARG(0), ARG(1), ARG(2)));
            as = "faccessat";
        }
        break;
    case SYS_fchmodat2:
        if (ARG(3) == 0) {
            ret = call_or_errno(syscall(SYS_fchmodat, ARG(0), ARG(1), ARG(2)));
            as = "fchmodat";
        }
        break;
    /* Android's app filter blocks the set*id calls, even ones that change
     * nothing: PulseAudio drops "root" with setresgid(gid, gid, gid) as a
     * plain user and aborts when it fails. A call that asks only for the ids
     * the process already has succeeds; any real change gets EPERM, as it
     * would for an unprivileged user. */
    case SYS_setresuid: case SYS_setresgid: case SYS_setreuid: case SYS_setregid:
    case SYS_setuid: case SYS_setgid: {
        int gid = nr == SYS_setresgid || nr == SYS_setregid || nr == SYS_setgid;
        long cur[3] = { -1, -1, -1 };
        unsigned int ids[3];
        if (syscall(gid ? SYS_getresgid : SYS_getresuid, &ids[0], &ids[1], &ids[2]) == 0)
            for (int i = 0; i < 3; i++) cur[i] = ids[i];
        int nargs = nr == SYS_setresuid || nr == SYS_setresgid ? 3 : nr == SYS_setuid || nr == SYS_setgid ? 1 : 2;
        ret = 0;
        for (int i = 0; i < nargs; i++) {
            long want = (long)(unsigned int)ARG(i);
            if (want == 0xffffffffL) continue;   /* -1: leave it */
            if (want != cur[0] || want != cur[1] || want != cur[2]) ret = -EPERM;
        }
        as = "a no-op (same ids)";
        break;
    }
    case SYS_close_range: {
        /* close_range(first, last, flags): each one, up to the open-file limit;
         * CLOSE_RANGE_CLOEXEC (4) marks them instead. Not CLOSE_RANGE_UNSHARE. */
        unsigned long first = (unsigned long)ARG(0), last = (unsigned long)ARG(1), fl = (unsigned long)ARG(2);
        if (fl & ~4UL) break;
        struct { unsigned long cur, max; } lim = { 1024, 1024 };
        syscall(SYS_prlimit64, 0, RLIMIT_NOFILE, NULL, &lim);
        if (last >= lim.cur) last = lim.cur ? lim.cur - 1 : 0;
        for (unsigned long fd = first; fd <= last && fd < (1UL << 20); fd++) {
            if (fl & 4) syscall(SYS_fcntl, (long)fd, F_SETFD, FD_CLOEXEC);
            else syscall(SYS_close, (long)fd);
        }
        ret = first > (unsigned long)ARG(1) ? -EINVAL : 0;
        as = fl & 4 ? "fcntl" : "close";
        break;
    }
    }
    SET_RET(ret);
#undef ARG
#undef SET_RET
    char line[PATH_MAX + 160];
    size_t n = 0;
    if (nr < 0) { errno = e; return; }
    if (sigsys_log[0]) {
        n = put_num(line, (unsigned long)nr);
        line[n++] = '\n';
        journal_write(sigsys_log, line, n);
    }
    if (journal_path[0] && nr >= 0 && nr < (long)sizeof sigsys_seen * 8
        && !(sigsys_seen[nr / 8] & (1u << (nr % 8)))) {
        sigsys_seen[nr / 8] |= (unsigned char)(1u << (nr % 8));
        n = put_str(line, 32, "ddmask[");
        n += put_num(line + n, (unsigned long)getpid());
        n += put_str(line + n, 8, "]: ");
        n += put_str(line + n, PATH_MAX, exe_path[0] ? exe_path : "(this program)");
        n += put_str(line + n, 64, ": Android blocks system call ");
        n += put_num(line + n, (unsigned long)nr);
        if (as) { n += put_str(line + n, 16, ", made as "); n += put_str(line + n, 32, as); }
        else n += put_str(line + n, 32, ", failed with ENOSYS");
        line[n++] = '\n';
        journal_write(journal_path, line, n);
    }
    errno = e;
}

typedef long (*syscall_fn)(long, ...);
static syscall_fn real_syscall;

static void catch_sigsys(void) {
    const char *off = getenv("DDMASK_SIGSYS");
    if (off && *off == '0') return;
    const char *l = getenv("DDMASK_SIGSYS_LOG");
    snprintf(sigsys_log, sizeof sigsys_log, "%s", l ? l : DDMASK_GLIBC_PREFIX "/sigsys.log");
    struct sigaction sa;
    memset(&sa, 0, sizeof sa);
    sa.sa_sigaction = on_sigsys;
    sa.sa_flags = SA_SIGINFO | SA_NODEFER;
    typedef int (*sigaction_fn)(int, const struct sigaction *, struct sigaction *);
    sigaction_fn real = (sigaction_fn)dlsym(RTLD_NEXT, "sigaction");
    real_syscall = (syscall_fn)dlsym(RTLD_NEXT, "syscall");
    if (real && real(SIGSYS, &sa, &prog_sigsys) == 0) sigsys_on = 1;
}

/*
 * Keeping the handler. A program that sets its own SIGSYS handler (FEX-Emu
 * takes every signal for the x86 program it runs) would otherwise replace
 * on_sigsys, and the next blocked call, such as set_robust_list in a new
 * thread, would reach that handler as a signal for the program and kill it
 * ("Bad system call"). So while on_sigsys is installed, setting SIGSYS only
 * records the program's handler, and blocking SIGSYS leaves it unblocked,
 * since a blocked seccomp SIGSYS kills the process outright. This covers
 * sigaction, signal, sigprocmask, pthread_sigmask and syscall() for
 * rt_sigaction and rt_sigprocmask, which is how FEX makes them.
 */
struct k_sigaction { void *handler; unsigned long flags; void *restorer; unsigned long mask; };
#define SIGSYS_BIT (1UL << (SIGSYS - 1))

static void record_sigsys(const struct sigaction *act, struct sigaction *old) {
    if (old) *old = prog_sigsys;
    if (act) prog_sigsys = *act;
}

EXPORT long syscall(long nr, ...) {
    va_list ap;
    va_start(ap, nr);
    long a[6];
    for (int i = 0; i < 6; i++) a[i] = va_arg(ap, long);
    va_end(ap);
    if (!real_syscall) real_syscall = (syscall_fn)dlsym(RTLD_NEXT, "syscall");
    if (sigsys_on && nr == SYS_rt_sigaction && a[0] == SIGSYS) {
        const struct k_sigaction *act = (const struct k_sigaction *)a[1];
        struct k_sigaction *old = (struct k_sigaction *)a[2];
        if (old) {
            memset(old, 0, sizeof *old);
            old->handler = prog_sigsys.sa_handler == SIG_DFL ? NULL : (void *)prog_sigsys.sa_handler;
            old->flags = (unsigned long)(unsigned int)prog_sigsys.sa_flags;
            memcpy(&old->mask, &prog_sigsys.sa_mask, sizeof old->mask);
        }
        if (act) {
            struct sigaction sa;
            memset(&sa, 0, sizeof sa);
            sa.sa_handler = (void (*)(int))act->handler;
            sa.sa_flags = (int)act->flags;
            memcpy(&sa.sa_mask, &act->mask, sizeof act->mask);
            prog_sigsys = sa;
        }
        return 0;
    }
    if (sigsys_on && nr == SYS_rt_sigprocmask && a[1] && a[0] != SIG_UNBLOCK) {
        unsigned long set = *(const unsigned long *)a[1] & ~SIGSYS_BIT;
        return real_syscall(nr, a[0], (long)&set, a[2], a[3], a[4], a[5]);
    }
    return real_syscall(nr, a[0], a[1], a[2], a[3], a[4], a[5]);
}

EXPORT int sigaction(int sig, const struct sigaction *act, struct sigaction *old) {
    typedef int (*fn)(int, const struct sigaction *, struct sigaction *);
    static fn real;
    if (!real) real = (fn)dlsym(RTLD_NEXT, "sigaction");
    if (sigsys_on && sig == SIGSYS) { record_sigsys(act, old); return 0; }
    return real(sig, act, old);
}

EXPORT sighandler_t signal(int sig, sighandler_t h) {
    typedef sighandler_t (*fn)(int, sighandler_t);
    static fn real;
    if (!real) real = (fn)dlsym(RTLD_NEXT, "signal");
    if (sigsys_on && sig == SIGSYS) {
        struct sigaction sa, old;
        memset(&sa, 0, sizeof sa);
        sa.sa_handler = h;
        sa.sa_flags = SA_RESTART;
        record_sigsys(&sa, &old);
        return old.sa_handler;
    }
    return real(sig, h);
}

static const sigset_t *keep_sigsys(int how, const sigset_t *set, sigset_t *copy) {
    if (!sigsys_on || !set || how == SIG_UNBLOCK || !sigismember(set, SIGSYS)) return set;
    *copy = *set;
    sigdelset(copy, SIGSYS);
    return copy;
}

EXPORT int sigprocmask(int how, const sigset_t *set, sigset_t *old) {
    typedef int (*fn)(int, const sigset_t *, sigset_t *);
    static fn real;
    if (!real) real = (fn)dlsym(RTLD_NEXT, "sigprocmask");
    sigset_t copy;
    return real(how, keep_sigsys(how, set, &copy), old);
}

EXPORT int pthread_sigmask(int how, const sigset_t *set, sigset_t *old) {
    typedef int (*fn)(int, const sigset_t *, sigset_t *);
    static fn real;
    if (!real) real = (fn)dlsym(RTLD_NEXT, "pthread_sigmask");
    sigset_t copy;
    return real(how, keep_sigsys(how, set, &copy), old);
}
#endif

/* ---- in every process ---- */

__attribute__((constructor)) static void ddmask_init(int argc, char **argv, char **envp) {
    (void)envp;
    real_execve = (execve_fn)dlsym(RTLD_NEXT, "execve");
    real_posix_spawn = (spawn_fn)dlsym(RTLD_NEXT, "posix_spawn");
    real_readlink = (readlink_fn)dlsym(RTLD_NEXT, "readlink");
    real_readlinkat = (readlinkat_fn)dlsym(RTLD_NEXT, "readlinkat");
    real_access = (access_fn)dlsym(RTLD_NEXT, "access");
    real_faccessat = (faccessat_fn)dlsym(RTLD_NEXT, "faccessat");
    const char *jf = getenv("DDMASK_JOURNAL");
    if (jf && *jf) snprintf(journal_path, sizeof journal_path, "%s", jf);

    Dl_info info;
    if (dladdr((void *)ddmask_init, &info) && info.dli_fname) {
        if (!realpath(info.dli_fname, self_path)) snprintf(self_path, sizeof self_path, "%s", info.dli_fname);
        snprintf(self_dir, sizeof self_dir, "%s", self_path);
        char *slash = strrchr(self_dir, '/');
        if (slash) *slash = 0; else self_dir[0] = 0;
    }
    const char *libs = getenv("DDMASK_LIBS");
    snprintf(apk_dir, sizeof apk_dir, "%s", libs && *libs ? libs : self_dir);
    /* The ddmask module (DDMASK_MODULE, an installed package with api-1):
     * its builds for the other worlds come first, then the ones next to this
     * one, then the APK's. */
    char mod_lib[PATH_MAX] = "";
    const char *mod = getenv("DDMASK_MODULE");
    if (mod && *mod) {
        char api[PATH_MAX];
        if ((size_t)snprintf(api, sizeof api, "%s/api-1", mod) < sizeof api && access(api, F_OK) == 0)
            snprintf(mod_lib, sizeof mod_lib, "%s/lib", mod);
    }
    for (int w = 0; w < WORLDS; w++) {
        if (w == SELF_WORLD) { snprintf(shims[w], PATH_MAX, "%s", self_path); continue; }
        /* Android's (bionic) build from the module only when the desktop
         * found Android's linker takes it (NativeDesk.kt checks: DDMASK_MODULE_BIONIC). */
        const char *mb = getenv("DDMASK_MODULE_BIONIC");
        int mod_ok = w != 0 || (mb && *mb == '1');
        const char *dirs[3] = { mod_ok ? mod_lib : "", mod_ok ? self_dir : apk_dir, mod_ok ? apk_dir : self_dir };
        shims[w][0] = 0;
        for (int d = 0; d < 3 && !shims[w][0]; d++) {
            if (!dirs[d][0]) continue;
            if ((size_t)snprintf(shims[w], PATH_MAX, "%s/%s", dirs[d], worlds[w].shim) >= PATH_MAX
                || access(shims[w], F_OK) != 0) shims[w][0] = 0;
        }
    }

    /* Started through a loader by ddmask: take back the program's identity. */
    const char *exe = getenv("DDMASK_EXE");
    if (exe) {
        snprintf(exe_path, sizeof exe_path, "%s", exe);
        unsetenv("DDMASK_EXE");
    }
    const char *a0 = getenv("DDMASK_ARGV0");
    if (a0) {
        /* (musl calls constructors without arguments: argc and argv aren't there.) */
#ifndef DDMASK_MUSL
        if (argc > 0 && argv) {
            char *copy = strdup(a0);
            if (copy) argv[0] = copy;
        }
#else
        (void)argc; (void)argv;
#endif
        unsetenv("DDMASK_ARGV0");
    }
    if (exe_path[0]) {
        const char *name = strrchr(exe_path, '/');
        prctl(PR_SET_NAME, name ? name + 1 : exe_path, 0, 0, 0);
    }
#ifdef DDMASK_SIGSYS
    catch_sigsys();
#endif
}

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
#include <sys/prctl.h>
#include <sys/stat.h>
#include <sys/syscall.h>
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
    { "libddmask_glibc.so", "libdd_ld-glibc.so", "/lib/ld-linux-aarch64.so.1", "DDMASK_GLIBC_LD_PRELOAD" },
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

static void logf_(char *const envp[], const char *fmt, ...) {
    const char *d = env_get(envp, "DDMASK_DEBUG");
    if (!d || !*d || *d == '0') return;
    char buf[PATH_MAX + 256];
    int n = snprintf(buf, sizeof buf, "ddmask[%d]: ", (int)getpid());
    va_list ap;
    va_start(ap, fmt);
    n += vsnprintf(buf + n, sizeof buf - n, fmt, ap);
    va_end(ap);
    if (n > (int)sizeof buf - 2) n = sizeof buf - 2;
    buf[n++] = '\n';
    ssize_t w = write(2, buf, n);
    (void)w;
}

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
    return self_dir[0] && in_dir(real, self_dir, strlen(self_dir));
#else
    return 1;
#endif
}

/* Whether `runner` is glibc's or musl's loader from the APK. */
static int is_world_loader(const char *runner) {
    const char *base = strrchr(runner, '/');
    base = base ? base + 1 : runner;
    for (int w = 0; w < WORLDS; w++)
        if (worlds[w].loader && strcmp(base, worlds[w].loader) == 0) return 1;
    return 0;
}

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
        if (!wd->interp || strcmp(path, wd->interp) != 0 || !self_dir[0] || (map && strstr(map, wd->interp))) continue;
        if ((size_t)snprintf(out, outsz, "%s/%s", self_dir, wd->loader) < outsz && access(out, F_OK) == 0) return out;
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
static char *with_preload(char *const envp[], const char *var, const char *lib, char *buf, size_t size) {
    const char *cur = env_get(envp, var);
    if (cur && *cur && strstr(cur, lib)) snprintf(buf, size, "%s=%s", var, cur);
    else if (cur && *cur) snprintf(buf, size, "%s=%s:%s", var, lib, cur);
    else snprintf(buf, size, "%s=%s", var, lib);
    return buf;
}

static int is_var(const char *entry, const char *var) {
    size_t n = strlen(var);
    return strncmp(entry, var, n) == 0 && entry[n] == '=';
}

/* New environment: each of ddmask's builds that's there in its world's preload
 * variable (LD_PRELOAD, DDMASK_GLIBC_LD_PRELOAD, DDMASK_MUSL_LD_PRELOAD);
 * DDMASK_EXE/DDMASK_ARGV0 only when given. nenvp has room for count(envp) + WORLDS + 3. */
static void build_env(char *const envp[], char **nenvp, struct plan *pl, int with_exe) {
    int j = 0;
    for (char *const *e = envp; e && *e; e++) {
        if (is_var(*e, "DDMASK_EXE") || is_var(*e, "DDMASK_ARGV0")) continue;
        int ours = 0;
        for (int w = 0; w < WORLDS; w++) if (shims[w][0] && is_var(*e, worlds[w].var)) ours = 1;
        if (!ours) nenvp[j++] = *e;
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
 * count(argv) + EXTRA_ARGS) and nenvp (room for count(envp) + WORLDS + 3). Returns 0,
 * or -1 with errno set when it can't be started.
 */
static int plan_exec(const char *path, char *const argv[], char *const envp[],
                     const char **npath, char **nargv, char **nenvp, struct plan *pl) {
    int argc = count(argv);
    const char *cur = path;
    /* The argument vector so far; scripts prepend their interpreter. */
    int off = EXTRA_ARGS;   /* nargv[off..] holds the current argv */
    for (int i = 0; i < argc; i++) nargv[off + i] = argv[i];
    nargv[off + argc] = NULL;
    if (argc == 0) { nargv[off] = (char *)path; nargv[off + 1] = NULL; argc = 1; }
    pl->env_exe[0] = pl->env_argv0[0] = 0;
    int with_exe = 0;

    for (int depth = 0;; depth++) {
        char resolved[PATH_MAX];
        if (!realpath(cur, resolved) || exec_allowed(resolved, envp)) {
            /* Let the kernel do it (or report why it can't). */
            *npath = cur;
            break;
        }
        struct stat st;
        if (stat(resolved, &st) != 0) return -1;
        if (!S_ISREG(st.st_mode) || !(st.st_mode & (S_IXUSR | S_IXGRP | S_IXOTH))) { errno = EACCES; return -1; }
        if (depth >= MAX_DEPTH) { errno = ELOOP; return -1; }
        /* A file opened by fd (fexecve, execveat) may close on exec: name it by its real path. */
        const char *prog = strncmp(cur, "/proc/self/fd/", 14) == 0 ? strcpy(pl->real, resolved) : cur;
        int machine, appimage = 0;
        char *interp = pl->interp[depth], *arg = pl->arg[depth];
        enum kind k = classify(resolved, interp, PATH_MAX, arg, LINE_MAX_SCRIPT, &machine, &appimage);
        const char *runner = NULL;
        const char *argv0_opt = NULL; /* glibc's and musl's loaders take the program's argv[0] as --argv0 */
        int keep_argv0 = 0;           /* ddload and the AppImage runner take: <program> <argv[0]> <args> */
        /* An AppImage: unpacked (no FUSE on Android) and its AppRun started, by
         * libdd_appimage.so; which runs the AppImage itself, to unpack it, with
         * DDMASK_APPIMAGE_RAW=1: then it's just a program. */
        const char *raw = env_get(envp, "DDMASK_APPIMAGE_RAW");
        if (appimage && !(raw && *raw && *raw != '0') && self_dir[0]) {
            snprintf(pl->emu, sizeof pl->emu, "%s/libdd_appimage.so", self_dir);
            if (access(pl->emu, F_OK) == 0) { runner = pl->emu; keep_argv0 = 1; k = RUN_FALLBACK; }
        }
        switch (runner ? RUN_FALLBACK : k) {
        case RUN_AS_IS:
            *npath = cur;
            goto done;
        case RUN_NOEXEC:
            errno = ENOEXEC;
            return -1;
        case RUN_LOADER:
            runner = map_path(interp, envp, pl->mapped[depth], PATH_MAX);
            if (access(runner, F_OK) != 0) runner = NULL; /* glibc's loader on Android... */
            if (runner) {
                snprintf(pl->env_exe, sizeof pl->env_exe, "DDMASK_EXE=%s", resolved);
                if (is_world_loader(runner)) argv0_opt = nargv[off];
                else if ((size_t)snprintf(pl->env_argv0, sizeof pl->env_argv0, "DDMASK_ARGV0=%s", nargv[off]) >= sizeof pl->env_argv0)
                    pl->env_argv0[0] = 0;
                with_exe = 1;
            }
            break;
        case RUN_STATIC:
            /* No loader to start it through: ddmask's own (ddload.c). */
            if (self_dir[0]) {
                snprintf(pl->emu, sizeof pl->emu, "%s/libdd_static.so", self_dir);
                if (access(pl->emu, F_OK) == 0) { runner = pl->emu; keep_argv0 = 1; }
            }
            break;
        case RUN_EMULATOR: {
            const char *e = env_get(envp, machine == EM_X86_64 ? "DDMASK_X86_64" : "DDMASK_I386");
            if (!e && machine == EM_X86_64 && self_dir[0]) {
                snprintf(pl->emu, sizeof pl->emu, "%s/libbox64.so", self_dir);
                if (access(pl->emu, F_OK) == 0) e = pl->emu;
            }
            runner = e && *e ? e : NULL;
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
            logf_(envp, "%s: can't be started (no loader for it)", cur);
            errno = EACCES;
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
    build_env(envp, nenvp, pl, with_exe);
    /* Move argv to the front. */
    int i = 0;
    while (nargv[off + i]) { nargv[i] = nargv[off + i]; i++; }
    nargv[i] = NULL;
    return 0;
}

static int dd_execve(const char *path, char *const argv[], char *const envp[]) {
    if (!path) { errno = EFAULT; return -1; }
    char *nargv[count(argv) + EXTRA_ARGS + 2];
    char *nenvp[count(envp) + WORLDS + 3];
    struct plan pl;
    const char *npath;
    if (plan_exec(path, argv, envp, &npath, nargv, nenvp, &pl) != 0) return -1;
    return sys_execve(npath, nargv, nenvp);
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
    size_t na = count(argv) + EXTRA_ARGS + 2, ne = count(envp) + WORLDS + 3;
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

/* ---- in every process ---- */

__attribute__((constructor)) static void ddmask_init(int argc, char **argv, char **envp) {
    (void)envp;
    real_execve = (execve_fn)dlsym(RTLD_NEXT, "execve");
    real_posix_spawn = (spawn_fn)dlsym(RTLD_NEXT, "posix_spawn");
    real_readlink = (readlink_fn)dlsym(RTLD_NEXT, "readlink");
    real_readlinkat = (readlinkat_fn)dlsym(RTLD_NEXT, "readlinkat");

    Dl_info info;
    if (dladdr((void *)ddmask_init, &info) && info.dli_fname) {
        if (!realpath(info.dli_fname, self_path)) snprintf(self_path, sizeof self_path, "%s", info.dli_fname);
        snprintf(self_dir, sizeof self_dir, "%s", self_path);
        char *slash = strrchr(self_dir, '/');
        if (slash) *slash = 0; else self_dir[0] = 0;
    }
    if (self_dir[0]) {
        for (int w = 0; w < WORLDS; w++) {
            if (w == SELF_WORLD) { snprintf(shims[w], PATH_MAX, "%s", self_path); continue; }
            if ((size_t)snprintf(shims[w], PATH_MAX, "%s/%s", self_dir, worlds[w].shim) >= PATH_MAX
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
}

/*
 * ddflatpak: runs a Flatpak app without bubblewrap.
 *
 * Flatpak normally starts an app inside bubblewrap, with the app's files
 * mounted at /app and its runtime's at /usr. Android gives apps no user
 * namespaces, so bubblewrap can't run there. This library is preloaded into
 * the app (glibc side, next to libddmask_glibc.so) and rewrites the paths
 * the app asks the C library for instead:
 *
 *   /app/...            -> $DDFLATPAK_APP/...
 *   /usr/...            -> $DDFLATPAK_RUNTIME/...
 *   /lib /lib64 /bin /sbin -> the runtime's (Flatpak links them into /usr)
 *   /etc/<x>            -> $DDFLATPAK_RUNTIME/etc/<x> when the runtime has it
 *   /tmp /var/tmp       -> $DDFLATPAK_TMP when set
 *   extensions (GL drivers, codecs, locales), from $DDFLATPAK_MOUNTS:
 *   "<path>=<folder>;..." where Flatpak would mount each one, checked first
 *   and in order (list the longer paths first)
 *
 * Programs the app starts get the same treatment: an ELF program is started
 * through the runtime's loader ($DDFLATPAK_LOADER) with the runtime's
 * library path ($DDFLATPAK_LIBPATH), so they use the runtime's glibc, not
 * the system's. On Android, ddmask (ddmask.c) does that step instead.
 *
 * Limits: only calls that go through the C library's exported functions are
 * seen. Programs that make raw system calls (static Go programs) or glibc's
 * own internal file reads (locales, gconv) see the real paths.
 *
 * Tested on desktop Linux by test/flatpak.sh.
 */
#define _GNU_SOURCE
#include <dirent.h>
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <sys/auxv.h>
#include <spawn.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/statfs.h>
#include <sys/statvfs.h>
#include <sys/types.h>
#include <unistd.h>

static const char *env_app, *env_rt, *env_tmp, *env_loader, *env_libpath;
static int debug;
#define MAX_MOUNTS 32
static struct { char *at, *to; } mounts[MAX_MOUNTS];
static int n_mounts;
/* The program this process runs, when it started through the loader. */
static char self_exe[PATH_MAX];

__attribute__((constructor)) static void ddflatpak_init(void) {
    env_app = getenv("DDFLATPAK_APP");
    env_rt = getenv("DDFLATPAK_RUNTIME");
    env_tmp = getenv("DDFLATPAK_TMP");
    env_loader = getenv("DDFLATPAK_LOADER");
    env_libpath = getenv("DDFLATPAK_LIBPATH");
    debug = getenv("DDFLATPAK_DEBUG") != NULL;
    const char *ms = getenv("DDFLATPAK_MOUNTS");
    if (ms) {
        char *all = strdup(ms), *save = NULL;
        for (char *m = strtok_r(all, ";", &save); m && n_mounts < MAX_MOUNTS; m = strtok_r(NULL, ";", &save)) {
            char *eq = strchr(m, '=');
            if (!eq || m[0] != '/') continue;
            *eq = 0;
            mounts[n_mounts].at = m;
            mounts[n_mounts++].to = eq + 1;
        }
    }
    /* Started as "<loader> <program>", /proc/self/exe names the loader.
     * Chromium (Electron) finds its files next to /proc/self/exe and starts
     * its helpers by exec'ing it, so it must name the program instead. The
     * loader points AT_EXECFN at the program it was given. */
    char exe[PATH_MAX];
    ssize_t (*rl)(const char *, char *, size_t) = dlsym(RTLD_NEXT, "readlink");
    ssize_t n = rl("/proc/self/exe", exe, sizeof exe - 1);
    if (n > 0) {
        exe[n] = 0;
        const char *base = strrchr(exe, '/') ? strrchr(exe, '/') + 1 : exe;
        const char *prog = (const char *)getauxval(AT_EXECFN);
        /* glibc's loader: the system's, or DeskDroid's (libdd_ld-glibc.so). */
        int loader = !strncmp(base, "ld-linux", 8) || !strncmp(base, "libdd_ld-", 9);
        if (loader && prog && prog[0] == '/' && strcmp(prog, exe))
            snprintf(self_exe, sizeof self_exe, "%s", prog);
    }
}

/* readlink of /proc/self/exe: the program, not the loader. */
static ssize_t self_link(const char *p, char *o, size_t n) {
    if (!self_exe[0] || (strcmp(p, "/proc/self/exe") && strcmp(p, "/proc/thread-self/exe"))) return -2;
    size_t l = strlen(self_exe);
    if (l > n) l = n;
    memcpy(o, self_exe, l);
    return (ssize_t)l;
}

/* "/usr" matches "/usr" and "/usr/x", not "/usrx". Returns the rest. */
static const char *under(const char *path, const char *prefix) {
    size_t n = strlen(prefix);
    if (strncmp(path, prefix, n) != 0) return NULL;
    if (path[n] == '\0' || path[n] == '/') return path + n;
    return NULL;
}

static int join(char *out, const char *base, const char *sub, const char *rest) {
    int n = snprintf(out, PATH_MAX, "%s%s%s", base, sub, rest);
    return n > 0 && n < PATH_MAX;
}

/* Rewrites path into buf and returns buf, or returns path unchanged. */
static const char *map(const char *path, char *buf) {
    const char *rest;
    if (!path || path[0] != '/' || !env_rt) return path;
    if (self_exe[0] && !strcmp(path, "/proc/self/exe")) return self_exe;
    for (int i = 0; i < n_mounts; i++)
        if ((rest = under(path, mounts[i].at)) && join(buf, mounts[i].to, "", rest)) goto mapped;
    if (env_app && (rest = under(path, "/app")) && join(buf, env_app, "", rest)) goto mapped;
    if ((rest = under(path, "/usr")) && join(buf, env_rt, "", rest)) goto mapped;
    if ((rest = under(path, "/lib")) && join(buf, env_rt, "/lib", rest)) goto mapped;
    if ((rest = under(path, "/lib64")) && join(buf, env_rt, "/lib64", rest)) goto mapped;
    if ((rest = under(path, "/bin")) && join(buf, env_rt, "/bin", rest)) goto mapped;
    if ((rest = under(path, "/sbin")) && join(buf, env_rt, "/bin", rest)) goto mapped;
    if (env_tmp && ((rest = under(path, "/tmp")) || (rest = under(path, "/var/tmp")))
        && join(buf, env_tmp, "", rest)) goto mapped;
    if ((rest = under(path, "/etc")) && *rest && join(buf, env_rt, "/etc", rest)) {
        /* Only what the runtime ships; the rest (resolv.conf from the
         * system, the user's own files) stays where it is. */
        static int (*real_access)(const char *, int);
        if (!real_access) real_access = dlsym(RTLD_NEXT, "access");
        if (real_access(buf, F_OK) == 0) goto mapped;
    }
    return path;
mapped:
    if (debug) fprintf(stderr, "ddflatpak: %s -> %s\n", path, buf);
    return buf;
}

#define REAL(name) static __typeof__(name) *real_##name; \
    if (!real_##name) real_##name = (__typeof__(name) *)dlsym(RTLD_NEXT, #name)

/* Android (SELinux) doesn't let apps make hard links in their data, so a
 * file opened with O_TMPFILE can never get a name (linkat). Say the folder
 * doesn't support O_TMPFILE: OSTree, Flatpak and GLib then write a named
 * temporary file and rename it, which works.  */
#define NO_TMPFILE(flags) if (((flags) & O_TMPFILE) == O_TMPFILE) { errno = EOPNOTSUPP; return -1; }

#define MODE_ARG(flags) NO_TMPFILE(flags); mode_t mode = 0; \
    if ((flags) & (O_CREAT | O_TMPFILE)) { va_list ap; va_start(ap, flags); mode = va_arg(ap, mode_t); va_end(ap); }

int open(const char *p, int flags, ...) { MODE_ARG(flags); char b[PATH_MAX]; REAL(open); return real_open(map(p, b), flags, mode); }
int open64(const char *p, int flags, ...) { MODE_ARG(flags); char b[PATH_MAX]; REAL(open64); return real_open64(map(p, b), flags, mode); }
int openat(int d, const char *p, int flags, ...) { MODE_ARG(flags); char b[PATH_MAX]; REAL(openat); return real_openat(d, map(p, b), flags, mode); }
int openat64(int d, const char *p, int flags, ...) { MODE_ARG(flags); char b[PATH_MAX]; REAL(openat64); return real_openat64(d, map(p, b), flags, mode); }
int __open_2(const char *p, int flags) { NO_TMPFILE(flags); char b[PATH_MAX]; REAL(open); return real_open(map(p, b), flags); }
int __open64_2(const char *p, int flags) { NO_TMPFILE(flags); char b[PATH_MAX]; REAL(open64); return real_open64(map(p, b), flags); }
int __openat_2(int d, const char *p, int flags) { NO_TMPFILE(flags); char b[PATH_MAX]; REAL(openat); return real_openat(d, map(p, b), flags); }
int __openat64_2(int d, const char *p, int flags) { NO_TMPFILE(flags); char b[PATH_MAX]; REAL(openat64); return real_openat64(d, map(p, b), flags); }
FILE *fopen(const char *p, const char *m) { char b[PATH_MAX]; REAL(fopen); return real_fopen(map(p, b), m); }
FILE *fopen64(const char *p, const char *m) { char b[PATH_MAX]; REAL(fopen64); return real_fopen64(map(p, b), m); }
FILE *freopen(const char *p, const char *m, FILE *f) { char b[PATH_MAX]; REAL(freopen); return real_freopen(map(p, b), m, f); }
FILE *freopen64(const char *p, const char *m, FILE *f) { char b[PATH_MAX]; REAL(freopen64); return real_freopen64(map(p, b), m, f); }

int stat(const char *p, struct stat *s) { char b[PATH_MAX]; REAL(stat); return real_stat(map(p, b), s); }
int stat64(const char *p, struct stat64 *s) { char b[PATH_MAX]; REAL(stat64); return real_stat64(map(p, b), s); }
int lstat(const char *p, struct stat *s) { char b[PATH_MAX]; REAL(lstat); return real_lstat(map(p, b), s); }
int lstat64(const char *p, struct stat64 *s) { char b[PATH_MAX]; REAL(lstat64); return real_lstat64(map(p, b), s); }
int fstatat(int d, const char *p, struct stat *s, int f) { char b[PATH_MAX]; REAL(fstatat); return real_fstatat(d, map(p, b), s, f); }
int fstatat64(int d, const char *p, struct stat64 *s, int f) { char b[PATH_MAX]; REAL(fstatat64); return real_fstatat64(d, map(p, b), s, f); }
int statx(int d, const char *p, int f, unsigned m, struct statx *s) { char b[PATH_MAX]; REAL(statx); return real_statx(d, map(p, b), f, m, s); }
int statfs(const char *p, struct statfs *s) { char b[PATH_MAX]; REAL(statfs); return real_statfs(map(p, b), s); }
int access(const char *p, int m) { char b[PATH_MAX]; REAL(access); return real_access(map(p, b), m); }
int faccessat(int d, const char *p, int m, int f) { char b[PATH_MAX]; REAL(faccessat); return real_faccessat(d, map(p, b), m, f); }
int euidaccess(const char *p, int m) { char b[PATH_MAX]; REAL(euidaccess); return real_euidaccess(map(p, b), m); }
int eaccess(const char *p, int m) { char b[PATH_MAX]; REAL(eaccess); return real_eaccess(map(p, b), m); }
DIR *opendir(const char *p) { char b[PATH_MAX]; REAL(opendir); return real_opendir(map(p, b)); }
ssize_t readlink(const char *p, char *o, size_t n) { ssize_t r = self_link(p, o, n); if (r != -2) return r; char b[PATH_MAX]; REAL(readlink); return real_readlink(map(p, b), o, n); }
/* Hard links: SELinux refuses them in app data with EACCES. Linux's own
 * refusal (protected_hardlinks, other file systems) is EPERM, which OSTree
 * and others take as "copy instead"; give them that.  */
int linkat(int od, const char *o, int nd, const char *n, int fl)
{
    char b1[PATH_MAX], b2[PATH_MAX]; REAL(linkat);
    int r = real_linkat(od, map(o, b1), nd, map(n, b2), fl);
    if (r < 0 && errno == EACCES) errno = EPERM;
    return r;
}
int link(const char *o, const char *n) { return linkat(AT_FDCWD, o, AT_FDCWD, n, 0); }
ssize_t readlinkat(int d, const char *p, char *o, size_t n) { ssize_t r = self_link(p, o, n); if (r != -2) return r; char b[PATH_MAX]; REAL(readlinkat); return real_readlinkat(d, map(p, b), o, n); }
char *realpath(const char *p, char *o) { char b[PATH_MAX]; REAL(realpath); return real_realpath(map(p, b), o); }
char *canonicalize_file_name(const char *p) { char b[PATH_MAX]; REAL(canonicalize_file_name); return real_canonicalize_file_name(map(p, b)); }
/* The fortified versions (_FORTIFY_SOURCE) Qt and fontconfig call. */
char *__realpath_chk(const char *p, char *o, size_t n) { char b[PATH_MAX]; REAL(__realpath_chk); return real___realpath_chk(map(p, b), o, n); }
ssize_t __readlink_chk(const char *p, char *o, size_t n, size_t on) { ssize_t r = self_link(p, o, n); if (r != -2) return r; char b[PATH_MAX]; REAL(__readlink_chk); return real___readlink_chk(map(p, b), o, n, on); }
ssize_t __readlinkat_chk(int d, const char *p, char *o, size_t n, size_t on) { ssize_t r = self_link(p, o, n); if (r != -2) return r; char b[PATH_MAX]; REAL(__readlinkat_chk); return real___readlinkat_chk(d, map(p, b), o, n, on); }
int statfs64(const char *p, struct statfs64 *s) { char b[PATH_MAX]; REAL(statfs64); return real_statfs64(map(p, b), s); }
int statvfs(const char *p, struct statvfs *s) { char b[PATH_MAX]; REAL(statvfs); return real_statvfs(map(p, b), s); }
int statvfs64(const char *p, struct statvfs64 *s) { char b[PATH_MAX]; REAL(statvfs64); return real_statvfs64(map(p, b), s); }
int scandir64(const char *p, struct dirent64 ***l, int (*sel)(const struct dirent64 *),
              int (*cmp)(const struct dirent64 **, const struct dirent64 **)) {
    char b[PATH_MAX]; REAL(scandir64); return real_scandir64(map(p, b), l, sel, cmp);
}
/* glibc's stat functions before 2.33, which programs built against an older
 * glibc still call (Electron, with its own fontconfig inside). glibc keeps
 * them for those programs only, so they go to today's ones, whose struct
 * stat is the same on 64-bit systems. */
int __xstat(int v, const char *p, struct stat *s) { (void)v; return stat(p, s); }
int __xstat64(int v, const char *p, struct stat64 *s) { (void)v; return stat64(p, s); }
int __lxstat(int v, const char *p, struct stat *s) { (void)v; return lstat(p, s); }
int __lxstat64(int v, const char *p, struct stat64 *s) { (void)v; return lstat64(p, s); }
int __fxstatat(int v, int d, const char *p, struct stat *s, int f) { (void)v; return fstatat(d, p, s, f); }
int __fxstatat64(int v, int d, const char *p, struct stat64 *s, int f) { (void)v; return fstatat64(d, p, s, f); }
int chdir(const char *p) { char b[PATH_MAX]; REAL(chdir); return real_chdir(map(p, b)); }
void *dlopen(const char *p, int f) { char b[PATH_MAX]; REAL(dlopen); return real_dlopen(map(p, b), f); }
int scandir(const char *p, struct dirent ***l, int (*sel)(const struct dirent *),
            int (*cmp)(const struct dirent **, const struct dirent **)) {
    char b[PATH_MAX]; REAL(scandir); return real_scandir(map(p, b), l, sel, cmp);
}

/* ---- starting programs ---- */

/*
 * Works out how to start path (as the app names it) with argv:
 *  - zypak-wrapper(.sh) <program> <args>: Flathub's Electron apps start
 *    through zypak, which asks Flatpak's portal to start Chromium's sandboxed
 *    helpers. There is no portal or sandbox here, so the program starts
 *    directly with --no-sandbox (Chromium's own sandbox needs namespaces or a
 *    setuid helper, which Android doesn't allow either).
 *  - a #! script: its interpreter, mapped (/bin/sh is the runtime's sh).
 *  - an ELF program: the runtime's loader.
 * Returns the file to exec and a new argv in *out (to free), or NULL with
 * errno set.
 */
static const char *resolve(const char *path, char *const argv[], char ***out, char *buf) {
    int argc = 0;
    while (argv && argv[argc]) argc++;
    char **a = calloc(argc + 12, sizeof(char *));
    if (!a) return NULL;
    for (int i = 0; i < argc; i++) a[i] = argv[i];
    if (!argc) a[argc++] = (char *)path;
    char hdr[256];
    REAL(open);
    char self[PATH_MAX];
    for (int depth = 0; depth < 4; depth++) {
        /* Chromium starts its helpers by exec'ing /proc/self/exe: the program
         * (readlink goes through ddmask's, or this file's, answer). */
        if (!strcmp(path, "/proc/self/exe") || !strcmp(path, "/proc/thread-self/exe")) {
            ssize_t n = readlink(path, self, sizeof self - 1);
            if (n > 0) { self[n] = 0; path = self; }
        }
        const char *m = map(path, buf);
        const char *base = strrchr(path, '/') ? strrchr(path, '/') + 1 : path;
        if ((!strcmp(base, "zypak-wrapper") || !strcmp(base, "zypak-wrapper.sh")) && argc > 1) {
            /* [wrapper, program, args...] -> [program, --no-sandbox, args...];
             * on a Wayland desktop (DeskDroid's has no X server) also
             * Chromium's Wayland backend. */
            path = a[1];
            a[0] = a[1];
            a[1] = "--no-sandbox";
            const char *wl = getenv("WAYLAND_DISPLAY");
            if (wl && *wl) {
                memmove(a + 3, a + 2, (argc - 1) * sizeof(char *));
                a[2] = "--ozone-platform-hint=auto";
                argc++;
            }
            if (debug) fprintf(stderr, "ddflatpak: zypak -> %s --no-sandbox\n", path);
            continue;
        }
        int fd = real_open(m, O_RDONLY | O_CLOEXEC);
        if (fd < 0) { free(a); return NULL; }
        ssize_t n = read(fd, hdr, sizeof hdr - 1);
        close(fd);
        if (n < 0) n = 0;
        hdr[n] = 0;
        if (n >= 4 && !memcmp(hdr, "\177ELF", 4) && env_loader) {
            /* [loader, --library-path, P, --argv0, argv0, m, args...] */
            int extra = env_libpath ? 5 : 3;
            memmove(a + extra + 1, a + 1, argc * sizeof(char *));
            char *argv0 = a[0];
            int i = 0;
            a[i++] = (char *)env_loader;
            if (env_libpath) { a[i++] = "--library-path"; a[i++] = (char *)env_libpath; }
            a[i++] = "--argv0"; a[i++] = argv0;
            a[i++] = strdup(m);
            *out = a;
            return env_loader;
        }
        if (n > 2 && hdr[0] == '#' && hdr[1] == '!') {
            /* "#!interp [arg]" -> [interp, (arg), path, args after argv0...] */
            char *s = hdr + 2, *e;
            s[strcspn(s, "\n")] = 0;
            while (*s == ' ' || *s == '\t') s++;
            e = s + strcspn(s, " \t");
            char *arg = NULL;
            if (*e) { *e++ = 0; while (*e == ' ' || *e == '\t') e++; if (*e) arg = e; }
            char *interp = strdup(s), *iarg = arg ? strdup(arg) : NULL;
            int add = iarg ? 2 : 1;
            memmove(a + add + 1, a + 1, argc * sizeof(char *));
            a[0] = interp;
            if (iarg) a[1] = iarg;
            a[add] = (char *)path;
            argc += add;
            path = interp;
            continue;
        }
        *out = a;
        return m; /* anything else: as the system would */
    }
    free(a);
    errno = ELOOP;
    return NULL;
}

int execve(const char *p, char *const argv[], char *const envp[]) {
    char b[PATH_MAX]; char **a; REAL(execve);
    const char *f = resolve(p, argv, &a, b);
    if (!f) return -1;
    real_execve(f, a, envp);
    int e = errno; free(a); errno = e;
    return -1;
}

int execv(const char *p, char *const argv[]) { extern char **environ; return execve(p, argv, environ); }
/* PATH search with mapped directories (/app/bin, /usr/bin). */
static int find_in_path(const char *file, char *out) {
    if (strchr(file, '/')) { snprintf(out, PATH_MAX, "%s", file); return 1; }
    const char *path = getenv("PATH");
    if (!path) path = "/usr/bin:/bin";
    char dir[PATH_MAX], cand[PATH_MAX], b[PATH_MAX];
    REAL(access);
    while (*path) {
        size_t n = strcspn(path, ":");
        snprintf(dir, sizeof dir, "%.*s", (int)n, path);
        snprintf(cand, sizeof cand, "%.2000s/%.2000s", n ? dir : ".", file);
        if (real_access(map(cand, b), X_OK) == 0) { snprintf(out, PATH_MAX, "%s", cand); return 1; }
        path += n + (path[n] == ':');
    }
    return 0;
}

int execvpe(const char *f, char *const argv[], char *const envp[]) {
    char p[PATH_MAX];
    if (!find_in_path(f, p)) { errno = ENOENT; return -1; }
    return execve(p, argv, envp);
}
int execvp(const char *f, char *const argv[]) { extern char **environ; return execvpe(f, argv, environ); }

static int spawn(pid_t *pid, const char *p, const posix_spawn_file_actions_t *fa,
                 const posix_spawnattr_t *at, char *const argv[], char *const envp[]) {
    char b[PATH_MAX]; char **a; REAL(posix_spawn);
    const char *f = resolve(p, argv, &a, b);
    if (!f) return errno;
    int r = real_posix_spawn(pid, f, fa, at, a, envp);
    free(a);
    return r;
}
int posix_spawn(pid_t *pid, const char *p, const posix_spawn_file_actions_t *fa,
                const posix_spawnattr_t *at, char *const argv[], char *const envp[]) {
    return spawn(pid, p, fa, at, argv, envp);
}
int posix_spawnp(pid_t *pid, const char *f, const posix_spawn_file_actions_t *fa,
                 const posix_spawnattr_t *at, char *const argv[], char *const envp[]) {
    char p[PATH_MAX];
    if (!find_in_path(f, p)) return ENOENT;
    return spawn(pid, p, fa, at, argv, envp);
}

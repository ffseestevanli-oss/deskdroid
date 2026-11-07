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
#include <spawn.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/statfs.h>
#include <sys/types.h>
#include <unistd.h>

static const char *env_app, *env_rt, *env_tmp, *env_loader, *env_libpath;
static int debug;

__attribute__((constructor)) static void ddflatpak_init(void) {
    env_app = getenv("DDFLATPAK_APP");
    env_rt = getenv("DDFLATPAK_RUNTIME");
    env_tmp = getenv("DDFLATPAK_TMP");
    env_loader = getenv("DDFLATPAK_LOADER");
    env_libpath = getenv("DDFLATPAK_LIBPATH");
    debug = getenv("DDFLATPAK_DEBUG") != NULL;
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

#define MODE_ARG(flags) mode_t mode = 0; \
    if ((flags) & (O_CREAT | O_TMPFILE)) { va_list ap; va_start(ap, flags); mode = va_arg(ap, mode_t); va_end(ap); }

int open(const char *p, int flags, ...) { MODE_ARG(flags); char b[PATH_MAX]; REAL(open); return real_open(map(p, b), flags, mode); }
int open64(const char *p, int flags, ...) { MODE_ARG(flags); char b[PATH_MAX]; REAL(open64); return real_open64(map(p, b), flags, mode); }
int openat(int d, const char *p, int flags, ...) { MODE_ARG(flags); char b[PATH_MAX]; REAL(openat); return real_openat(d, map(p, b), flags, mode); }
int openat64(int d, const char *p, int flags, ...) { MODE_ARG(flags); char b[PATH_MAX]; REAL(openat64); return real_openat64(d, map(p, b), flags, mode); }
int __open_2(const char *p, int flags) { char b[PATH_MAX]; REAL(open); return real_open(map(p, b), flags); }
int __open64_2(const char *p, int flags) { char b[PATH_MAX]; REAL(open64); return real_open64(map(p, b), flags); }
int __openat_2(int d, const char *p, int flags) { char b[PATH_MAX]; REAL(openat); return real_openat(d, map(p, b), flags); }
int __openat64_2(int d, const char *p, int flags) { char b[PATH_MAX]; REAL(openat64); return real_openat64(d, map(p, b), flags); }
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
ssize_t readlink(const char *p, char *o, size_t n) { char b[PATH_MAX]; REAL(readlink); return real_readlink(map(p, b), o, n); }
ssize_t readlinkat(int d, const char *p, char *o, size_t n) { char b[PATH_MAX]; REAL(readlinkat); return real_readlinkat(d, map(p, b), o, n); }
char *realpath(const char *p, char *o) { char b[PATH_MAX]; REAL(realpath); return real_realpath(map(p, b), o); }
char *canonicalize_file_name(const char *p) { char b[PATH_MAX]; REAL(canonicalize_file_name); return real_canonicalize_file_name(map(p, b)); }
/* The fortified versions (_FORTIFY_SOURCE) Qt and fontconfig call. */
char *__realpath_chk(const char *p, char *o, size_t n) { char b[PATH_MAX]; REAL(__realpath_chk); return real___realpath_chk(map(p, b), o, n); }
ssize_t __readlink_chk(const char *p, char *o, size_t n, size_t on) { char b[PATH_MAX]; REAL(__readlink_chk); return real___readlink_chk(map(p, b), o, n, on); }
ssize_t __readlinkat_chk(int d, const char *p, char *o, size_t n, size_t on) { char b[PATH_MAX]; REAL(__readlinkat_chk); return real___readlinkat_chk(d, map(p, b), o, n, on); }
int statfs64(const char *p, struct statfs64 *s) { char b[PATH_MAX]; REAL(statfs64); return real_statfs64(map(p, b), s); }
int chdir(const char *p) { char b[PATH_MAX]; REAL(chdir); return real_chdir(map(p, b)); }
void *dlopen(const char *p, int f) { char b[PATH_MAX]; REAL(dlopen); return real_dlopen(map(p, b), f); }
int scandir(const char *p, struct dirent ***l, int (*sel)(const struct dirent *),
            int (*cmp)(const struct dirent **, const struct dirent **)) {
    char b[PATH_MAX]; REAL(scandir); return real_scandir(map(p, b), l, sel, cmp);
}

/* ---- starting programs ---- */

/* An ELF program with an interpreter starts through the runtime's loader. */
static int needs_loader(const char *path) {
    int fd; unsigned char h[4];
    REAL(open);
    if (!env_loader || (fd = real_open(path, O_RDONLY | O_CLOEXEC)) < 0) return 0;
    ssize_t n = read(fd, h, 4);
    close(fd);
    return n == 4 && memcmp(h, "\177ELF", 4) == 0;
}

/* Builds the argv to run path (already mapped) as argv0. */
static char **loader_argv(const char *path, char *const argv[]) {
    int argc = 0;
    while (argv && argv[argc]) argc++;
    char **a = calloc(argc + 8, sizeof(char *));
    int i = 0;
    a[i++] = (char *)env_loader;
    if (env_libpath) { a[i++] = "--library-path"; a[i++] = (char *)env_libpath; }
    a[i++] = "--argv0"; a[i++] = argc ? argv[0] : (char *)path;
    a[i++] = (char *)path;
    for (int j = 1; j < argc; j++) a[i++] = argv[j];
    a[i] = NULL;
    return a;
}

int execve(const char *p, char *const argv[], char *const envp[]) {
    char b[PATH_MAX]; REAL(execve);
    const char *m = map(p, b);
    if (needs_loader(m)) {
        char **a = loader_argv(m, argv);
        real_execve(env_loader, a, envp);
        int e = errno; free(a); errno = e;
        return -1;
    }
    return real_execve(m, argv, envp);
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
    char b[PATH_MAX]; REAL(posix_spawn);
    const char *m = map(p, b);
    if (needs_loader(m)) {
        char **a = loader_argv(m, argv);
        int r = real_posix_spawn(pid, env_loader, fa, at, a, envp);
        free(a);
        return r;
    }
    return real_posix_spawn(pid, m, fa, at, argv, envp);
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

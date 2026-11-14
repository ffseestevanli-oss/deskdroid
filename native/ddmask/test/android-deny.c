/* Android's refusals for compat.sh, preloaded after ddmask: SELinux refuses
 * reopening a memfd through /proc (EACCES; here, any file) and hard links
 * (EACCES, once the new name is known to be free), there's no /dev/shm, and
 * seccomp blocks System V IPC (glibc's loader makes those ENOSYS). */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <stdarg.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static int refused(const char *p) {
    if (!strncmp(p, "/dev/shm", 8)) { errno = ENOENT; return 1; }
    if (!strncmp(p, "/proc/", 6) && strstr(p, "/fd/")) { errno = EACCES; return 1; }
    return 0;
}
#define MODE mode_t m = 0; if (f & O_CREAT) { va_list a; va_start(a, f); m = va_arg(a, int); va_end(a); }
int open(const char *p, int f, ...) { MODE; if (refused(p)) return -1; return ((int (*)(const char *, int, ...))dlsym(RTLD_NEXT, "open"))(p, f, m); }
int open64(const char *p, int f, ...) { MODE; if (refused(p)) return -1; return ((int (*)(const char *, int, ...))dlsym(RTLD_NEXT, "open64"))(p, f, m); }
int unlink(const char *p) { if (refused(p)) return -1; return ((int (*)(const char *))dlsym(RTLD_NEXT, "unlink"))(p); }
int stat(const char *p, struct stat *s) { if (refused(p)) return -1; return ((int (*)(const char *, struct stat *))dlsym(RTLD_NEXT, "stat"))(p, s); }
int linkat(int od, const char *o, int nd, const char *n, int fl) {
    struct stat st;
    if (fstatat(nd, n, &st, AT_SYMLINK_NOFOLLOW) == 0) { errno = EEXIST; return -1; }
    if (fstatat(od, o, &st, AT_SYMLINK_NOFOLLOW) != 0) return -1;
    (void)fl; errno = EACCES; return -1;
}
int link(const char *o, const char *n) { return linkat(AT_FDCWD, o, AT_FDCWD, n, 0); }
#include <sys/types.h>
int shmget(key_t k, size_t s, int f) { (void)k; (void)s; (void)f; errno = ENOSYS; return -1; }
int shmctl(int i, int c, void *b) { (void)i; (void)c; (void)b; errno = ENOSYS; return -1; }
int semget(key_t k, int n, int f) { (void)k; (void)n; (void)f; errno = ENOSYS; return -1; }

/* Android's refusals for compat.sh, preloaded after ddmask: SELinux refuses
 * reopening a memfd through /proc (EACCES; here, any file), and there's no
 * /dev/shm. */
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

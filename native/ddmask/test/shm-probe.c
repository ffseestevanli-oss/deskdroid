/* Shares memory the way Firefox does (ipc/glue/SharedMemoryPlatform_posix.cpp),
 * for compat.sh: a memfd and its read-only copy opened through
 * /proc/self/fd, then POSIX shared memory (shm_open). */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/syscall.h>
#include <unistd.h>
#ifndef F_SEAL_FUTURE_WRITE
#define F_SEAL_FUTURE_WRITE 0x0010
#endif

static void share(const char *what, int rw, int ro) {
    if (ftruncate(rw, 4096) != 0) { printf("%s-truncate=%s\n", what, strerror(errno)); return; }
    char *w = mmap(0, 4096, PROT_READ | PROT_WRITE, MAP_SHARED, rw, 0);
    char *r = mmap(0, 4096, PROT_READ, MAP_SHARED, ro, 0);
    if (w == MAP_FAILED || r == MAP_FAILED) { printf("%s-map=%s\n", what, strerror(errno)); return; }
    strcpy(w, "shared");
    printf("%s-shared=%s\n", what, r);
}

int main(void) {
    int fd = (int)syscall(SYS_memfd_create, "mozilla-ipc", MFD_CLOEXEC | MFD_ALLOW_SEALING);
    if (fd < 0) { printf("memfd=%s\n", strerror(errno)); return 1; }
    char p[64];
    snprintf(p, sizeof p, "/proc/self/fd/%d", fd);
    int ro = open(p, O_RDONLY | O_CLOEXEC);
    printf("memfd-reopen=%s\n", ro >= 0 ? "ok" : strerror(errno));
    if (ro >= 0) {
        share("memfd", fd, ro);
        printf("memfd-cloexec=%s\n", (fcntl(ro, F_GETFD) & FD_CLOEXEC) ? "yes" : "no");
        int sealed = fcntl(fd, F_ADD_SEALS, F_SEAL_GROW | F_SEAL_SHRINK | F_SEAL_SEAL | F_SEAL_FUTURE_WRITE) == 0;
        void *m = mmap(0, 4096, PROT_READ | PROT_WRITE, MAP_SHARED, ro, 0);
        printf("memfd-sealed=%s copy-writable=%s\n", sealed ? "yes" : strerror(errno), m == MAP_FAILED ? "no" : "yes");
    }
    /* Not a memfd: as Android says. */
    int dev = open("/dev/null", O_RDONLY);
    snprintf(p, sizeof p, "/proc/self/fd/%d", dev);
    printf("other-reopen=%s\n", open(p, O_RDONLY) >= 0 ? "ok" : strerror(errno));

    char name[64];
    snprintf(name, sizeof name, "/org.mozilla.ipc.%d.0", (int)getpid());
    int s = shm_open(name, O_RDWR | O_CREAT | O_EXCL, 0600);
    if (s < 0) { printf("shm_open=%s\n", strerror(errno)); return 0; }
    int sro = shm_open(name, O_RDONLY, 0400);
    printf("shm-again=%s\n", sro >= 0 ? "ok" : strerror(errno));
    printf("shm-excl=%s\n", shm_open(name, O_RDWR | O_CREAT | O_EXCL, 0600) >= 0 ? "opened" : strerror(errno));
    printf("shm_unlink=%s\n", shm_unlink(name) == 0 ? "ok" : strerror(errno));
    if (sro >= 0) share("shm", s, sro);
    printf("shm-gone=%s\n", shm_open(name, O_RDONLY, 0) < 0 ? strerror(errno) : "no");
    return 0;
}

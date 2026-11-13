/* ddmask's blocked-system-call test (compat.sh): traps some system calls the
 * way Android's seccomp filter does (SIGSYS), then makes them. */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <linux/filter.h>
#include <linux/seccomp.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>
#include <sys/epoll.h>
#include <sys/prctl.h>
#include <sys/socket.h>
#include <sys/syscall.h>
#include <sys/un.h>
#include <time.h>
#include <unistd.h>

#ifndef SYS_faccessat2
#define SYS_faccessat2 439
#endif
#ifndef SYS_close_range
#define SYS_close_range 436
#endif
#ifndef SYS_epoll_pwait2
#define SYS_epoll_pwait2 441
#endif

#define TRAP(nr) BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, (nr), 0, 1), BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_TRAP)

int main(void) {
    struct sock_filter f[] = {
        BPF_STMT(BPF_LD | BPF_W | BPF_ABS, offsetof(struct seccomp_data, nr)),
        TRAP(SYS_faccessat2),
        TRAP(SYS_epoll_pwait2),
        TRAP(SYS_accept),
        TRAP(SYS_getcpu),
        TRAP(SYS_close_range),
        TRAP(SYS_setresgid),
        BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ALLOW),
    };
    struct sock_fprog prog = { sizeof f / sizeof f[0], f };
    if (prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) || prctl(PR_SET_SECCOMP, SECCOMP_MODE_FILTER, &prog)) {
        perror("seccomp");
        return 1;
    }
    long r = syscall(SYS_faccessat2, AT_FDCWD, "/", F_OK, 0);
    printf("faccessat2=%ld/%s\n", r, r ? strerror(errno) : "ok");
    int ep = epoll_create1(0);
    struct epoll_event ev[1];
    struct timespec ts = { 0, 1000000 };
    r = syscall(SYS_epoll_pwait2, ep, ev, 1, &ts, NULL, 8);
    printf("epoll_pwait2=%ld/%s\n", r, r < 0 ? strerror(errno) : "ok");
    int s = socket(AF_UNIX, SOCK_STREAM | SOCK_NONBLOCK, 0);
    struct sockaddr_un a = { .sun_family = AF_UNIX };
    snprintf(a.sun_path + 1, sizeof a.sun_path - 1, "ddmask-test-%d", (int)getpid()); /* abstract */
    bind(s, (struct sockaddr *)&a, sizeof a);
    listen(s, 1);
    r = syscall(SYS_accept, s, NULL, NULL);
    printf("accept=%ld/%s\n", r, r < 0 ? strerror(errno) : "ok");
    int d = dup(1), d2 = dup(1);
    r = syscall(SYS_close_range, d < d2 ? d : d2, d < d2 ? d2 : d, 0);
    printf("close_range=%ld/%s closed=%s\n", r, r < 0 ? strerror(errno) : "ok",
           fcntl(d, F_GETFD) == -1 && fcntl(d2, F_GETFD) == -1 ? "both" : "not both");
    gid_t g = getgid();
    r = syscall(SYS_setresgid, g, g, g);
    printf("setresgid-same=%ld/%s\n", r, r < 0 ? strerror(errno) : "ok");
    r = syscall(SYS_setresgid, -1, g + 1, -1);
    printf("setresgid-other=%ld/%s\n", r, r < 0 ? strerror(errno) : "ok");
    unsigned cpu;
    r = syscall(SYS_getcpu, &cpu, NULL, NULL);
    printf("getcpu=%ld/%s\n", r, r < 0 ? strerror(errno) : "ok");
    return 0;
}

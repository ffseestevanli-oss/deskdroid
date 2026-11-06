/* Test program for DeskDroid's glibc and musl (native/glibc/test/run.sh,
 * native/musl/test/run.sh): prints what the patched C library and ddmask give it. */
#define _GNU_SOURCE
#include <errno.h>
#include <pwd.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>
int main(int argc, char **argv) {
    char exe[4096] = ""; ssize_t n = readlink("/proc/self/exe", exe, sizeof exe - 1); if (n > 0) exe[n] = 0;
    struct passwd *pw = getpwuid(getuid());
    int r = kill(getpid(), SIGSYS); int e = errno;
    printf("argv0=%s exe=%s user=%s sigsys=%d/%s preload=%s\n", argv[0], exe, pw ? pw->pw_name : "(none)", r, r ? strerror(e) : "ok", getenv("DDMASK_GLIBC_LD_PRELOAD") || getenv("DDMASK_MUSL_LD_PRELOAD") ? "set" : "unset");
    return 0;
}

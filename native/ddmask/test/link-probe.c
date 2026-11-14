/* What compat.sh checks of hard links: an X server's lock file (link the
 * temporary file to the lock; EEXIST while one is there), in folder $1. */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static const char *res(int r) { return r == 0 ? "ok" : strerror(errno); }

int main(int argc, char **argv) {
    if (argc < 2 || chdir(argv[1]) != 0) return 2;
    int fd = open(".tX8-lock", O_CREAT | O_EXCL | O_WRONLY, 0444);
    if (fd < 0 || write(fd, "      4242\n", 11) != 11) return 2;
    close(fd);
    printf("lock=%s\n", res(link(".tX8-lock", ".X8-lock")));
    printf("lock-again=%s\n", res(link(".tX8-lock", ".X8-lock")));
    unlink(".tX8-lock");
    char b[32] = {0};
    fd = open(".X8-lock", O_RDONLY);
    printf("lock-text=%s", fd >= 0 && read(fd, b, sizeof b - 1) > 0 ? b : "none\n");
    struct stat st;
    printf("lock-mode=%o\n", stat(".X8-lock", &st) == 0 ? (unsigned)(st.st_mode & 0777) : 0);
    mkdir("dir", 0755);
    printf("link-dir=%s\n", res(link("dir", "dir2")));
    printf("link-missing=%s\n", res(linkat(AT_FDCWD, "nothing", AT_FDCWD, "n2", 0)));
    return 0;
}

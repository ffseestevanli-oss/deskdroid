/* ddmask's test program: prints how it was started, then optionally starts
 * another program the ways the desktop's apps do. */
#define _GNU_SOURCE
#include <fcntl.h>
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

extern char **environ;

int main(int argc, char **argv) {
    char exe[4096] = "", comm[64] = "", cmd[4096] = "";
    ssize_t n = readlink("/proc/self/exe", exe, sizeof exe - 1);
    if (n > 0) exe[n] = 0;
    int fd = open("/proc/self/comm", O_RDONLY);
    if (fd >= 0) { n = read(fd, comm, sizeof comm - 1); if (n > 0) comm[n - 1] = 0; close(fd); }
    fd = open("/proc/self/cmdline", O_RDONLY);
    if (fd >= 0) { n = read(fd, cmd, sizeof cmd - 1); if (n > 0) cmd[n] = 0; close(fd); }
    printf("argv0=%s exe=%s comm=%s cmd0=%s", argv[0], exe, comm, cmd);
    for (int i = 1; i < argc; i++) printf(" arg=%s", argv[i]);
    printf("\n");
    fflush(stdout);
    if (argc >= 3 && strcmp(argv[1], "execvp") == 0) {
        char *a[] = { argv[2], (char *)"child", NULL };
        execvp(argv[2], a);
        perror("execvp");
        return 1;
    }
    if (argc >= 4 && strcmp(argv[1], "execle") == 0) {
        /* A cleaned environment: only argv[3] (no LD_PRELOAD). */
        char *env[] = { argv[3], NULL };
        execle(argv[2], "child", (char *)NULL, env);
        perror("execle");
        return 1;
    }
    if (argc >= 3 && strcmp(argv[1], "spawnp") == 0) {
        char *a[] = { argv[2], (char *)"spawned", NULL };
        pid_t pid;
        int r = posix_spawnp(&pid, argv[2], NULL, NULL, a, environ);
        if (r) { fprintf(stderr, "posix_spawnp: %s\n", strerror(r)); return 1; }
        int st;
        waitpid(pid, &st, 0);
        return WIFEXITED(st) ? WEXITSTATUS(st) : 1;
    }
    if (argc >= 3 && strcmp(argv[1], "execv") == 0) {
        char *a[] = { argv[2], NULL };
        execv(argv[2], a);
        perror("execv");
        return 1;
    }
    return 0;
}

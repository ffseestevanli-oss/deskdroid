/* For flatpak.sh: reads the files named on the command line in several ways
 * and prints what it found; "exec:<path>" starts <path> as "child" with the arguments after it. */
#define _GNU_SOURCE
#include <dirent.h>
#include <fcntl.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

int main(int argc, char **argv) {
    char exe[PATH_MAX] = "";
    ssize_t n = readlink("/proc/self/exe", exe, sizeof exe - 1);
    if (n > 0) exe[n] = 0;
    printf("argv0=%s exe=%s\n", argv[0], exe);
    for (int i = 1; i < argc; i++) {
        const char *a = argv[i];
        if (!strncmp(a, "exec:", 5)) {
            fflush(stdout);
            argv[i] = "child"; /* the child reads the arguments after this one */
            execv(a + 5, argv + i);
            printf("exec %s failed\n", a + 5);
            return 1;
        }
        if (!strcmp(a, "child")) continue;
        char line[256] = "";
        FILE *f = fopen(a, "r");
        if (f) { if (fgets(line, sizeof line, f)) line[strcspn(line, "\n")] = 0; fclose(f); }
        struct stat st;
        int fd = open(a, O_RDONLY);
        if (fd >= 0) close(fd);
        char *dir = strdup(a); *strrchr(dir, '/') = 0;
        DIR *d = opendir(dir);
        if (d) closedir(d);
        char real[PATH_MAX];
        printf("%s fopen=%s open=%s stat=%s opendir=%s realpath=%s\n", a, f ? line : "no",
               fd >= 0 ? "yes" : "no", stat(a, &st) == 0 ? "yes" : "no", d ? "yes" : "no",
               realpath(a, real) ? "yes" : "no");
        free(dir);
    }
    return 0;
}

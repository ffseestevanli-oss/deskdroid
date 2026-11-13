/* For flatpak.sh: reads the files named on the command line in several ways
 * and prints what it found; "exec:<path>" starts <path> as "child" with the arguments after it. */
#define _GNU_SOURCE
#include <dirent.h>
#include <dlfcn.h>
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
        if (!strcmp(a, "clobber-env")) { /* Chromium's process title: variables moved, their old memory overwritten */
            extern char **environ;
            int n = 0;
            while (environ[n]) n++;
            char **moved = calloc(n + 1, sizeof *moved);
            for (int k = 0; k < n; k++) moved[k] = strdup(environ[k]);
            char **old = environ;
            environ = moved;
            for (int k = 0; k < n; k++) memset(old[k], 'x', strlen(old[k]));
            continue;
        }
        if (!strncmp(a, "temp:", 5)) { /* temp:<template>: Chromium's shared memory, then removed */
            char t[PATH_MAX];
            snprintf(t, sizeof t, "%s", a + 5);
            int fd = mkostemp(t, O_CLOEXEC);
            struct stat st;
            int named = fd >= 0 && stat(t, &st) == 0 && strcmp(t, a + 5) && !strncmp(t, a + 5, strlen(a + 5) - 6);
            int gone = fd >= 0 && unlink(t) == 0 && stat(t, &st) != 0;
            printf("temp fd=%s named=%s removed=%s\n", fd >= 0 ? "yes" : "no", named ? "yes" : "no", gone ? "yes" : "no");
            continue;
        }
        if (a[0] != '/') { printf("%s fopen=no\n", a); continue; } /* a word, not a path */
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
        /* glibc's pre-2.33 stat, as old builds (Electron) call it; found
         * only when something (ddflatpak) defines it. */
        int (*xstat)(int, const char *, struct stat *) = dlsym(RTLD_DEFAULT, "__xstat64");
        int xs = xstat && xstat(1, a, &st) == 0;
        printf("%s fopen=%s open=%s stat=%s opendir=%s realpath=%s xstat=%s\n", a, f ? line : "no",
               fd >= 0 ? "yes" : "no", stat(a, &st) == 0 ? "yes" : "no", d ? "yes" : "no",
               realpath(a, real) ? "yes" : "no", xs ? "yes" : "no");
        free(dir);
    }
    return 0;
}

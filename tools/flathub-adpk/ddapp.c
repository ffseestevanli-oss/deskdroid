/*
 * ddapp: the main program of DeskDroid store packages made from Flathub
 * builds (.adpk files from tools/adpk-flathub.py).
 *
 * The store marks only ELF files executable, and store-program.sh starts the
 * package's main program through Android's linker when ddmask isn't
 * preloaded, so the main program has to be a small bionic program. It does
 * two things:
 *
 *   - normally, it hands over to the package's launcher script, $DDAPP_RUN
 *     (program.env sets it to program/run.sh), with /system/bin/sh;
 *   - with DDAPP_SETUP=<layout file> and DDAPP_ROOT=<folder>, it lays out
 *     what a zip unpacked by the store can't carry, once per package: the
 *     symbolic links (and files that were hard links), the execute bits of
 *     scripts, and empty folders. Lines of the layout file:
 *         L <path> <target>    symbolic link
 *         X <path>             make executable
 *         D <path>             folder
 *     with paths relative to DDAPP_ROOT, and %20 for a space, %25 for %.
 */
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static void unescape(char *s) {
    char *o = s;
    for (; *s; s++) {
        if (s[0] == '%' && s[1] && s[2]) {
            char h[3] = {s[1], s[2], 0};
            *o++ = (char)strtol(h, NULL, 16);
            s += 2;
        } else {
            *o++ = *s;
        }
    }
    *o = 0;
}

static void mkparents(char *path) {
    for (char *p = path + 1; *p; p++) {
        if (*p != '/') continue;
        *p = 0;
        mkdir(path, 0755);
        *p = '/';
    }
}

static int setup(const char *layout, const char *root) {
    FILE *f = fopen(layout, "r");
    if (!f) { fprintf(stderr, "ddapp: can't read %s: %s\n", layout, strerror(errno)); return 1; }
    static char line[16384], path[8192];
    int bad = 0;
    while (fgets(line, sizeof line, f)) {
        line[strcspn(line, "\n")] = 0;
        char *op = strtok(line, " "), *a = strtok(NULL, " "), *b = strtok(NULL, " ");
        if (!op || !a) continue;
        unescape(a);
        if (b) unescape(b);
        if (snprintf(path, sizeof path, "%s/%s", root, a) >= (int)sizeof path) continue;
        if (op[0] == 'L' && b) {
            mkparents(path);
            unlink(path);
            if (symlink(b, path) != 0) { bad++; if (bad < 5) fprintf(stderr, "ddapp: link %s: %s\n", path, strerror(errno)); }
        } else if (op[0] == 'X') {
            chmod(path, 0555);
        } else if (op[0] == 'D') {
            strcat(path, "/");
            mkparents(path);
        }
    }
    fclose(f);
    return bad ? 1 : 0;
}

int main(int argc, char **argv) {
    const char *layout = getenv("DDAPP_SETUP");
    if (layout && *layout) {
        const char *root = getenv("DDAPP_ROOT");
        if (!root || !*root) { fprintf(stderr, "ddapp: DDAPP_ROOT isn't set\n"); return 2; }
        return setup(layout, root);
    }
    const char *run = getenv("DDAPP_RUN");
    if (!run || !*run) {
        fprintf(stderr, "ddapp: DDAPP_RUN isn't set (start the app from its menu entry)\n");
        return 127;
    }
    char **args = calloc((size_t)argc + 2, sizeof(char *));
    if (!args) return 127;
    args[0] = "sh";
    args[1] = (char *)run;
    for (int i = 1; i < argc; i++) args[i + 1] = argv[i];
    execv("/system/bin/sh", args);
    fprintf(stderr, "ddapp: can't start /system/bin/sh: %s\n", strerror(errno));
    return 127;
}

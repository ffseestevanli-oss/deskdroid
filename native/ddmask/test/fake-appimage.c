/* A pretend AppImage for test/run.sh: run.sh writes AppImage's mark into its
 * ELF header. With --appimage-extract it writes squashfs-root/AppRun, as a
 * real one unpacks its files; started any other way it fails, as a real one
 * does without FUSE. */
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
int main(int argc, char **argv) {
    if (argc < 2 || strcmp(argv[1], "--appimage-extract") != 0) { fprintf(stderr, "fake AppImage: no FUSE\n"); return 1; }
    mkdir("squashfs-root", 0755);
    FILE *f = fopen("squashfs-root/AppRun", "w");
    if (!f) return 1;
    fprintf(f, "#!/bin/sh\necho \"apprun appimage=$APPIMAGE argv0=$ARGV0 appdir=$APPDIR args=$*\"\n");
    fclose(f);
    chmod("squashfs-root/AppRun", 0755);
    fprintf(stderr, "unpacked\n");
    return 0;
}

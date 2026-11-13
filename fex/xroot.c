/*
 * deskdroid-xroot.so: preloaded into Xwayland (an x86 program, run by FEX-Emu)
 * when Steam starts on DeskDroid's native desktop (steam-x86.sh). The app
 * ships it built, as app/src/main/assets/x86/deskdroid-xroot.so, from:
 *   gcc -shared -fPIC -nostdlib -O2 -s -Wl,--hash-style=both -Wl,-z,noexecstack \
 *     -o deskdroid-xroot.so fex/xroot.c          (on x86-64 Linux)
 *
 * Xwayland keeps a lock file in /tmp, and Android has no /tmp. Its -nolock
 * option turns that off, but only for root. This makes Xwayland see itself
 * as root: getuid() and geteuid() say 0, and the calls that would give up
 * root do nothing (an Android app can't change its user anyway, so they'd
 * only fail). Nothing else changes: the kernel still sees the app's user.
 * No libc: the library stands alone, so it loads with any glibc.
 */
typedef unsigned int id_t;
id_t getuid(void) { return 0; }
id_t geteuid(void) { return 0; }
int setuid(id_t u) { (void)u; return 0; }
int seteuid(id_t u) { (void)u; return 0; }
int setreuid(id_t r, id_t e) { (void)r; (void)e; return 0; }
int setresuid(id_t r, id_t e, id_t s) { (void)r; (void)e; (void)s; return 0; }

#!/usr/bin/env python3
"""DeskDroid's changes to musl, so musl programs (Alpine's, static-musl
builds made dynamic...) run on Android without proot. The same three changes
as glibc's (../glibc/patch.py):

patch.py <musl source dir> <prefix>

1. Paths: "/etc/...", "/var/...", "/tmp" move under <prefix>
   (/data/data/io.deskdroid.app/files/musl), the loader looks for libraries in
   <prefix>/lib and <prefix>/usr/lib, and the shell is /system/bin/sh.
2. Environment: the loader reads DDMASK_MUSL_LD_LIBRARY_PATH and
   DDMASK_MUSL_LD_PRELOAD instead of Android's LD_* variables.
3. Seccomp: a system call Android blocks fails with ENOSYS instead of killing
   the process (a SIGSYS handler, installed before the program starts).
"""
import pathlib
import re
import sys

src = pathlib.Path(sys.argv[1])
prefix = sys.argv[2].rstrip("/")


def edit(rel, old, new):
    p = src / rel
    s = p.read_text()
    if old not in s:
        sys.exit(f"patch.py: {rel}: {old!r} not found")
    p.write_text(s.replace(old, new, 1))


# 1. Paths.
lit = re.compile(r'"(/etc/|/var/(?:tmp|db|run|lib|log|spool|mail)\b|/tmp(?=[/"]))')
changed = 0
for p in list((src / "src").rglob("*.c")) + list((src / "include").rglob("*.h")):
    s = p.read_text()
    n = lit.sub(lambda m: '"' + prefix + m.group(1), s)
    if n != s:
        p.write_text(n)
        changed += 1
if changed < 10:
    sys.exit(f"patch.py: only {changed} files had /etc, /var or /tmp paths")
# tmpfile() and tmpnam() fill in the XXXXXX at a fixed offset into the path.
edit("src/stdio/tmpfile.c", "__randname(s+13)", "__randname(s+sizeof s-7)")
edit("src/stdio/tmpnam.c", "__randname(s+12)", "__randname(s+sizeof s-7)")
for rel in ("src/process/system.c", "src/stdio/popen.c", "src/misc/wordexp.c", "include/paths.h"):
    edit(rel, '"/bin/sh"', '"/system/bin/sh"')
edit("src/process/execvp.c", '"/usr/local/bin:/bin:/usr/bin"', f'"{prefix}/bin:/system/bin"')
edit("include/paths.h", '"/usr/local/bin:/bin:/usr/bin"', f'"{prefix}/bin:/system/bin"')
edit("src/conf/confstr.c", '"/bin:/usr/bin"', f'"{prefix}/bin:/system/bin"')
edit("ldso/dynlink.c", '"/lib:/usr/local/lib:/usr/lib"', f'"{prefix}/lib:{prefix}/usr/lib"')
# The loader's own settings file: <prefix>/etc/ld-musl-aarch64.path, not one
# next to wherever the loader is (the APK's library folder).
edit("ldso/dynlink.c", '''+ sizeof "/etc/ld-musl-" LDSO_ARCH ".path"];''',
     f'''+ sizeof "{prefix}/etc/ld-musl-" LDSO_ARCH ".path"];''')
edit("ldso/dynlink.c", '''"%.*s/etc/ld-musl-" LDSO_ARCH ".path",
					(int)prefix_len, prefix);''', f'''"%.*s{prefix}/etc/ld-musl-" LDSO_ARCH ".path",
					0, prefix);''')

# 2. The loader's variables.
edit("ldso/dynlink.c", 'getenv("LD_LIBRARY_PATH")', 'getenv("DDMASK_MUSL_LD_LIBRARY_PATH")')
edit("ldso/dynlink.c", 'getenv("LD_PRELOAD")', 'getenv("DDMASK_MUSL_LD_PRELOAD")')

# 3. SIGSYS -> ENOSYS, installed just before the loader jumps to the program.
edit("ldso/dynlink.c", '#include "libc.h"', '''#include "libc.h"
#include <signal.h>
#include <ucontext.h>

/* DeskDroid: Android's seccomp filter sends SIGSYS for a system call it
 * blocks; make the call return ENOSYS instead of killing the process. */
static void deskdroid_sigsys(int sig, siginfo_t *si, void *ctx)
{
	(void)sig; (void)si;
#if defined(__aarch64__)
	((ucontext_t *)ctx)->uc_mcontext.regs[0] = -ENOSYS;
#elif defined(__x86_64__)
	((ucontext_t *)ctx)->uc_mcontext.gregs[REG_RAX] = -ENOSYS;
#endif
}''')
edit("ldso/dynlink.c", '''	errno = 0;

	CRTJMP((void *)aux[AT_ENTRY], argv-1);''', '''	{
		struct sigaction sa = { .sa_sigaction = deskdroid_sigsys, .sa_flags = SA_SIGINFO };
		sigaction(SIGSYS, &sa, 0);
	}
	errno = 0;

	CRTJMP((void *)aux[AT_ENTRY], argv-1);''')
print(f"patch.py: {changed} files with paths under {prefix}")

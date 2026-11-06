#!/usr/bin/env python3
"""DeskDroid's changes to glibc, so glibc programs run on Android without proot.

patch.py <glibc source dir> <prefix>

1. Paths: Android has no /etc, /tmp, /var or /bin/sh. Every "/etc/...",
   "/var/...", "/tmp" in glibc's own sources (not its tests) moves under
   <prefix> (/data/data/io.deskdroid.app/files/glibc), and the shell is
   Android's /system/bin/sh.
2. Environment: glibc's loader reads DDMASK_GLIBC_LD_* (DDMASK_GLIBC_LD_PRELOAD,
   DDMASK_GLIBC_LD_LIBRARY_PATH...) instead of LD_*, which belong to Android's
   loader. Both kinds of program then pass through each other's environment
   without one loader trying to load the other's libraries.
3. Android's seccomp policy kills an app's process on a system call it doesn't
   allow (set_robust_list, which glibc makes at start, and others). The loader
   catches that signal (SIGSYS) first thing and makes the call fail with ENOSYS
   instead, which glibc and most programs handle.
"""
import pathlib
import re
import sys

src = pathlib.Path(sys.argv[1])
prefix = sys.argv[2].rstrip("/")


def edit(rel, old, new, count=1):
    p = src / rel
    s = p.read_text()
    if s.count(old) < 1:
        sys.exit(f"patch.py: {rel}: {old!r} not found")
    p.write_text(s.replace(old, new, count if count else -1))


# 1. Paths, in glibc's own sources: tests, manual and other systems' code keep theirs.
skip = re.compile(r"(^|/)(tst-|test-|bug-)|/tests?/|^manual/|^scripts/|^sysdeps/mach/|^hurd/|^benchtests/|^conform/")
lit = re.compile(r'"(/etc/|/var/(?:tmp|db|run|lib|log|spool|mail|nis|yp)\b|/tmp(?=[/"]))')
changed = 0
for p in src.rglob("*"):
    if p.suffix not in (".c", ".h") or not p.is_file():
        continue
    rel = p.relative_to(src).as_posix()
    if skip.search(rel):
        continue
    s = p.read_text(errors="surrogateescape")
    n = lit.sub(lambda m: '"' + prefix + m.group(1), s)
    if n != s:
        p.write_text(n, errors="surrogateescape")
        changed += 1
if changed < 20:
    sys.exit(f"patch.py: only {changed} files had /etc, /var or /tmp paths")
edit("sysdeps/unix/sysv/linux/paths.h", '"/bin/sh"', '"/system/bin/sh"')
edit("sysdeps/unix/sysv/linux/paths.h", '"/usr/bin:/bin"', f'"{prefix}/bin:/system/bin"')
edit("sysdeps/posix/system.c", '"/bin/sh"', '"/system/bin/sh"')

# 2. The loader's variables.
edit("elf/dl-environ.c",
     """      if (__builtin_expect ((*current)[0] == 'L', 0)
	  && (*current)[1] == 'D' && (*current)[2] == '_')
	{
	  result = &(*current)[3];""",
     """      /* DeskDroid: DDMASK_GLIBC_LD_*, as LD_* is Android's loader's.  */
      if (__builtin_expect ((*current)[0] == 'D', 0)
	  && strncmp (*current, "DDMASK_GLIBC_LD_", 16) == 0)
	{
	  result = &(*current)[16];""")
edit("elf/dl-environ.c", "#include <stdlib.h>", "#include <stdlib.h>\n#include <string.h>")
# Its messages name them that way too.
edit("elf/rtld.c", '''npreloads += handle_preload_list (state.preloadlist, main_map,
					"LD_PRELOAD");''', '''npreloads += handle_preload_list (state.preloadlist, main_map,
					"DDMASK_GLIBC_LD_PRELOAD");''')
edit("elf/rtld.c", 'state->library_path_source = "LD_LIBRARY_PATH";', 'state->library_path_source = "DDMASK_GLIBC_LD_LIBRARY_PATH";')

# 3. SIGSYS: blocked system calls fail with ENOSYS.
edit("elf/rtld.c", "#include <dl-call_tls_init_tp.h>", """#include <dl-call_tls_init_tp.h>
#include <signal.h>
#include <sys/ucontext.h>
#include <kernel_sigaction.h>

/* DeskDroid: Android's seccomp filter traps system calls apps may not make
   (SIGSYS). Make them return ENOSYS, as on a kernel without them.  */
static void
deskdroid_sigsys (int sig, siginfo_t *info, void *context)
{
  ucontext_t *uc = context;
#if defined __aarch64__
  uc->uc_mcontext.regs[0] = (unsigned long int) -ENOSYS;
#elif defined __x86_64__
  uc->uc_mcontext.gregs[REG_RAX] = -ENOSYS;
#endif
}

static void
deskdroid_catch_sigsys (void)
{
  struct kernel_sigaction act = { 0 };
  act.k_sa_handler = (__sighandler_t) deskdroid_sigsys;
  act.sa_flags = SA_SIGINFO;
  INTERNAL_SYSCALL_CALL (rt_sigaction, SIGSYS, &act, NULL, __NSIG_BYTES);
}""")
edit("elf/rtld.c", """  struct dl_main_state state;
  dl_main_state_init (&state);
""", """  deskdroid_catch_sigsys ();

  struct dl_main_state state;
  dl_main_state_init (&state);
""")
print(f"patch.py: {changed} files with paths under {prefix}")

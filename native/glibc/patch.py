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
4. No clone3: glibc makes it with every signal blocked (creating a thread,
   posix_spawn), where SIGSYS can't be caught and the process dies ("Bad
   system call"). glibc uses plain clone instead, as on kernels before 5.3.
5. No rseq: glibc registers it again in every new thread, also with every
   signal blocked. Off by default (the glibc.pthread.rseq tunable), as on
   kernels before 4.18.
6. set_robust_list, which Android blocks (the log above names it, number 99),
   glibc makes again in every new thread and in fork's child, both with every
   signal blocked. Built as for kernels without it: glibc checks the result of
   its first call at start and skips the rest.
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
#if defined __x86_64__ && !defined SA_RESTORER
# define SA_RESTORER 0x04000000
#endif
#include <kernel_sigaction.h>
#include <fcntl.h>

/* DeskDroid: Android's seccomp filter traps system calls apps may not make
   (SIGSYS). Make them return ENOSYS, as on a kernel without them.  */
static void
deskdroid_sigsys (int sig, siginfo_t *info, void *context)
{
  ucontext_t *uc = context;
  /* Note the call in <prefix>/sigsys.log: the calls Android blocks, for
     finding the one that killed a program where this can't run.  */
  {
    char line[24];
    int n = sizeof line;
    line[--n] = '\\n';
    unsigned int nr = info->si_syscall;
    do
      line[--n] = '0' + nr % 10;
    while ((nr /= 10) != 0 && n > 0);
    int fd = INTERNAL_SYSCALL_CALL (openat, AT_FDCWD, "@PREFIX@/sigsys.log",
                                    O_WRONLY | O_APPEND | O_CREAT | O_CLOEXEC, 0600);
    if (fd >= 0)
      {
        INTERNAL_SYSCALL_CALL (write, fd, line + n, sizeof line - n);
        INTERNAL_SYSCALL_CALL (close, fd);
      }
  }
#if defined __aarch64__
  uc->uc_mcontext.regs[0] = (unsigned long int) -ENOSYS;
#elif defined __x86_64__
  uc->uc_mcontext.gregs[REG_RAX] = -ENOSYS;
#endif
}

#if defined __x86_64__
/* x86_64 (a desktop machine standing in for the phone, test/android-sim.sh)
   returns from a handler through a restorer the program names; ARM64's
   kernel has its own.  */
extern void deskdroid_restore_rt (void) attribute_hidden;
asm (".text\\n"
     "deskdroid_restore_rt:\\n"
     "  movq $15, %rax\\n" /* rt_sigreturn */
     "  syscall\\n");
#endif

static void
deskdroid_catch_sigsys (void)
{
  struct kernel_sigaction act = { 0 };
  act.k_sa_handler = (__sighandler_t) deskdroid_sigsys;
  act.sa_flags = SA_SIGINFO;
#if defined __x86_64__
  act.sa_flags |= SA_RESTORER;
  act.sa_restorer = deskdroid_restore_rt;
#endif
  INTERNAL_SYSCALL_CALL (rt_sigaction, SIGSYS, &act, NULL, __NSIG_BYTES);
}""".replace("@PREFIX@", prefix))
edit("elf/rtld.c", """  struct dl_main_state state;
  dl_main_state_init (&state);
""", """  deskdroid_catch_sigsys ();

  struct dl_main_state state;
  dl_main_state_init (&state);
""")
# 4. No clone3 (see above): without HAVE_CLONE3_WRAPPER glibc only uses clone.
for arch in ("aarch64", "x86_64"):
    p = src / f"sysdeps/unix/sysv/linux/{arch}/sysdep.h"
    t, n = re.subn(r"^# define HAVE_CLONE3_WRAPPER\s+1$", "/* DeskDroid: no HAVE_CLONE3_WRAPPER */", p.read_text(), flags=re.M)
    if n != 1:
        sys.exit(f"patch.py: {arch}/sysdep.h: HAVE_CLONE3_WRAPPER not found")
    p.write_text(t)
# 5. No rseq (see above).
edit("sysdeps/nptl/dl-tunables.list", """    rseq {
      type: INT_32
      minval: 0
      maxval: 1
      default: 1""", """    rseq {
      type: INT_32
      minval: 0
      maxval: 1
      default: 0""")
# 6. set_robust_list only where the first call at start worked (see above).
edit("sysdeps/unix/sysv/linux/kernel-features.h", "#define __ASSUME_SET_ROBUST_LIST\t1",
     "/* DeskDroid: no __ASSUME_SET_ROBUST_LIST (Android blocks it) */")
edit("sysdeps/nptl/_Fork.c", """      INTERNAL_SYSCALL_CALL (set_robust_list, &self->robust_head,""",
     """#ifndef __ASSUME_SET_ROBUST_LIST
      if (__nptl_set_robust_list_avail)
#endif
      INTERNAL_SYSCALL_CALL (set_robust_list, &self->robust_head,""")
print(f"patch.py: {changed} files with paths under {prefix}")

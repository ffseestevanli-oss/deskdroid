/* A desktop stand-in for an Android app's process (x86_64), for testing
   DeskDroid's glibc programs (flatpak) without a phone:
   - Android's seccomp policy for apps (android-policy.py): other system calls
     trap with SIGSYS, which kills the process if it's blocked or unhandled;
   - SELinux's denials for app data that programs run into: hard links
     (link, linkat: EACCES);
   then runs the command. Build: see android-sim.sh.  */
#include <errno.h>
#include <linux/audit.h>
#include <linux/filter.h>
#include <linux/seccomp.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>
#include <sys/prctl.h>
#include <sys/syscall.h>
#include <unistd.h>

#include "android-policy.h"

#define N (sizeof android_allowed / sizeof android_allowed[0])

int
main (int argc, char **argv)
{
  if (argc < 2)
    {
      fprintf (stderr, "usage: android-sim <command> [args...]\n");
      return 2;
    }
  static struct sock_filter f[8 + 2 * N + 1];
  int i = 0;
  f[i++] = (struct sock_filter) BPF_STMT (BPF_LD | BPF_W | BPF_ABS, offsetof (struct seccomp_data, arch));
  f[i++] = (struct sock_filter) BPF_JUMP (BPF_JMP | BPF_JEQ | BPF_K, AUDIT_ARCH_X86_64, 1, 0);
  f[i++] = (struct sock_filter) BPF_STMT (BPF_RET | BPF_K, SECCOMP_RET_KILL_PROCESS);
  f[i++] = (struct sock_filter) BPF_STMT (BPF_LD | BPF_W | BPF_ABS, offsetof (struct seccomp_data, nr));
  /* SELinux: no hard links in app data.  */
  f[i++] = (struct sock_filter) BPF_JUMP (BPF_JMP | BPF_JEQ | BPF_K, __NR_link, 1, 0);
  f[i++] = (struct sock_filter) BPF_JUMP (BPF_JMP | BPF_JEQ | BPF_K, __NR_linkat, 0, 1);
  f[i++] = (struct sock_filter) BPF_STMT (BPF_RET | BPF_K, SECCOMP_RET_ERRNO | EACCES);
  for (unsigned int k = 0; k < N; k++)
    {
      f[i++] = (struct sock_filter) BPF_JUMP (BPF_JMP | BPF_JEQ | BPF_K, android_allowed[k], 0, 1);
      f[i++] = (struct sock_filter) BPF_STMT (BPF_RET | BPF_K, SECCOMP_RET_ALLOW);
    }
  f[i++] = (struct sock_filter) BPF_STMT (BPF_RET | BPF_K, SECCOMP_RET_TRAP);
  struct sock_fprog prog = { .len = (unsigned short) i, .filter = f };
  if (prctl (PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) || prctl (PR_SET_SECCOMP, SECCOMP_MODE_FILTER, &prog))
    {
      perror ("android-sim: seccomp");
      return 1;
    }
  execvp (argv[1], argv + 1);
  perror ("android-sim: exec");
  return 127;
}

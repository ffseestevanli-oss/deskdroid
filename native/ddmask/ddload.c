/*
 * ddload: runs a static program, which has no interpreter that Android could
 * start it through (ddmask runs dynamic programs through their loader).
 *
 *   libdd_static.so <program> <argv[0]> <args>...
 *
 * It lives in the APK's library folder, where Android lets it run. It maps
 * the program's segments itself (Android allows mapping an app's own files as
 * code), points the auxiliary vector at the program, and jumps to its entry
 * point on its own stack: the kernel's exec, done in user space. The program
 * sees argv[0] and the rest of its arguments, its environment, and its own
 * headers; /proc/self/exe still names ddload.
 *
 * Freestanding (no C library), so the same file builds with the NDK for the
 * phone and with any gcc for the tests; aarch64 and x86_64.
 */
#include <elf.h>
#include <stddef.h>
#include <stdint.h>

#define PAGE 4096UL /* the minimum; segments align to their own p_align */
#define NAME_MAX_ 15

#if defined(__aarch64__)
#define SYS_openat 56
#define SYS_close 57
#define SYS_pread64 67
#define SYS_write 64
#define SYS_exit 93
#define SYS_mmap 222
#define SYS_munmap 215
#define SYS_mprotect 226
#define SYS_prctl 167
#define SYS_rt_sigaction 134
static long sys6(long n, long a, long b, long c, long d, long e, long f) {
    register long x8 __asm__("x8") = n, x0 __asm__("x0") = a, x1 __asm__("x1") = b, x2 __asm__("x2") = c,
                  x3 __asm__("x3") = d, x4 __asm__("x4") = e, x5 __asm__("x5") = f;
    __asm__ volatile("svc 0" : "+r"(x0) : "r"(x8), "r"(x1), "r"(x2), "r"(x3), "r"(x4), "r"(x5) : "memory");
    return x0;
}
/* SIGSYS: x0 is the system call's return value. */
#define SIGSYS_RESULT(uc) (((uint64_t *)((char *)(uc) + 176 + 8))[0]) /* uc_mcontext.regs[0] (after fault_address) */
#define SA_RESTORER_ 0
__asm__(".text\n.global _start\n_start:\n mov x29, #0\n mov x30, #0\n mov x0, sp\n bl ddload_main\n");
static void __attribute__((noreturn)) jump(uintptr_t entry, uintptr_t sp) {
    __asm__ volatile("mov sp, %1\n mov x0, #0\n mov x29, #0\n mov x30, #0\n br %0" :: "r"(entry), "r"(sp) : "x0", "memory");
    __builtin_unreachable();
}
#elif defined(__x86_64__)
#define SYS_openat 257
#define SYS_close 3
#define SYS_pread64 17
#define SYS_write 1
#define SYS_exit 60
#define SYS_mmap 9
#define SYS_munmap 11
#define SYS_mprotect 10
#define SYS_prctl 157
#define SYS_rt_sigaction 13
static long sys6(long n, long a, long b, long c, long d, long e, long f) {
    register long r10 __asm__("r10") = d, r8 __asm__("r8") = e, r9 __asm__("r9") = f;
    long r;
    __asm__ volatile("syscall" : "=a"(r) : "a"(n), "D"(a), "S"(b), "d"(c), "r"(r10), "r"(r8), "r"(r9) : "rcx", "r11", "memory");
    return r;
}
/* SIGSYS: rax is the system call's return value; x86_64 needs its own sigreturn. */
#define SIGSYS_RESULT(uc) (((uint64_t *)((char *)(uc) + 40))[13]) /* uc_mcontext.gregs[REG_RAX] */
#define SA_RESTORER_ 0x04000000
__asm__(".text\nddload_restore:\n mov $15, %eax\n syscall\n");
extern char ddload_restore[];
__asm__(".text\n.global _start\n_start:\n xor %rbp, %rbp\n mov %rsp, %rdi\n and $-16, %rsp\n call ddload_main\n");
static void __attribute__((noreturn)) jump(uintptr_t entry, uintptr_t sp) {
    __asm__ volatile("mov %1, %%rsp\n xor %%edx, %%edx\n xor %%ebp, %%ebp\n jmp *%0" :: "r"(entry), "r"(sp) : "rdx", "memory");
    __builtin_unreachable();
}
#else
#error "ddload: aarch64 and x86_64 only"
#endif

#define AT_FDCWD_ -100
#define PROT_R 1
#define PROT_W 2
#define PROT_X 4
#define MAP_PRIVATE_ 0x02
#define MAP_FIXED_ 0x10
#define MAP_ANON_ 0x20
#define MAP_FIXED_NOREPLACE_ 0x100000
#define PR_SET_NAME_ 15

/* The compiler may call these for struct copies and loops. */
void *memset(void *d, int c, size_t n) { unsigned char *p = d; while (n--) *p++ = (unsigned char)c; return d; }
void *memcpy(void *d, const void *s, size_t n) { unsigned char *p = d; const unsigned char *q = s; while (n--) *p++ = *q++; return d; }

static size_t len(const char *s) { size_t n = 0; while (s[n]) n++; return n; }
static int bad(long r) { return (unsigned long)r > -4096UL; }

static void __attribute__((noreturn)) die(const char *prog, const char *why) {
    static const char me[] = "ddload: ";
    sys6(SYS_write, 2, (long)me, sizeof me - 1, 0, 0, 0);
    if (prog) { sys6(SYS_write, 2, (long)prog, len(prog), 0, 0, 0); sys6(SYS_write, 2, (long)": ", 2, 0, 0, 0); }
    sys6(SYS_write, 2, (long)why, len(why), 0, 0, 0);
    sys6(SYS_write, 2, (long)"\n", 1, 0, 0, 0);
    sys6(SYS_exit, 127, 0, 0, 0, 0, 0);
    __builtin_unreachable();
}

/*
 * Android's seccomp filter kills a process with SIGSYS on a system call it
 * blocks. glibc's and musl's loaders (native/glibc, native/musl) make such a
 * call fail with ENOSYS instead; a static program has no loader, so ddload
 * does it: the handler stays in ddload's memory, which stays mapped, and a
 * program that sets its own SIGSYS handler replaces it.
 */
static void sigsys(int sig, void *info, void *uc) {
    (void)sig; (void)info;
    SIGSYS_RESULT(uc) = (uint64_t)-38; /* -ENOSYS */
}

static void catch_sigsys(void) {
    struct { void *handler; unsigned long flags; void *restorer; uint64_t mask; } sa = { 0 };
    sa.handler = (void *)sigsys;
    sa.flags = 4 /* SA_SIGINFO */ | SA_RESTORER_;
#if SA_RESTORER_
    sa.restorer = (void *)ddload_restore;
#endif
    sys6(SYS_rt_sigaction, 31 /* SIGSYS */, (long)&sa, 0, 8, 0, 0);
}

static int prot_of(uint32_t f) { return (f & PF_R ? PROT_R : 0) | (f & PF_W ? PROT_W : 0) | (f & PF_X ? PROT_X : 0); }

#if defined(__aarch64__)
#define MACHINE EM_AARCH64
#else
#define MACHINE EM_X86_64
#endif

/*
 * The stack the kernel gave us: argc, argv[] (ddload, program, argv[0], args),
 * NULL, envp[], NULL, auxv[]. The program gets it from argv[2] on.
 */
__attribute__((used, noreturn)) void ddload_main(uintptr_t *sp) {
    long argc = (long)sp[0];
    char **argv = (char **)(sp + 1);
    if (argc < 3) die(0, "usage: libdd_static.so <program> <argv[0]> [args...]");
    const char *prog = argv[1];

    long fd = sys6(SYS_openat, AT_FDCWD_, (long)prog, 0 /* O_RDONLY */ | 02000000 /* O_CLOEXEC */, 0, 0, 0);
    if (bad(fd)) die(prog, "can't open");
    Elf64_Ehdr eh;
    if (sys6(SYS_pread64, fd, (long)&eh, sizeof eh, 0, 0, 0) != (long)sizeof eh
        || eh.e_ident[EI_MAG0] != ELFMAG0 || eh.e_ident[EI_MAG1] != ELFMAG1 || eh.e_ident[EI_MAG2] != ELFMAG2
        || eh.e_ident[EI_MAG3] != ELFMAG3 || eh.e_ident[EI_CLASS] != ELFCLASS64)
        die(prog, "not a 64-bit ELF file");
    if (eh.e_machine != MACHINE) die(prog, "built for another CPU");
    if (eh.e_type != ET_EXEC && eh.e_type != ET_DYN) die(prog, "not a program");
    if (eh.e_phentsize != sizeof(Elf64_Phdr) || eh.e_phnum == 0 || eh.e_phnum > 64) die(prog, "bad program headers");
    Elf64_Phdr ph[64];
    size_t phsz = eh.e_phnum * sizeof(Elf64_Phdr);
    if (sys6(SYS_pread64, fd, (long)ph, phsz, eh.e_phoff, 0, 0) != (long)phsz) die(prog, "can't read its program headers");

    /* The span its segments cover. */
    uintptr_t lo = UINTPTR_MAX, hi = 0, phdr_vaddr = 0;
    unsigned long align = PAGE;
    for (int i = 0; i < eh.e_phnum; i++) {
        if (ph[i].p_type == PT_INTERP) die(prog, "has an interpreter (ddmask runs it through that)");
        if (ph[i].p_type == PT_PHDR) phdr_vaddr = ph[i].p_vaddr;
        if (ph[i].p_type != PT_LOAD) continue;
        if (ph[i].p_align > align) align = ph[i].p_align;
        uintptr_t s = ph[i].p_vaddr & ~(PAGE - 1), e = ph[i].p_vaddr + ph[i].p_memsz;
        if (s < lo) lo = s;
        if (e > hi) hi = e;
    }
    if (hi <= lo) die(prog, "no segments to load");
    hi = (hi + PAGE - 1) & ~(PAGE - 1);

    /* Reserve the span: where it asks (ET_EXEC), or anywhere aligned (static PIE). */
    uintptr_t base = 0;
    if (eh.e_type == ET_EXEC) {
        /* (Kernels before 4.17 take NOREPLACE as a hint: check where it landed.) */
        long r = sys6(SYS_mmap, lo, hi - lo, 0, MAP_PRIVATE_ | MAP_ANON_ | MAP_FIXED_NOREPLACE_, -1, 0);
        if (bad(r) || (uintptr_t)r != lo) die(prog, "its addresses are taken");
    } else {
        long r = sys6(SYS_mmap, 0, hi - lo + align, 0, MAP_PRIVATE_ | MAP_ANON_, -1, 0);
        if (bad(r)) die(prog, "out of memory");
        uintptr_t a = ((uintptr_t)r + align - 1) & ~(uintptr_t)(align - 1);
        if (a > (uintptr_t)r) sys6(SYS_munmap, r, a - (uintptr_t)r, 0, 0, 0, 0);
        uintptr_t end = (uintptr_t)r + hi - lo + align;
        if (end > a + (hi - lo)) sys6(SYS_munmap, a + (hi - lo), end - (a + (hi - lo)), 0, 0, 0, 0);
        base = a - lo;
    }

    /* Each segment: its file pages, then zeroes (.bss). */
    for (int i = 0; i < eh.e_phnum; i++) {
        if (ph[i].p_type != PT_LOAD) continue;
        uintptr_t va = base + ph[i].p_vaddr, page = va & ~(PAGE - 1);
        uintptr_t off = ph[i].p_offset & ~(PAGE - 1);
        int prot = prot_of(ph[i].p_flags);
        uintptr_t file_end = va + ph[i].p_filesz, mem_end = va + ph[i].p_memsz;
        if (ph[i].p_filesz) {
            long r = sys6(SYS_mmap, page, file_end - page, prot | (ph[i].p_memsz > ph[i].p_filesz ? PROT_W : 0),
                          MAP_PRIVATE_ | MAP_FIXED_, fd, off);
            if (bad(r)) die(prog, "can't map a segment");
        }
        uintptr_t zero_page = (file_end + PAGE - 1) & ~(PAGE - 1);
        if (ph[i].p_memsz > ph[i].p_filesz) {
            if (ph[i].p_filesz && file_end < zero_page) memset((void *)file_end, 0, zero_page - file_end);
            else if (!ph[i].p_filesz) zero_page = page;
            if (mem_end > zero_page) {
                long r = sys6(SYS_mmap, zero_page, mem_end - zero_page, prot, MAP_PRIVATE_ | MAP_ANON_ | MAP_FIXED_, -1, 0);
                if (bad(r)) die(prog, "can't map its zeroed memory");
            }
            if (ph[i].p_filesz && !(prot & PROT_W)) sys6(SYS_mprotect, page, zero_page - page, prot, 0, 0, 0);
        }
    }
    sys6(SYS_close, fd, 0, 0, 0, 0, 0);

    /* Where its program headers are in memory: PT_PHDR, or inside the segment that maps e_phoff. */
    if (!phdr_vaddr)
        for (int i = 0; i < eh.e_phnum; i++)
            if (ph[i].p_type == PT_LOAD && eh.e_phoff >= ph[i].p_offset && eh.e_phoff + phsz <= ph[i].p_offset + ph[i].p_filesz)
                phdr_vaddr = ph[i].p_vaddr + (eh.e_phoff - ph[i].p_offset);
    if (!phdr_vaddr) die(prog, "its program headers aren't in a segment");

    /* The program's stack: drop ddload and the program path from argv. */
    char **envp = argv + argc + 1;
    char **e = envp;
    while (*e) e++;
    Elf64_auxv_t *av = (Elf64_auxv_t *)(e + 1);
    for (; av->a_type != AT_NULL; av++) {
        switch (av->a_type) {
        case AT_PHDR: av->a_un.a_val = base + phdr_vaddr; break;
        case AT_PHNUM: av->a_un.a_val = eh.e_phnum; break;
        case AT_PHENT: av->a_un.a_val = sizeof(Elf64_Phdr); break;
        case AT_ENTRY: av->a_un.a_val = base + eh.e_entry; break;
        case AT_BASE: av->a_un.a_val = 0; break;
        case AT_EXECFN: av->a_un.a_val = (uintptr_t)prog; break;
        }
    }
    sp[2] = (uintptr_t)(argc - 2);

    /* Its process name, as the kernel would set it. */
    const char *name = prog;
    for (const char *p = prog; *p; p++) if (*p == '/') name = p + 1;
    char comm[NAME_MAX_ + 1];
    size_t n = 0;
    while (name[n] && n < NAME_MAX_) { comm[n] = name[n]; n++; }
    comm[n] = 0;
    sys6(SYS_prctl, PR_SET_NAME_, (long)comm, 0, 0, 0, 0);
    catch_sigsys();

    jump(base + eh.e_entry, (uintptr_t)(sp + 2));
}

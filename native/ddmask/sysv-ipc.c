/*
 * System V shared memory and semaphores, which Android's seccomp filter
 * blocks for apps (shmget, shmat, semget, semop... all fail). Linux programs
 * use them: X11 clients draw through MIT-SHM, audio stacks and Wine share
 * buffers, some servers lock with semaphores. Included by ddmask.c in its
 * glibc and musl builds.
 *
 * Each segment or semaphore set is a file in $DDMASK_SHM/sysv (else
 * $TMPDIR/ddmask-shm/sysv), shared by every process that uses that folder:
 *   shm.<id>                 a segment's memory (its size is the file's)
 *   shm.<id>.rm              removed (IPC_RMID) while still attached
 *   shm.<id>.at.<pid>.<addr> one process's attachment, for shm_nattch
 *   sem.<id>                 a semaphore set (struct semset), mapped shared
 *   shm-key.<key>, sem-key.<key>  links from a key to its id's file
 * Ids name the files, so an id passed to another process (a client telling
 * the X server which segment to read) works there too. Semaphore waits are
 * futexes in the shared mapping. Message queues aren't here: hardly anything
 * uses them.
 */
#include <dirent.h>
#include <sys/ipc.h>
#include <sys/mman.h>
#include <sys/sem.h>
#include <sys/shm.h>

#ifndef SHM_EXEC
#define SHM_EXEC 0100000
#endif
#ifndef SHM_REMAP
#define SHM_REMAP 040000
#endif
#ifndef SHM_STAT
#define SHM_STAT 13
#endif
#ifndef SHM_STAT_ANY
#define SHM_STAT_ANY 15
#endif
#ifndef SEM_STAT
#define SEM_STAT 18
#endif
#ifndef SEM_STAT_ANY
#define SEM_STAT_ANY 20
#endif
#ifndef SEM_INFO
#define SEM_INFO 19
#endif
#ifndef SHM_INFO
#define SHM_INFO 14
#endif
#ifndef FUTEX_WAIT
#define FUTEX_WAIT 0
#define FUTEX_WAKE 1
#endif
#define SEMVMX_ 32767
#define SEMMSL_ 32000

/* ---- the folder, ids and keys ---- */

static int sysv_dir(char *out, size_t size) {
    char base[PATH_MAX];
    shm_fallback(base, sizeof base);
    if ((size_t)snprintf(out, size, "%s/sysv", base) >= size) { errno = ENAMETOOLONG; return -1; }
    if (mkdir(out, 0700) != 0 && errno != EEXIST) return -1;
    return 0;
}

static int sysv_path(char *out, const char *kind, int id, const char *suffix) {
    char dir[PATH_MAX];
    if (sysv_dir(dir, sizeof dir) != 0) return -1;
    if (snprintf(out, PATH_MAX, "%s/%s.%d%s", dir, kind, id, suffix) >= PATH_MAX) { errno = ENAMETOOLONG; return -1; }
    return 0;
}

static int sysv_keypath(char *out, const char *kind, key_t key) {
    char dir[PATH_MAX];
    if (sysv_dir(dir, sizeof dir) != 0) return -1;
    if (snprintf(out, PATH_MAX, "%s/%s-key.%08x", dir, kind, (unsigned)key) >= PATH_MAX) { errno = ENAMETOOLONG; return -1; }
    return 0;
}

/* The id a key names, or -1 (a link to a file that's gone is cleared). */
static int sysv_key_id(const char *kind, key_t key) {
    char kp[PATH_MAX], target[64];
    if (sysv_keypath(kp, kind, key) != 0) return -1;
    ssize_t n = readlink(kp, target, sizeof target - 1);
    if (n <= 0) return -1;
    target[n] = 0;
    size_t kl = strlen(kind);
    if (strncmp(target, kind, kl) != 0 || target[kl] != '.') return -1;
    int id = atoi(target + kl + 1);
    char p[PATH_MAX];
    if (sysv_path(p, kind, id, "") != 0) return -1;
    if (access(p, F_OK) != 0) { unlink(kp); return -1; }
    return id;
}

/* Makes <kind>.<id> (O_EXCL) with a new id; returns its fd, the id in *id. */
static int sysv_create(const char *kind, int mode, int *id) {
    static unsigned int counter;
    char p[PATH_MAX];
    for (int tries = 0; tries < 1000; tries++) {
        unsigned int c = __atomic_add_fetch(&counter, 1, __ATOMIC_RELAXED);
        int n = (int)(((unsigned int)getpid() * 65599u + c * 2654435761u + (unsigned int)time(NULL)) & 0x3fffffff);
        if (n == 0) continue;
        if (sysv_path(p, kind, n, "") != 0) return -1;
        int fd = open(p, O_RDWR | O_CREAT | O_EXCL | O_CLOEXEC, (mode & 0777) | 0600);
        if (fd >= 0) { *id = n; return fd; }
        if (errno != EEXIST) return -1;
    }
    errno = ENOSPC;
    return -1;
}

/* Clears the key links that point at <kind>.<id>. */
static void sysv_unkey(const char *kind, int id) {
    char dir[PATH_MAX], want[64], prefix[16], p[PATH_MAX], target[64];
    if (sysv_dir(dir, sizeof dir) != 0) return;
    snprintf(want, sizeof want, "%s.%d", kind, id);
    snprintf(prefix, sizeof prefix, "%s-key.", kind);
    DIR *d = opendir(dir);
    if (!d) return;
    struct dirent *e;
    while ((e = readdir(d))) {
        if (strncmp(e->d_name, prefix, strlen(prefix)) != 0) continue;
        snprintf(p, sizeof p, "%s/%s", dir, e->d_name);
        ssize_t n = readlink(p, target, sizeof target - 1);
        if (n > 0) { target[n] = 0; if (!strcmp(target, want)) unlink(p); }
    }
    closedir(d);
}

/* shmget/semget: the id for key, made with make() when asked. */
static int sysv_get(const char *kind, key_t key, int flg, int (*make)(int flg, long arg), long arg,
                    int (*fits)(int id, long arg)) {
    if (key == IPC_PRIVATE) return make(flg, arg);
    char kp[PATH_MAX];
    if (sysv_keypath(kp, kind, key) != 0) return -1;
    for (int tries = 0; tries < 100; tries++) {
        int id = sysv_key_id(kind, key);
        if (id >= 0) {
            if ((flg & IPC_CREAT) && (flg & IPC_EXCL)) { errno = EEXIST; return -1; }
            if (!fits(id, arg)) { errno = EINVAL; return -1; }
            return id;
        }
        if (!(flg & IPC_CREAT)) { errno = ENOENT; return -1; }
        id = make(flg, arg);
        if (id < 0) return -1;
        char target[64];
        snprintf(target, sizeof target, "%s.%d", kind, id);
        if (symlink(target, kp) == 0) return id;
        int e = errno;
        char p[PATH_MAX];
        if (sysv_path(p, kind, id, "") == 0) unlink(p);
        if (e != EEXIST) { errno = e; return -1; }
    }
    errno = EAGAIN;
    return -1;
}

static int pid_alive(int pid) { return pid > 0 && (kill(pid, 0) == 0 || errno == EPERM); }

/* ---- shared memory ---- */

static struct { void *addr; size_t size; int id; } shm_maps[256];
static int shm_maps_lock;
static void maps_lock(void) { while (__atomic_exchange_n(&shm_maps_lock, 1, __ATOMIC_ACQUIRE)) sched_yield(); }
static void maps_unlock(void) { __atomic_store_n(&shm_maps_lock, 0, __ATOMIC_RELEASE); }

/* Live attachments of segment id (clearing those of processes that ended). */
static int shm_nattch(int id) {
    char dir[PATH_MAX], prefix[48], p[PATH_MAX];
    if (sysv_dir(dir, sizeof dir) != 0) return 0;
    int pl = snprintf(prefix, sizeof prefix, "shm.%d.at.", id);
    int n = 0;
    DIR *d = opendir(dir);
    if (!d) return 0;
    struct dirent *e;
    while ((e = readdir(d))) {
        if (strncmp(e->d_name, prefix, pl) != 0) continue;
        if (pid_alive(atoi(e->d_name + pl))) n++;
        else { snprintf(p, sizeof p, "%s/%s", dir, e->d_name); unlink(p); }
    }
    closedir(d);
    return n;
}

/* A removed segment goes once nothing has it attached. */
static void shm_reap(int id) {
    char rm[PATH_MAX], p[PATH_MAX];
    if (sysv_path(rm, "shm", id, ".rm") != 0 || access(rm, F_OK) != 0) return;
    if (shm_nattch(id) > 0) return;
    if (sysv_path(p, "shm", id, "") == 0) unlink(p);
    unlink(rm);
}

/* Removed segments whose last user ended without detaching. */
static void shm_reap_all(void) {
    char dir[PATH_MAX];
    if (sysv_dir(dir, sizeof dir) != 0) return;
    DIR *d = opendir(dir);
    if (!d) return;
    int ids[64], n = 0;
    struct dirent *e;
    while ((e = readdir(d)) && n < 64) {
        size_t l = strlen(e->d_name);
        if (!strncmp(e->d_name, "shm.", 4) && l > 7 && !strcmp(e->d_name + l - 3, ".rm")) ids[n++] = atoi(e->d_name + 4);
    }
    closedir(d);
    for (int i = 0; i < n; i++) shm_reap(ids[i]);
}

static int shm_make(int flg, long size) {
    if (size < 1) { errno = EINVAL; return -1; }
    shm_reap_all();
    int id, fd = sysv_create("shm", flg, &id);
    if (fd < 0) return -1;
    if (ftruncate(fd, (off_t)size) != 0) {
        int e = errno; close(fd);
        char p[PATH_MAX];
        if (sysv_path(p, "shm", id, "") == 0) unlink(p);
        errno = e == EFBIG ? EINVAL : e;
        return -1;
    }
    close(fd);
    return id;
}

static int shm_fits(int id, long size) {
    char p[PATH_MAX];
    struct stat st;
    return sysv_path(p, "shm", id, "") == 0 && stat(p, &st) == 0 && size <= (long)st.st_size;
}

EXPORT int shmget(key_t key, size_t size, int flg) {
    return sysv_get("shm", key, flg, shm_make, (long)size, shm_fits);
}

EXPORT void *shmat(int id, const void *addr, int flg) {
    char p[PATH_MAX];
    if (id < 0 || sysv_path(p, "shm", id, "") != 0) { errno = EINVAL; return (void *)-1; }
    int ro = flg & SHM_RDONLY;
    int fd = open(p, (ro ? O_RDONLY : O_RDWR) | O_CLOEXEC);
    if (fd < 0) { errno = errno == ENOENT ? EINVAL : errno; return (void *)-1; }
    struct stat st;
    if (fstat(fd, &st) != 0) { int e = errno; close(fd); errno = e; return (void *)-1; }
    uintptr_t want = (uintptr_t)addr;
    long page = sysconf(_SC_PAGESIZE);
    if (want && (flg & SHM_RND)) want &= ~(uintptr_t)(page - 1);
    if (want & (uintptr_t)(page - 1)) { close(fd); errno = EINVAL; return (void *)-1; }
    int mflags = MAP_SHARED;
#ifdef MAP_FIXED_NOREPLACE
    if (want) mflags |= (flg & SHM_REMAP) ? MAP_FIXED : MAP_FIXED_NOREPLACE;
#else
    if (want) mflags |= MAP_FIXED;
#endif
    int prot = PROT_READ | (ro ? 0 : PROT_WRITE) | ((flg & SHM_EXEC) ? PROT_EXEC : 0);
    void *m = mmap((void *)want, (size_t)st.st_size, prot, mflags, fd, 0);
    int e = errno;
    close(fd);
    if (m == MAP_FAILED) { errno = e == EEXIST ? EINVAL : e; return (void *)-1; }
    maps_lock();
    for (size_t i = 0; i < sizeof shm_maps / sizeof shm_maps[0]; i++)
        if (!shm_maps[i].addr) { shm_maps[i].addr = m; shm_maps[i].size = (size_t)st.st_size; shm_maps[i].id = id; break; }
    maps_unlock();
    char at[PATH_MAX], sfx[64];
    snprintf(sfx, sizeof sfx, ".at.%d.%lx", (int)getpid(), (unsigned long)(uintptr_t)m);
    if (sysv_path(at, "shm", id, sfx) == 0) { int afd = open(at, O_WRONLY | O_CREAT | O_CLOEXEC, 0600); if (afd >= 0) close(afd); }
    return m;
}

EXPORT int shmdt(const void *addr) {
    size_t size = 0;
    int id = -1;
    maps_lock();
    for (size_t i = 0; i < sizeof shm_maps / sizeof shm_maps[0]; i++)
        if (shm_maps[i].addr == addr) { size = shm_maps[i].size; id = shm_maps[i].id; shm_maps[i].addr = NULL; break; }
    maps_unlock();
    if (id < 0) { errno = EINVAL; return -1; }
    munmap((void *)addr, size);
    char at[PATH_MAX], sfx[64];
    snprintf(sfx, sizeof sfx, ".at.%d.%lx", (int)getpid(), (unsigned long)(uintptr_t)addr);
    if (sysv_path(at, "shm", id, sfx) == 0) unlink(at);
    shm_reap(id);
    return 0;
}

EXPORT int shmctl(int id, int cmd, struct shmid_ds *buf) {
    char p[PATH_MAX];
    struct stat st;
    if (cmd == IPC_INFO || cmd == SHM_INFO) {
        if (!buf) { errno = EFAULT; return -1; }
        if (cmd == IPC_INFO) {
            struct shminfo *i = (struct shminfo *)buf;
            memset(i, 0, sizeof *i);
            i->shmmax = (unsigned long)LONG_MAX; i->shmmin = 1; i->shmmni = 4096; i->shmseg = 4096; i->shmall = (unsigned long)LONG_MAX;
        } else memset(buf, 0, sizeof(struct shm_info) > sizeof *buf ? sizeof *buf : sizeof(struct shm_info));
        return 0;
    }
    if (id < 0 || sysv_path(p, "shm", id, "") != 0 || stat(p, &st) != 0) { errno = EINVAL; return -1; }
    switch (cmd) {
    case IPC_STAT: case SHM_STAT: case SHM_STAT_ANY:
        if (!buf) { errno = EFAULT; return -1; }
        memset(buf, 0, sizeof *buf);
        buf->shm_perm.uid = buf->shm_perm.cuid = st.st_uid;
        buf->shm_perm.gid = buf->shm_perm.cgid = st.st_gid;
        buf->shm_perm.mode = st.st_mode & 0777;
        { char rm[PATH_MAX]; if (sysv_path(rm, "shm", id, ".rm") == 0 && access(rm, F_OK) == 0) buf->shm_perm.mode |= SHM_DEST; }
        buf->shm_segsz = (size_t)st.st_size;
        buf->shm_atime = buf->shm_dtime = st.st_atime;
        buf->shm_ctime = st.st_ctime;
        buf->shm_nattch = (shmatt_t)shm_nattch(id);
        return cmd == IPC_STAT ? 0 : id;
    case IPC_SET:
        if (!buf) { errno = EFAULT; return -1; }
        return chmod(p, (buf->shm_perm.mode & 0777) | 0600);
    case IPC_RMID: {
        sysv_unkey("shm", id);
        char rm[PATH_MAX];
        if (sysv_path(rm, "shm", id, ".rm") == 0) { int fd = open(rm, O_WRONLY | O_CREAT | O_CLOEXEC, 0600); if (fd >= 0) close(fd); }
        shm_reap(id);
        return 0;
    }
#ifdef SHM_LOCK
    case SHM_LOCK: case SHM_UNLOCK:
        return 0;
#endif
    default:
        errno = EINVAL;
        return -1;
    }
}

/* ---- semaphores ---- */

#define SEMSET_MAGIC 0x5e3a5e70u
struct semset {
    unsigned int magic;
    int lock;          /* futex: 0 free, 1 held */
    unsigned int seq;  /* futex: bumped on every change; waiters sleep on it */
    int removed;
    int nsems;
    int pad;
    long long otime, ctime;
    struct { int val, pid, ncnt, zcnt; } s[];
};

static struct { int id; struct semset *set; size_t size; } sem_maps[64];

static long futex_(void *addr, int op, unsigned int val, const struct timespec *ts) {
    return syscall(SYS_futex, addr, op, val, ts, NULL, 0);
}
static void set_lock(struct semset *s) {
    while (__atomic_exchange_n(&s->lock, 1, __ATOMIC_ACQUIRE)) futex_(&s->lock, FUTEX_WAIT, 1, NULL);
}
static void set_unlock(struct semset *s) {
    __atomic_store_n(&s->lock, 0, __ATOMIC_RELEASE);
    futex_(&s->lock, FUTEX_WAKE, 1, NULL);
}
static void set_changed(struct semset *s) {
    __atomic_add_fetch(&s->seq, 1, __ATOMIC_RELEASE);
    futex_(&s->seq, FUTEX_WAKE, 0x7fffffff, NULL);
}

/* The set id, mapped (kept mapped for the process). */
static struct semset *sem_map(int id) {
    maps_lock();
    for (size_t i = 0; i < sizeof sem_maps / sizeof sem_maps[0]; i++)
        if (sem_maps[i].set && sem_maps[i].id == id) { struct semset *s = sem_maps[i].set; maps_unlock(); return s; }
    maps_unlock();
    char p[PATH_MAX];
    if (id < 0 || sysv_path(p, "sem", id, "") != 0) { errno = EINVAL; return NULL; }
    int fd = open(p, O_RDWR | O_CLOEXEC);
    if (fd < 0) { errno = EINVAL; return NULL; }
    struct stat st;
    if (fstat(fd, &st) != 0 || st.st_size < (off_t)sizeof(struct semset)) { close(fd); errno = EINVAL; return NULL; }
    struct semset *s = mmap(NULL, (size_t)st.st_size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    close(fd);
    if (s == MAP_FAILED || s->magic != SEMSET_MAGIC) { if (s != MAP_FAILED) munmap(s, (size_t)st.st_size); errno = EINVAL; return NULL; }
    maps_lock();
    for (size_t i = 0; i < sizeof sem_maps / sizeof sem_maps[0]; i++)
        if (!sem_maps[i].set) { sem_maps[i].id = id; sem_maps[i].set = s; sem_maps[i].size = (size_t)st.st_size; break; }
    maps_unlock();
    return s;
}

static int sem_make(int flg, long nsems) {
    if (nsems < 1 || nsems > SEMMSL_) { errno = EINVAL; return -1; }
    int id, fd = sysv_create("sem", flg, &id);
    if (fd < 0) return -1;
    size_t size = sizeof(struct semset) + (size_t)nsems * sizeof(((struct semset *)0)->s[0]);
    struct semset *s = MAP_FAILED;
    if (ftruncate(fd, (off_t)size) == 0) s = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    close(fd);
    if (s == MAP_FAILED) { char p[PATH_MAX]; int e = errno; if (sysv_path(p, "sem", id, "") == 0) unlink(p); errno = e; return -1; }
    s->nsems = (int)nsems;
    s->ctime = time(NULL);
    __atomic_store_n(&s->magic, SEMSET_MAGIC, __ATOMIC_RELEASE);
    munmap(s, size);
    return id;
}

static int sem_fits(int id, long nsems) {
    struct semset *s = sem_map(id);
    return s && nsems <= s->nsems;
}

EXPORT int semget(key_t key, int nsems, int flg) {
    if (nsems < 0) { errno = EINVAL; return -1; }
    return sysv_get("sem", key, flg, sem_make, nsems, sem_fits);
}

/* SEM_UNDO: what this process has to give back when it ends. */
static struct { int id, num, adj; } sem_undo[64];

static void undo_note(int id, int num, int op) {
    maps_lock();
    size_t free_ = (size_t)-1;
    for (size_t i = 0; i < sizeof sem_undo / sizeof sem_undo[0]; i++) {
        if (sem_undo[i].adj && sem_undo[i].id == id && sem_undo[i].num == num) { sem_undo[i].adj -= op; maps_unlock(); return; }
        if (!sem_undo[i].adj && free_ == (size_t)-1) free_ = i;
    }
    if (free_ != (size_t)-1) { sem_undo[free_].id = id; sem_undo[free_].num = num; sem_undo[free_].adj = -op; }
    maps_unlock();
}

__attribute__((destructor)) static void sem_undo_at_exit(void) {
    for (size_t i = 0; i < sizeof sem_undo / sizeof sem_undo[0]; i++) {
        if (!sem_undo[i].adj) continue;
        struct semset *s = sem_map(sem_undo[i].id);
        if (!s) continue;
        set_lock(s);
        if (!s->removed && sem_undo[i].num < s->nsems) {
            int v = s->s[sem_undo[i].num].val + sem_undo[i].adj;
            s->s[sem_undo[i].num].val = v < 0 ? 0 : v > SEMVMX_ ? SEMVMX_ : v;
        }
        set_unlock(s);
        set_changed(s);
    }
}

EXPORT int semtimedop(int id, struct sembuf *sops, size_t nsops, const struct timespec *timeout) {
    if (nsops == 0 || nsops > 500) { errno = nsops ? E2BIG : EINVAL; return -1; }
    struct semset *s = sem_map(id);
    if (!s) return -1;
    for (size_t i = 0; i < nsops; i++)
        if (sops[i].sem_num >= (unsigned)s->nsems) { errno = EFBIG; return -1; }
    for (int waited = 0;; waited = 1) {
        set_lock(s);
        if (s->removed) { set_unlock(s); errno = waited ? EIDRM : EINVAL; return -1; }
        int vals[nsops], block = -1, blocking_zero = 0;
        for (size_t i = 0; i < nsops; i++) vals[i] = s->s[sops[i].sem_num].val;
        /* Apply in order on a copy (several ops can name one semaphore). */
        for (size_t i = 0; i < nsops && block < 0; i++) {
            int v = vals[i];
            for (size_t j = 0; j < i; j++) if (sops[j].sem_num == sops[i].sem_num) v = vals[j];
            if (sops[i].sem_op > 0) {
                if (v + sops[i].sem_op > SEMVMX_) { set_unlock(s); errno = ERANGE; return -1; }
                v += sops[i].sem_op;
            } else if (sops[i].sem_op == 0) {
                if (v != 0) { block = (int)i; blocking_zero = 1; }
            } else if (v + sops[i].sem_op < 0) block = (int)i;
            else v += sops[i].sem_op;
            vals[i] = v;
            for (size_t j = 0; j < i; j++) if (sops[j].sem_num == sops[i].sem_num) vals[j] = v;
        }
        if (block < 0) {
            int pid = (int)getpid();
            for (size_t i = 0; i < nsops; i++) {
                s->s[sops[i].sem_num].val = vals[i];
                s->s[sops[i].sem_num].pid = pid;
            }
            s->otime = time(NULL);
            set_unlock(s);
            set_changed(s);
            for (size_t i = 0; i < nsops; i++)
                if ((sops[i].sem_flg & SEM_UNDO) && sops[i].sem_op) undo_note(id, sops[i].sem_num, sops[i].sem_op);
            return 0;
        }
        if (sops[block].sem_flg & IPC_NOWAIT) { set_unlock(s); errno = EAGAIN; return -1; }
        int num = sops[block].sem_num;
        if (blocking_zero) s->s[num].zcnt++; else s->s[num].ncnt++;
        unsigned int seq = __atomic_load_n(&s->seq, __ATOMIC_ACQUIRE);
        set_unlock(s);
        long r = futex_(&s->seq, FUTEX_WAIT, seq, timeout);
        int e = errno;
        set_lock(s);
        if (blocking_zero) s->s[num].zcnt--; else s->s[num].ncnt--;
        set_unlock(s);
        if (r != 0 && e == ETIMEDOUT) { errno = EAGAIN; return -1; }
        if (r != 0 && e == EINTR) { errno = EINTR; return -1; }
    }
}

EXPORT int semop(int id, struct sembuf *sops, size_t nsops) { return semtimedop(id, sops, nsops, NULL); }

union ddmask_semun { int val; struct semid_ds *buf; unsigned short *array; struct seminfo *info; };

EXPORT int semctl(int id, int num, int cmd, ...) {
    union ddmask_semun arg = { 0 };
    va_list ap;
    va_start(ap, cmd);
    switch (cmd) {
    case SETVAL: case SETALL: case GETALL: case IPC_STAT: case IPC_SET: case SEM_STAT: case SEM_STAT_ANY:
    case IPC_INFO: case SEM_INFO:
        arg = va_arg(ap, union ddmask_semun);
        break;
    }
    va_end(ap);
    if (cmd == IPC_INFO || cmd == SEM_INFO) {
        if (!arg.info) { errno = EFAULT; return -1; }
        memset(arg.info, 0, sizeof *arg.info);
        arg.info->semmni = 32000; arg.info->semmsl = SEMMSL_; arg.info->semmns = 1024000000;
        arg.info->semopm = 500; arg.info->semvmx = SEMVMX_; arg.info->semmap = 32000; arg.info->semmnu = 32000; arg.info->semume = 500;
        return 0;
    }
    struct semset *s = sem_map(id);
    if (!s) return -1;
    char p[PATH_MAX];
    struct stat st;
    if (sysv_path(p, "sem", id, "") != 0) return -1;
    int r = 0;
    set_lock(s);
    if (s->removed) { set_unlock(s); errno = EINVAL; return -1; }
    int one = cmd == GETVAL || cmd == SETVAL || cmd == GETPID || cmd == GETNCNT || cmd == GETZCNT;
    if (one && (num < 0 || num >= s->nsems)) { set_unlock(s); errno = EINVAL; return -1; }
    switch (cmd) {
    case GETVAL: r = s->s[num].val; break;
    case GETPID: r = s->s[num].pid; break;
    case GETNCNT: r = s->s[num].ncnt; break;
    case GETZCNT: r = s->s[num].zcnt; break;
    case SETVAL:
        if (arg.val < 0 || arg.val > SEMVMX_) { r = -1; errno = ERANGE; break; }
        s->s[num].val = arg.val; s->s[num].pid = (int)getpid(); s->ctime = time(NULL);
        break;
    case GETALL:
        if (!arg.array) { r = -1; errno = EFAULT; break; }
        for (int i = 0; i < s->nsems; i++) arg.array[i] = (unsigned short)s->s[i].val;
        break;
    case SETALL:
        if (!arg.array) { r = -1; errno = EFAULT; break; }
        for (int i = 0; i < s->nsems; i++) {
            if (arg.array[i] > SEMVMX_) { r = -1; errno = ERANGE; break; }
            s->s[i].val = arg.array[i]; s->s[i].pid = (int)getpid();
        }
        s->ctime = time(NULL);
        break;
    case IPC_STAT: case SEM_STAT: case SEM_STAT_ANY:
        if (!arg.buf) { r = -1; errno = EFAULT; break; }
        if (stat(p, &st) != 0) { r = -1; break; }
        memset(arg.buf, 0, sizeof *arg.buf);
        arg.buf->sem_perm.uid = arg.buf->sem_perm.cuid = st.st_uid;
        arg.buf->sem_perm.gid = arg.buf->sem_perm.cgid = st.st_gid;
        arg.buf->sem_perm.mode = st.st_mode & 0777;
        arg.buf->sem_nsems = (unsigned short)s->nsems;
        arg.buf->sem_otime = (time_t)s->otime;
        arg.buf->sem_ctime = (time_t)s->ctime;
        if (cmd != IPC_STAT) r = id;
        break;
    case IPC_SET:
        if (!arg.buf) { r = -1; errno = EFAULT; break; }
        r = chmod(p, (arg.buf->sem_perm.mode & 0777) | 0600);
        s->ctime = time(NULL);
        break;
    case IPC_RMID:
        s->removed = 1;
        sysv_unkey("sem", id);
        unlink(p);
        break;
    default:
        r = -1; errno = EINVAL;
    }
    int e = errno;
    set_unlock(s);
    if (cmd == SETVAL || cmd == SETALL || cmd == IPC_RMID) set_changed(s);
    errno = e;
    return r;
}

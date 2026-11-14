/* System V shared memory and semaphores the way X11's MIT-SHM and Xorg use
 * them, for compat.sh: a private segment shared with a child by id, removed
 * while attached, a keyed one, and a semaphore a child waits on. */
#define _GNU_SOURCE
#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <sys/ipc.h>
#include <sys/sem.h>
#include <sys/shm.h>
#include <sys/wait.h>
#include <unistd.h>

union semun { int val; struct semid_ds *buf; unsigned short *array; };

static const char *err(int r) { return r == -1 ? strerror(errno) : "ok"; }

int main(void) {
    /* Xorg's CheckForShmSyscall: an invalid id is EINVAL, not ENOSYS. */
    struct shmid_ds ds;
    printf("probe=%s\n", err(shmctl(-1, IPC_STAT, &ds)));
    int id = shmget(IPC_PRIVATE, 100000, IPC_CREAT | 0600);
    if (id < 0) { printf("shmget=%s\n", strerror(errno)); return 1; }
    char *m = shmat(id, NULL, 0);
    if (m == (void *)-1) { printf("shmat=%s\n", strerror(errno)); return 1; }
    strcpy(m, "from-parent");
    fflush(stdout);
    pid_t c = fork();
    if (c == 0) {   /* the X server: attaches by id, read-only */
        char *r = shmat(id, NULL, SHM_RDONLY);
        if (r == (void *)-1) { printf("child-shmat=%s\n", strerror(errno)); _exit(1); }
        printf("child-sees=%s\n", r);
        shmctl(id, IPC_STAT, &ds);
        printf("child-nattch=%d\n", (int)ds.shm_nattch);
        fflush(stdout);
        sleep(1);
        printf("child-after-rmid=%s\n", r);
        fflush(stdout);
        _exit(shmdt(r) != 0);
    }
    usleep(300000);
    printf("rmid=%s\n", err(shmctl(id, IPC_RMID, NULL)));
    strcpy(m, "changed");
    waitpid(c, NULL, 0);
    shmctl(id, IPC_STAT, &ds);
    printf("size=%d mode=%o dest=%s\n", (int)ds.shm_segsz, ds.shm_perm.mode & 0777, ds.shm_perm.mode & SHM_DEST ? "yes" : "no");
    printf("shmdt=%s\n", err(shmdt(m)));
    printf("gone=%s\n", err(shmctl(id, IPC_STAT, &ds)));
    printf("shmdt-again=%s\n", err(shmdt(m)));

    key_t key = 0x0dd5;
    int k = shmget(key, 4096, IPC_CREAT | IPC_EXCL | 0644);
    printf("key=%s\n", err(k));
    printf("key-same=%s\n", shmget(key, 1000, 0) == k ? "yes" : "no");
    printf("key-excl=%s\n", err(shmget(key, 4096, IPC_CREAT | IPC_EXCL | 0644)));
    printf("key-bigger=%s\n", err(shmget(key, 8192, 0)));
    shmctl(k, IPC_RMID, NULL);
    printf("key-after-rmid=%s\n", err(shmget(key, 4096, 0)));

    int s = semget(IPC_PRIVATE, 2, IPC_CREAT | 0600);
    printf("semget=%s\n", err(s));
    union semun a = { .val = 0 };
    semctl(s, 0, SETVAL, a);
    struct sembuf nowait = { 0, -1, IPC_NOWAIT };
    printf("nowait=%s\n", err(semop(s, &nowait, 1)));
    fflush(stdout);
    c = fork();
    if (c == 0) {
        struct sembuf take = { 0, -1, 0 };
        int r = semop(s, &take, 1);
        printf("child-took=%s\n", err(r));
        fflush(stdout);
        _exit(0);
    }
    usleep(300000);
    printf("ncnt=%d\n", semctl(s, 0, GETNCNT));
    struct sembuf give[2] = { { 0, 1, 0 }, { 1, 5, 0 } };
    fflush(stdout);
    printf("give=%s\n", err(semop(s, give, 2)));
    fflush(stdout);
    waitpid(c, NULL, 0);
    unsigned short all[2];
    union semun g = { .array = all };
    semctl(s, 0, GETALL, g);
    printf("vals=%d,%d\n", all[0], all[1]);
    struct timespec ts = { 0, 100000000 };
    struct sembuf wait0 = { 1, 0, 0 };
    printf("timed=%s\n", err(semtimedop(s, &wait0, 1, &ts)));
    printf("sem-rmid=%s\n", err(semctl(s, 0, IPC_RMID)));
    printf("sem-gone=%s\n", err(semctl(s, 0, GETVAL)));
    return 0;
}

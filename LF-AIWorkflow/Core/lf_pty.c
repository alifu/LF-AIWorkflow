#include "lf_pty.h"

#include <crt_externs.h>
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <sys/event.h>
#include <sys/ioctl.h>
#include <sys/time.h>
#include <sys/wait.h>
#include <termios.h>
#include <unistd.h>
#include <util.h>

#define LF_PTY_DEFAULT_COLS 120
#define LF_PTY_DEFAULT_ROWS 40
#define LF_PTY_DESTROY_GRACE_MS 2000
#define LF_PTY_VEOF_BYTE 0x04
#define LF_PTY_EXEC_WAIT_MS 2000

struct lf_pty {
    int master;
    int stdin_fd;    /* write end of the stdin pipe; -1 in tty mode or once closed (EOF) */
    int stdin_pipe;  /* pipe mode flag; stays set after EOF so writes fail with EPIPE */
    int kq;
    pid_t pid;
    int exit_seen;   /* NOTE_EXIT observed */
    int eof_seen;    /* lf_pty_read returned 0 (EOF/EIO) */
    int read_unwatched; /* EVFILT_READ deleted after EOF */
    int reaped;
    int status;
};

/// Complexity: O(1) time, O(1) space
static int normalize_status(int raw) {
    if (WIFEXITED(raw)) return WEXITSTATUS(raw);
    if (WIFSIGNALED(raw)) return 128 + WTERMSIG(raw);
    return raw;
}

/// Complexity: O(1) time, O(1) space
static int set_cloexec_nonblock(int fd, int nonblock) {
    int fl = fcntl(fd, F_GETFD);
    if (fl < 0 || fcntl(fd, F_SETFD, fl | FD_CLOEXEC) < 0) return -1;
    if (nonblock) {
        int sf = fcntl(fd, F_GETFL);
        if (sf < 0 || fcntl(fd, F_SETFL, sf | O_NONBLOCK) < 0) return -1;
    }
    return 0;
}

/// Terminal settings: no echo, canonical input, ONLCR output.
/// Complexity: O(1) time, O(1) space
static void make_termios(struct termios *t) {
    memset(t, 0, sizeof *t);
    t->c_iflag = ICRNL | IXON | IMAXBEL;
    t->c_oflag = OPOST | ONLCR;
    t->c_cflag = CS8 | CREAD | HUPCL;
    t->c_lflag = ICANON | ISIG | IEXTEN;
    for (int i = 0; i < NCCS; i++) t->c_cc[i] = _POSIX_VDISABLE;
    t->c_cc[VEOF] = LF_PTY_VEOF_BYTE;
    t->c_cc[VERASE] = 0x7f;
    t->c_cc[VINTR] = 0x03;
    t->c_cc[VKILL] = 0x15;
    t->c_cc[VQUIT] = 0x1c;
    t->c_cc[VSUSP] = 0x1a;
    t->c_cc[VMIN] = 1;
    t->c_cc[VTIME] = 0;
    cfsetspeed(t, B38400);
}

/// Registers kqueue filters. Returns 0; marks exit_seen if the child is already gone.
/// Complexity: O(1) time, O(1) space
static int register_events(lf_pty *p) {
    struct kevent ch[2];
    EV_SET(&ch[0], (uintptr_t)p->master, EVFILT_READ, EV_ADD, 0, 0, NULL);
    EV_SET(&ch[1], (uintptr_t)p->pid, EVFILT_PROC, EV_ADD | EV_CLEAR, NOTE_EXIT, 0, NULL);
    if (kevent(p->kq, ch, 2, NULL, 0, NULL) < 0) {
        if (errno != ESRCH) return -1;
        p->exit_seen = 1;
        if (kevent(p->kq, ch, 1, NULL, 0, NULL) < 0) return -1;
    }
    return 0;
}

/// Reads the exec-error pipe. Returns the child's errno, or 0 if exec succeeded.
/// The pipe is polled with a bounded timeout: FD_CLOEXEC is set after pipe(), so a
/// concurrent fork in another thread can inherit errpipe[1] and keep it open forever.
/// On timeout the child counts as exec'd only if it is still alive.
/// Known remaining race (TD-014): the same window exists for the master fd after forkpty().
/// Complexity: O(1) time, O(1) space
static int read_exec_error(int fd, pid_t pid) {
    struct pollfd pfd = { fd, POLLIN, 0 };
    int r;
    do { r = poll(&pfd, 1, LF_PTY_EXEC_WAIT_MS); } while (r < 0 && errno == EINTR);
    if (r == 0) {
        int st;
        return waitpid(pid, &st, WNOHANG) == 0 ? 0 : EIO;
    }
    if (r < 0) return errno;
    int err = 0;
    ssize_t n;
    do { n = read(fd, &err, sizeof err); } while (n < 0 && errno == EINTR);
    return n == (ssize_t)sizeof err ? err : 0;
}

/// Restores default dispositions and an empty mask in the child (the host may ignore
/// SIGTERM/SIGPIPE, and ignored signals survive exec). Async-signal-safe.
/// Complexity: O(1) time, O(1) space
static void reset_child_signals(void) {
    static const int sigs[] = { SIGHUP, SIGINT, SIGQUIT, SIGTERM, SIGPIPE, SIGCHLD };
    for (size_t i = 0; i < sizeof sigs / sizeof sigs[0]; i++) signal(sigs[i], SIG_DFL);
    sigset_t empty;
    sigemptyset(&empty);
    sigprocmask(SIG_SETMASK, &empty, NULL);
}

/// Creates the child-stdin pipe: both ends close-on-exec, write end nonblocking and
/// SIGPIPE-free (write fails with EPIPE instead of killing the host), read end above fd 2
/// so forkpty's slave cannot collide with it when the host closed stdio.
/// Complexity: O(1) time, O(1) space
static int make_stdin_pipe(int fds[2]) {
    if (pipe(fds) < 0) return -1;
    if (fds[0] <= STDERR_FILENO) {
        int moved = fcntl(fds[0], F_DUPFD_CLOEXEC, STDERR_FILENO + 1);
        if (moved < 0) return -1;
        close(fds[0]);
        fds[0] = moved;
    }
    if (set_cloexec_nonblock(fds[0], 0) < 0 || set_cloexec_nonblock(fds[1], 1) < 0 ||
        fcntl(fds[1], F_SETNOSIGPIPE, 1) < 0) {
        return -1;
    }
    return 0;
}

/// Complexity: O(argc + envc) time, O(1) space
lf_pty *lf_pty_spawn(const lf_pty_options *opts) {
    if (opts == NULL || opts->argv == NULL || opts->argv[0] == NULL) {
        errno = EINVAL;
        return NULL;
    }
    lf_pty *p = calloc(1, sizeof *p);
    if (p == NULL) { errno = ENOMEM; return NULL; }
    p->master = -1;
    p->stdin_fd = -1;
    p->kq = -1;
    p->pid = -1;

    int errpipe[2] = { -1, -1 };
    int inpipe[2] = { -1, -1 };
    if (opts->stdin_pipe && make_stdin_pipe(inpipe) < 0) goto fail;
    p->stdin_pipe = opts->stdin_pipe != 0;
    if (pipe(errpipe) < 0 || set_cloexec_nonblock(errpipe[0], 0) < 0 || set_cloexec_nonblock(errpipe[1], 0) < 0) {
        goto fail;
    }

    struct termios term;
    make_termios(&term);
    struct winsize ws;
    memset(&ws, 0, sizeof ws);
    ws.ws_col = opts->cols ? opts->cols : LF_PTY_DEFAULT_COLS;
    ws.ws_row = opts->rows ? opts->rows : LF_PTY_DEFAULT_ROWS;

    char *const *envp = opts->envp ? (char *const *)opts->envp : *_NSGetEnviron();
    char *const *argv = (char *const *)opts->argv;
    const char *cwd = opts->cwd;

    pid_t pid = forkpty(&p->master, NULL, &term, &ws);
    if (pid < 0) goto fail;
    if (pid == 0) {
        /* Child: async-signal-safe calls only. */
        int e;
        reset_child_signals();
        if (inpipe[0] >= 0 && dup2(inpipe[0], STDIN_FILENO) < 0) {
            e = errno;
            ssize_t w0 = write(errpipe[1], &e, sizeof e);
            (void)w0;
            _exit(127);
        }
        if (cwd != NULL && chdir(cwd) < 0) {
            e = errno;
        } else {
            execve(argv[0], argv, envp);
            e = errno;
        }
        ssize_t w = write(errpipe[1], &e, sizeof e);
        (void)w;
        _exit(127);
    }
    p->pid = pid;
    close(errpipe[1]);
    errpipe[1] = -1;
    if (inpipe[0] >= 0) { close(inpipe[0]); inpipe[0] = -1; }
    p->stdin_fd = inpipe[1];
    inpipe[1] = -1;

    int child_errno = read_exec_error(errpipe[0], pid);
    close(errpipe[0]);
    errpipe[0] = -1;
    if (child_errno != 0) {
        int status;
        while (waitpid(pid, &status, 0) < 0 && errno == EINTR) {}
        p->pid = -1;
        errno = child_errno;
        goto fail;
    }

    p->kq = kqueue();
    if (p->kq < 0 || set_cloexec_nonblock(p->master, 1) < 0 || set_cloexec_nonblock(p->kq, 0) < 0 ||
        register_events(p) < 0) {
        int saved = errno;
        lf_pty_terminate(p, 0);
        errno = saved;
        goto fail;
    }
    return p;

fail:;
    int saved = errno;
    if (errpipe[0] >= 0) close(errpipe[0]);
    if (errpipe[1] >= 0) close(errpipe[1]);
    if (inpipe[0] >= 0) close(inpipe[0]);
    if (inpipe[1] >= 0) close(inpipe[1]);
    if (p->stdin_fd >= 0) close(p->stdin_fd);
    if (p->master >= 0) close(p->master);
    if (p->kq >= 0) close(p->kq);
    free(p);
    errno = saved;
    return NULL;
}

/// Complexity: O(n) time, O(1) space
long lf_pty_write(lf_pty *p, const void *buf, size_t len) {
    if (p == NULL) { errno = EINVAL; return -1; }
    if (len == 0) return 0;
    ssize_t n;
    if (p->stdin_pipe && p->stdin_fd < 0) { errno = EPIPE; return -1; }
    int fd = p->stdin_pipe ? p->stdin_fd : p->master;
    do { n = write(fd, buf, len); } while (n < 0 && errno == EINTR);
    return (long)n;
}

/// Complexity: O(n) time, O(1) space
long lf_pty_read(lf_pty *p, void *buf, size_t cap) {
    if (p == NULL) { errno = EINVAL; return -1; }
    if (cap == 0) return 0;
    ssize_t n;
    do { n = read(p->master, buf, cap); } while (n < 0 && errno == EINTR);
    if (n < 0 && errno == EIO) n = 0;
    if (n == 0) p->eof_seen = 1;
    return (long)n;
}

/// Complexity: O(1) time, O(1) space
int lf_pty_send_eof(lf_pty *p) {
    if (p == NULL) { errno = EINVAL; return -1; }
    if (p->stdin_pipe) {
        if (p->stdin_fd < 0) return 0;
        int r = close(p->stdin_fd);
        p->stdin_fd = -1;
        return r;
    }
    unsigned char eof = LF_PTY_VEOF_BYTE;
    ssize_t n;
    do { n = write(p->master, &eof, 1); } while (n < 0 && errno == EINTR);
    return n == 1 ? 0 : -1;
}

/// Complexity: O(1) time, O(1) space
int lf_pty_wait_event(lf_pty *p, int timeout_ms) {
    if (p == NULL) { errno = EINVAL; return -1; }
    struct timespec ts, *tsp = NULL;
    if (p->exit_seen) timeout_ms = 0;
    if (timeout_ms >= 0) {
        ts.tv_sec = timeout_ms / 1000;
        ts.tv_nsec = (long)(timeout_ms % 1000) * 1000000L;
        tsp = &ts;
    }
    if (p->eof_seen && !p->read_unwatched) {
        /* EOF is level-triggered: stop watching READ so later calls only report exit or time out. */
        struct kevent del;
        EV_SET(&del, (uintptr_t)p->master, EVFILT_READ, EV_DELETE, 0, 0, NULL);
        (void)kevent(p->kq, &del, 1, NULL, 0, NULL);
        p->read_unwatched = 1;
    }
    struct kevent ev[2];
    int n;
    do { n = kevent(p->kq, NULL, 0, ev, 2, tsp); } while (n < 0 && errno == EINTR);
    if (n < 0) return -1;
    int mask = 0;
    for (int i = 0; i < n; i++) {
        if (ev[i].filter == EVFILT_READ) mask |= LF_PTY_READABLE;
        else if (ev[i].filter == EVFILT_PROC && (ev[i].fflags & NOTE_EXIT)) p->exit_seen = 1;
    }
    if (p->exit_seen) mask |= LF_PTY_EXITED;
    return mask;
}

/// Waits up to ms for the child to exit using a private kqueue. Returns 1 if exited.
/// Complexity: O(1) time, O(1) space
static int wait_exit(lf_pty *p, int ms) {
    if (p->exit_seen) return 1;
    int kq = kqueue();
    if (kq < 0) return 0;
    struct kevent ch, ev;
    EV_SET(&ch, (uintptr_t)p->pid, EVFILT_PROC, EV_ADD | EV_ONESHOT, NOTE_EXIT, 0, NULL);
    struct timespec ts = { ms / 1000, (long)(ms % 1000) * 1000000L };
    int n;
    do { n = kevent(kq, &ch, 1, &ev, 1, &ts); } while (n < 0 && errno == EINTR);
    int exited = (n > 0) || (n < 0 && errno == ESRCH);
    close(kq);
    if (exited) p->exit_seen = 1;
    return exited;
}

/// Complexity: O(1) time, O(1) space
int lf_pty_wait(lf_pty *p, int *exit_status) {
    if (p == NULL) { errno = EINVAL; return -1; }
    if (!p->reaped) {
        int raw;
        pid_t r;
        do { r = waitpid(p->pid, &raw, 0); } while (r < 0 && errno == EINTR);
        if (r < 0) return -1;
        p->status = normalize_status(raw);
        p->reaped = 1;
    }
    if (exit_status != NULL) *exit_status = p->status;
    return 0;
}

/// Complexity: O(1) time, O(1) space
int lf_pty_terminate(lf_pty *p, int grace_ms) {
    if (p == NULL) { errno = EINVAL; return -1; }
    if (!p->reaped) {
        kill(-p->pid, SIGTERM);
        if (!wait_exit(p, grace_ms < 0 ? 0 : grace_ms)) kill(-p->pid, SIGKILL);
        else kill(-p->pid, SIGKILL);   /* sweep stragglers in the group; leader is already dead */
    }
    int status = 0;
    if (lf_pty_wait(p, &status) < 0) return -1;
    return status;
}

/// Complexity: O(1) time, O(1) space
int lf_pty_pid(const lf_pty *p) {
    return p ? (int)p->pid : -1;
}

/// Complexity: O(1) time, O(1) space
void lf_pty_destroy(lf_pty *p) {
    if (p == NULL) return;
    if (!p->reaped && p->pid > 0) lf_pty_terminate(p, LF_PTY_DESTROY_GRACE_MS);
    if (p->stdin_fd >= 0) close(p->stdin_fd);
    if (p->master >= 0) close(p->master);
    if (p->kq >= 0) close(p->kq);
    free(p);
}

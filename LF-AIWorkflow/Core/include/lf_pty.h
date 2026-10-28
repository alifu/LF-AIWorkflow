#ifndef LF_PTY_H
#define LF_PTY_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Child process under a pseudo-terminal; owns master fd, child pid and a kqueue fd.
/// Not thread-safe. The stdin pipe is created with F_SETNOSIGPIPE, so a write after the child
/// closed its end fails with EPIPE instead of raising SIGPIPE (no host signal setup needed).
typedef struct lf_pty lf_pty;

typedef struct {
    const char *const *argv;   /* argv[0] = absolute path; NULL-terminated; required */
    const char *const *envp;   /* NULL-terminated; NULL inherits the current environment */
    const char *cwd;           /* NULL inherits */
    unsigned short cols, rows; /* 0 selects 120 x 40 */
    int stdin_pipe;            /* nonzero: child stdin is a pipe (raw bytes, no line limit,
                                  no tty interpretation); stdout/stderr stay on the pty */
} lf_pty_options;

enum { LF_PTY_READABLE = 1, LF_PTY_EXITED = 2 };

/// Spawns the child. NULL + errno on failure (EINVAL bad options; exec failure such as
/// ENOENT is reported through a close-on-exec pipe).
/// Complexity: O(argc + envc) time, O(1) space
lf_pty *lf_pty_spawn(const lf_pty_options *opts);

/// Nonblocking write to the child's stdin. May be short; -1 + EAGAIN when full. In pipe mode,
/// -1 + EPIPE once the child closed its stdin or after lf_pty_send_eof (never SIGPIPE).
/// Complexity: O(n) time, O(1) space
long lf_pty_write(lf_pty *p, const void *buf, size_t len);

/// Nonblocking read. >0 bytes, 0 at EOF (EIO after child exit is mapped to 0), -1 + EAGAIN.
/// Complexity: O(n) time, O(1) space
long lf_pty_read(lf_pty *p, void *buf, size_t cap);

/// Stdin EOF: closes the stdin pipe in pipe mode (idempotent: later calls return 0), else
/// writes VEOF (^D) for a canonical tty.
/// Complexity: O(1) time, O(1) space
int lf_pty_send_eof(lf_pty *p);

/// Waits via kqueue for output and/or child exit. Returns an LF_PTY_* mask, 0 on timeout,
/// -1 on error. timeout_ms < 0 waits forever.
/// Complexity: O(1) time, O(1) space; no busy wait
int lf_pty_wait_event(lf_pty *p, int timeout_ms);

/// SIGTERM to the process group, wait up to grace_ms, then SIGKILL; reaps. Returns the
/// normalized exit status (exit code, or 128 + signal), or -1 + errno.
/// Complexity: O(1) time, O(1) space
int lf_pty_terminate(lf_pty *p, int grace_ms);

/// Blocking waitpid(pid) once; idempotent after reaping. Returns 0 and the normalized status.
/// Complexity: O(1) time, O(1) space
int lf_pty_wait(lf_pty *p, int *exit_status);

/// Child pid, or -1 for NULL.
/// Complexity: O(1) time, O(1) space
int lf_pty_pid(const lf_pty *p);

/// Terminates a still-running child (2000 ms grace), closes fds, frees. NULL-safe.
/// Complexity: O(1) time, O(1) space
void lf_pty_destroy(lf_pty *p);

#ifdef __cplusplus
}
#endif

#endif /* LF_PTY_H */

#include <errno.h>
#include "include/LFCore.h"

/// Complexity: O(1) time, O(1) space
int lf_pty_spawn(const char *const *argv, int *master_fd, int *child_pid) {
    (void)argv; (void)master_fd; (void)child_pid;
    errno = ENOSYS;
    return -1;
}

/// Complexity: O(n) time, O(1) space, where n is len
long lf_pty_write(int master_fd, const void *buffer, unsigned long len) {
    (void)master_fd; (void)buffer; (void)len;
    errno = ENOSYS;
    return -1;
}

/// Complexity: O(n) time, O(1) space, where n is len
long lf_pty_read(int master_fd, void *buffer, unsigned long len) {
    (void)master_fd; (void)buffer; (void)len;
    errno = ENOSYS;
    return -1;
}

/// Complexity: O(1) time, O(1) space
int lf_pty_kill(int child_pid, int signal_number) {
    (void)child_pid; (void)signal_number;
    errno = ENOSYS;
    return -1;
}

/// Complexity: O(1) time, O(1) space
int lf_pty_wait(int child_pid, int *exit_status) {
    (void)child_pid; (void)exit_status;
    errno = ENOSYS;
    return -1;
}

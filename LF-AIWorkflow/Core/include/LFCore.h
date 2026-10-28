//
//  LFCore.h
//  LF-AIWorkflow
//
//  Public C API of the LFCore module. Stubs only until Phase 2.
//

#ifndef LFCORE_H
#define LFCORE_H

#ifdef __cplusplus
extern "C" {
#endif

/// Returns the core version tag as a static string.
/// Complexity: O(1) time, O(1) space
const char *lf_core_version(void);

/// Spawns a child process under a pseudo-terminal (stub: always fails with ENOSYS).
/// Complexity: O(1) time, O(1) space
int lf_pty_spawn(const char *const *argv, int *master_fd, int *child_pid);

/// Writes bytes to the PTY master (stub: always fails with ENOSYS).
/// Complexity: O(n) time, O(1) space, where n is len
long lf_pty_write(int master_fd, const void *buffer, unsigned long len);

/// Reads bytes from the PTY master (stub: always fails with ENOSYS).
/// Complexity: O(n) time, O(1) space, where n is len
long lf_pty_read(int master_fd, void *buffer, unsigned long len);

/// Sends a signal to the child process (stub: always fails with ENOSYS).
/// Complexity: O(1) time, O(1) space
int lf_pty_kill(int child_pid, int signal_number);

/// Reaps the child process and returns its exit status (stub: always fails with ENOSYS).
/// Complexity: O(1) time, O(1) space
int lf_pty_wait(int child_pid, int *exit_status);

/// Fills a ring buffer slot (stub: always fails with ENOSYS).
/// Complexity: O(1) time, O(1) space
int lf_ringbuf_stub(void);

/// Feeds a chunk into the NDJSON line framer (stub: always fails with ENOSYS).
/// Complexity: O(1) time, O(1) space
int lf_ndjson_stub(void);

/// Walks a folder tree for skill and document files (stub: always fails with ENOSYS).
/// Complexity: O(1) time, O(1) space
int lf_scan_stub(void);

/// Estimates the token count of a text (stub: always fails with ENOSYS).
/// Complexity: O(1) time, O(1) space
int lf_tokens_stub(void);

/// Extracts error lines from build or test output (stub: always fails with ENOSYS).
/// Complexity: O(1) time, O(1) space
int lf_errscan_stub(void);

/// Collapses whitespace and removes boilerplate (stub: always fails with ENOSYS).
/// Complexity: O(1) time, O(1) space
int lf_textclean_stub(void);

/// Ranks text chunks by BM25 relevance (stub: always fails with ENOSYS).
/// Complexity: O(1) time, O(1) space
int lf_bm25_stub(void);

#ifdef __cplusplus
}
#endif

#endif /* LFCORE_H */

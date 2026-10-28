#ifndef LF_NDJSON_H
#define LF_NDJSON_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Default maximum line length (16 MiB).
#define LF_NDJSON_DEFAULT_MAX_LINE ((size_t)16 * 1024 * 1024)

/// Incremental newline-delimited framer; opaque.
typedef struct lf_ndjson lf_ndjson;

/// Line callback. `line` excludes '\n' and a trailing '\r', is NOT NUL-terminated and is
/// borrowed (valid only during the call). Return non-zero to stop.
typedef int (*lf_ndjson_line_cb)(const char *line, size_t len, void *ctx);

/// Creates a framer. max_line 0 selects LF_NDJSON_DEFAULT_MAX_LINE. NULL + ENOMEM on failure.
/// Complexity: O(1) time, O(1) space
lf_ndjson *lf_ndjson_create(size_t max_line);

/// Frees the framer. NULL-safe.
/// Complexity: O(1) time, O(1) space
void lf_ndjson_destroy(lf_ndjson *fr);

/// Feeds a chunk; emits every complete non-blank line. Returns lines emitted, or -1 + errno.
/// If the callback returns non-zero the remaining input is kept for the next call.
/// Complexity: O(k) amortized time, O(L) space, k = chunk bytes, L = longest pending line
long lf_ndjson_feed(lf_ndjson *fr, const void *data, size_t len, lf_ndjson_line_cb cb, void *ctx);

/// Flushes a final unterminated line and resets the framer. Returns lines emitted, or -1.
/// Complexity: O(L) time, O(L) space
long lf_ndjson_finish(lf_ndjson *fr, lf_ndjson_line_cb cb, void *ctx);

/// Number of lines dropped for exceeding max_line.
/// Complexity: O(1) time, O(1) space
uint64_t lf_ndjson_oversize_count(const lf_ndjson *fr);

/// Finds a string value at a dotted object-key path (e.g. "message.usage.model").
/// Returns 0 and sets out/out_len to the raw bytes between the quotes (escapes not decoded,
/// points into `line`). Returns -1 with ENOENT (missing) or EINVAL (wrong type/malformed).
/// Complexity: O(line) time, O(1) space
int lf_ndjson_get_string(const char *line, size_t len, const char *path, const char **out, size_t *out_len);

/// Finds an integer value at a dotted object-key path. Returns 0 on success; -1 with ENOENT,
/// EINVAL (wrong type/malformed) or ERANGE (overflow).
/// Complexity: O(line) time, O(1) space
int lf_ndjson_get_int64(const char *line, size_t len, const char *path, int64_t *out);

#ifdef __cplusplus
}
#endif

#endif /* LF_NDJSON_H */

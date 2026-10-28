#ifndef LF_SCAN_H
#define LF_SCAN_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define LF_FNV1A64_OFFSET 0xcbf29ce484222325ULL

/// FNV-1a 64-bit hash, chainable through `seed` (start with LF_FNV1A64_OFFSET).
/// (NULL, 0) returns seed.
/// Complexity: O(n) time, O(1) space
uint64_t lf_fnv1a64(const void *data, size_t len, uint64_t seed);

/// Streaming FNV-1a of a file using a 64 KiB heap buffer. 0 ok, -1 + errno.
/// Complexity: O(size) time, O(1) space (fixed 64 KiB)
int lf_fnv1a64_file(const char *path, uint64_t *out);

/// One regular file found by the walk. `path` is borrowed (valid during the callback only).
typedef struct {
    const char *path;
    size_t path_len;
    uint64_t size;
    uint64_t hash;
    int hashed;
    int depth;
} lf_scan_entry;

/// Callback per file; non-zero stops the walk.
typedef int (*lf_scan_cb)(const lf_scan_entry *e, void *ctx);

typedef struct {
    int max_depth;                  /* root's children = depth 1; < 0 unlimited */
    const char *const *extensions;  /* without dot, case-insensitive; NULL = all regular files */
    size_t extension_count;
    uint64_t max_hash_bytes;        /* larger files get hashed = 0; 0 hashes all */
    int include_hidden;             /* 0 skips dot-files and dot-directories */
} lf_scan_options;

/// Walks `root` (symlinks are never followed below the root). Returns entries reported,
/// or -1 + errno (e.g. ENOENT for a missing root). Unreadable directories are skipped.
/// Complexity: O(F + sum of sizes) time, O(depth) space plus one 64 KiB buffer
long lf_scan_walk(const char *root, const lf_scan_options *opts, lf_scan_cb cb, void *ctx);

#ifdef __cplusplus
}
#endif

#endif /* LF_SCAN_H */

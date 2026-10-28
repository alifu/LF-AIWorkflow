#ifndef LF_TOKENS_H
#define LF_TOKENS_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Estimates the number of Claude tokens in `len` bytes of UTF-8 text with a single-pass
/// heuristic (no allocation, no tables). `(NULL, 0)` returns 0. Invalid or truncated UTF-8
/// counts 1 per byte and never reads past `len`. The pointer is borrowed for the call.
/// Complexity: O(n) time, O(1) space
size_t lf_tokens_estimate(const void *text, size_t len);

#ifdef __cplusplus
}
#endif

#endif /* LF_TOKENS_H */

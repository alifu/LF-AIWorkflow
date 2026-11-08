#ifndef LF_TEXTCLEAN_H
#define LF_TEXTCLEAN_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// A borrowed byte range. `ptr` may be NULL only when `len` is 0.
typedef struct {
    const char *ptr;
    size_t len;
} lf_text_span;

/// Normalizes whitespace in place: CR removed, control bytes except \n and \t dropped,
/// runs of space/tab become one space, trailing spaces on a line trimmed, 3+ newlines become 2.
/// Bytes >= 0x80 are kept untouched. Returns the new length (never larger than `len`).
/// Complexity: O(n) time, O(1) space
size_t lf_text_collapse_ws(char *buf, size_t len);

/// FNV-1a 64-bit hash of `n` bytes (`p` may be NULL when n is 0).
/// Complexity: O(n) time, O(1) space
uint64_t lf_text_hash(const void *p, size_t n);

/// Removes lines shared by many pages. A non-blank line counts once per page; when
/// n >= min_pages, lines present in >= ceil(n/2) pages are dropped (with their newline).
/// Blank (whitespace-only) lines are never removed. Page i is written to outs[i]
/// (out_caps[i] >= pages[i].len) and its length to out_lens[i]. Returns the number of removed
/// line occurrences; -1 + EINVAL on bad arguments, -1 + ENOMEM on allocation failure.
/// Complexity: O(total bytes) expected time, O(total lines) space
long lf_textclean_boilerplate(const lf_text_span *pages, size_t n, size_t min_pages,
                              char **outs, const size_t *out_caps, size_t *out_lens);

/// Flags exact duplicate pages: dup_of[i] = index of the first identical earlier page, else -1.
/// Returns 0; -1 + EINVAL on bad arguments, -1 + ENOMEM on allocation failure.
/// Complexity: O(total bytes) expected time, O(n) space
int lf_textclean_dedupe(const lf_text_span *pages, size_t n, long *dup_of);

#ifdef __cplusplus
}
#endif

#endif /* LF_TEXTCLEAN_H */

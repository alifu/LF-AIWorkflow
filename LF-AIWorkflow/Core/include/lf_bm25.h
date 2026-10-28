#ifndef LF_BM25_H
#define LF_BM25_H

#include <stddef.h>
#include <stdint.h>
#include "lf_textclean.h"

#ifdef __cplusplus
extern "C" {
#endif

/// Opaque BM25 index over a fixed set of text chunks.
typedef struct lf_bm25_index lf_bm25_index;

/// Builds an index. Tokens are ASCII alphanumeric runs lower-cased; bytes >= 0x80 count as word
/// bytes; tokens shorter than 2 bytes are ignored. Chunk bytes are copied, so `chunks` need not
/// outlive the call. Returns NULL + errno (EINVAL, ENOMEM) on failure.
/// Complexity: O(total bytes) expected time, O(total tokens) space
lf_bm25_index *lf_bm25_create(const lf_text_span *chunks, size_t n, double k1, double b);

/// Scores chunks against `q`. Writes up to `k` best chunk ids and scores, score descending, ties
/// by lower id. Returns the number written (min(k, matching chunks)); -1 + EINVAL/ENOMEM on error.
/// Complexity: O(q + postings touched + n + m log k) time, O(n + k) space
long lf_bm25_query(const lf_bm25_index *idx, const char *q, size_t qlen, size_t k,
                   uint32_t *ids, double *scores);

/// Frees an index (NULL is a no-op).
/// Complexity: O(terms) time, O(1) space
void lf_bm25_free(lf_bm25_index *idx);

#ifdef __cplusplus
}
#endif

#endif /* LF_BM25_H */

#ifndef LF_ERRSCAN_H
#define LF_ERRSCAN_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    size_t context_before, context_after;  /* default 2 / 2 */
    size_t tail_lines;                     /* default 20 */
    size_t max_output_bytes;               /* required > 0 */
} lf_errscan_options;

/// Options with the defaults (context 2/2, tail 20) and the given output budget.
/// Complexity: O(1) time, O(1) space
lf_errscan_options lf_errscan_default_options(size_t max_output_bytes);

/// Extracts error lines with context from build/test output into the caller buffer `out`
/// (out_cap >= max_output_bytes). Matches (case-insensitive) `error:`, `fatal`, `failed`;
/// (case-sensitive) `FAIL`, U+2718. Overlapping or touching groups merge; groups are
/// separated by "--\n"; the last `tail_lines` lines follow "-- tail --\n". The tail is added
/// only when something matched. Returns bytes written (0 = no matches); *truncated = 1 when
/// the budget cut output. -1 + EINVAL on bad arguments.
/// Complexity: O(n) time, O(c + out) space, c = context_before
long lf_errscan_extract(const void *log, size_t len, const lf_errscan_options *opts,
                        char *out, size_t out_cap, int *truncated);

#ifdef __cplusplus
}
#endif

#endif /* LF_ERRSCAN_H */

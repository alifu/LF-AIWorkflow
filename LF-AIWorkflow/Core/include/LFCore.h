//
//  LFCore.h
//  LF-AIWorkflow
//
//  Umbrella header of the LFCore module.
//

#ifndef LFCORE_H
#define LFCORE_H

#include "lf_ringbuf.h"
#include "lf_ndjson.h"
#include "lf_pty.h"
#include "lf_scan.h"
#include "lf_tokens.h"
#include "lf_errscan.h"
#include "lf_textclean.h"
#include "lf_bm25.h"

#ifdef __cplusplus
extern "C" {
#endif

/// Returns the core version tag as a static string.
/// Complexity: O(1) time, O(1) space
const char *lf_core_version(void);

/// Returns 1 when the C core was built with AddressSanitizer or UBSan, else 0 (skips wall-clock guards).
/// Complexity: O(1) time, O(1) space
int lf_core_built_with_sanitizer(void);

#ifdef __cplusplus
}
#endif

#endif /* LFCORE_H */

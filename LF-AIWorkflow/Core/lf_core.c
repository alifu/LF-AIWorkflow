#include "LFCore.h"

/// Complexity: O(1) time, O(1) space
const char *lf_core_version(void) {
    return "0.2.0";
}

/// Complexity: O(1) time, O(1) space
int lf_core_built_with_sanitizer(void) {
#if defined(__has_feature)
#  if __has_feature(address_sanitizer) || __has_feature(undefined_behavior_sanitizer)
    return 1;
#  endif
#endif
    return 0;
}

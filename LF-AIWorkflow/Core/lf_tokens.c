#include <stddef.h>
#include <stdint.h>
#include "LFCore.h"

/* Tuning constants (calibrated against Fixtures/tokens/reference.json). */
#define LF_TOK_ALPHA_RUN_DIV   4   /* ASCII letter run of n chars ~ ceil(n / 4) tokens */
#define LF_TOK_DIGIT_RUN_DIV   3   /* digit run of n chars ~ ceil(n / 3) tokens */
#define LF_TOK_PUNCT_RUN_DIV   2   /* ASCII punctuation run of n chars ~ ceil(n / 2) tokens */
#define LF_TOK_INDENT_MIN      2   /* space/tab run this long costs 1 token */
#define LF_TOK_EMOJI_COST      2   /* 4-byte sequence */
#define LF_TOK_WIDE_COST       1   /* 3-byte sequence (CJK etc.) */
#define LF_TOK_NARROW_COST     1   /* 2-byte sequence */

typedef enum { RUN_NONE = 0, RUN_ALPHA, RUN_DIGIT, RUN_NEWLINE, RUN_PUNCT, RUN_SPACE, RUN_HIGH } lf_run_kind;

/* Byte classes (256 entries): RUN_NONE = control byte, RUN_HIGH = UTF-8 lead/continuation. */
static const uint8_t kClass[256] = {
    RUN_NONE, RUN_NONE, RUN_NONE, RUN_NONE, RUN_NONE, RUN_NONE, RUN_NONE, RUN_NONE,
    RUN_NONE, RUN_SPACE, RUN_NEWLINE, RUN_NONE, RUN_NONE, RUN_NEWLINE, RUN_NONE, RUN_NONE,
    RUN_NONE, RUN_NONE, RUN_NONE, RUN_NONE, RUN_NONE, RUN_NONE, RUN_NONE, RUN_NONE,
    RUN_NONE, RUN_NONE, RUN_NONE, RUN_NONE, RUN_NONE, RUN_NONE, RUN_NONE, RUN_NONE,
    RUN_SPACE, RUN_PUNCT, RUN_PUNCT, RUN_PUNCT, RUN_PUNCT, RUN_PUNCT, RUN_PUNCT, RUN_PUNCT,
    RUN_PUNCT, RUN_PUNCT, RUN_PUNCT, RUN_PUNCT, RUN_PUNCT, RUN_PUNCT, RUN_PUNCT, RUN_PUNCT,
    RUN_DIGIT, RUN_DIGIT, RUN_DIGIT, RUN_DIGIT, RUN_DIGIT, RUN_DIGIT, RUN_DIGIT, RUN_DIGIT,
    RUN_DIGIT, RUN_DIGIT, RUN_PUNCT, RUN_PUNCT, RUN_PUNCT, RUN_PUNCT, RUN_PUNCT, RUN_PUNCT,
    RUN_PUNCT, RUN_ALPHA, RUN_ALPHA, RUN_ALPHA, RUN_ALPHA, RUN_ALPHA, RUN_ALPHA, RUN_ALPHA,
    RUN_ALPHA, RUN_ALPHA, RUN_ALPHA, RUN_ALPHA, RUN_ALPHA, RUN_ALPHA, RUN_ALPHA, RUN_ALPHA,
    RUN_ALPHA, RUN_ALPHA, RUN_ALPHA, RUN_ALPHA, RUN_ALPHA, RUN_ALPHA, RUN_ALPHA, RUN_ALPHA,
    RUN_ALPHA, RUN_ALPHA, RUN_ALPHA, RUN_PUNCT, RUN_PUNCT, RUN_PUNCT, RUN_PUNCT, RUN_PUNCT,
    RUN_PUNCT, RUN_ALPHA, RUN_ALPHA, RUN_ALPHA, RUN_ALPHA, RUN_ALPHA, RUN_ALPHA, RUN_ALPHA,
    RUN_ALPHA, RUN_ALPHA, RUN_ALPHA, RUN_ALPHA, RUN_ALPHA, RUN_ALPHA, RUN_ALPHA, RUN_ALPHA,
    RUN_ALPHA, RUN_ALPHA, RUN_ALPHA, RUN_ALPHA, RUN_ALPHA, RUN_ALPHA, RUN_ALPHA, RUN_ALPHA,
    RUN_ALPHA, RUN_ALPHA, RUN_ALPHA, RUN_PUNCT, RUN_PUNCT, RUN_PUNCT, RUN_PUNCT, RUN_NONE,
    RUN_HIGH, RUN_HIGH, RUN_HIGH, RUN_HIGH, RUN_HIGH, RUN_HIGH, RUN_HIGH, RUN_HIGH,
    RUN_HIGH, RUN_HIGH, RUN_HIGH, RUN_HIGH, RUN_HIGH, RUN_HIGH, RUN_HIGH, RUN_HIGH,
    RUN_HIGH, RUN_HIGH, RUN_HIGH, RUN_HIGH, RUN_HIGH, RUN_HIGH, RUN_HIGH, RUN_HIGH,
    RUN_HIGH, RUN_HIGH, RUN_HIGH, RUN_HIGH, RUN_HIGH, RUN_HIGH, RUN_HIGH, RUN_HIGH,
    RUN_HIGH, RUN_HIGH, RUN_HIGH, RUN_HIGH, RUN_HIGH, RUN_HIGH, RUN_HIGH, RUN_HIGH,
    RUN_HIGH, RUN_HIGH, RUN_HIGH, RUN_HIGH, RUN_HIGH, RUN_HIGH, RUN_HIGH, RUN_HIGH,
    RUN_HIGH, RUN_HIGH, RUN_HIGH, RUN_HIGH, RUN_HIGH, RUN_HIGH, RUN_HIGH, RUN_HIGH,
    RUN_HIGH, RUN_HIGH, RUN_HIGH, RUN_HIGH, RUN_HIGH, RUN_HIGH, RUN_HIGH, RUN_HIGH,
    RUN_HIGH, RUN_HIGH, RUN_HIGH, RUN_HIGH, RUN_HIGH, RUN_HIGH, RUN_HIGH, RUN_HIGH,
    RUN_HIGH, RUN_HIGH, RUN_HIGH, RUN_HIGH, RUN_HIGH, RUN_HIGH, RUN_HIGH, RUN_HIGH,
    RUN_HIGH, RUN_HIGH, RUN_HIGH, RUN_HIGH, RUN_HIGH, RUN_HIGH, RUN_HIGH, RUN_HIGH,
    RUN_HIGH, RUN_HIGH, RUN_HIGH, RUN_HIGH, RUN_HIGH, RUN_HIGH, RUN_HIGH, RUN_HIGH,
    RUN_HIGH, RUN_HIGH, RUN_HIGH, RUN_HIGH, RUN_HIGH, RUN_HIGH, RUN_HIGH, RUN_HIGH,
    RUN_HIGH, RUN_HIGH, RUN_HIGH, RUN_HIGH, RUN_HIGH, RUN_HIGH, RUN_HIGH, RUN_HIGH,
    RUN_HIGH, RUN_HIGH, RUN_HIGH, RUN_HIGH, RUN_HIGH, RUN_HIGH, RUN_HIGH, RUN_HIGH,
    RUN_HIGH, RUN_HIGH, RUN_HIGH, RUN_HIGH, RUN_HIGH, RUN_HIGH, RUN_HIGH, RUN_HIGH,
};

/// Tokens for a finished run.
/// Complexity: O(1) time, O(1) space
static size_t run_cost(lf_run_kind kind, size_t n) {
    switch (kind) {
    case RUN_ALPHA:   return (n + LF_TOK_ALPHA_RUN_DIV - 1) / LF_TOK_ALPHA_RUN_DIV;
    case RUN_DIGIT:   return (n + LF_TOK_DIGIT_RUN_DIV - 1) / LF_TOK_DIGIT_RUN_DIV;
    case RUN_PUNCT:   return (n + LF_TOK_PUNCT_RUN_DIV - 1) / LF_TOK_PUNCT_RUN_DIV;
    case RUN_SPACE:   return n >= LF_TOK_INDENT_MIN ? 1 : 0; /* single spaces merge into words */
    case RUN_NEWLINE: return 1;
    default:          return 0;
    }
}

/// Length of the valid UTF-8 sequence starting at p[0] (lead >= 0xC2), or 0 if the lead is
/// invalid or the sequence is truncated / has bad continuation bytes.
/// Complexity: O(1) time, O(1) space
static size_t utf8_seq_len(const uint8_t *p, size_t remaining) {
    uint8_t c = p[0];
    size_t need = (c >= 0xC2 && c <= 0xDF) ? 2 : (c >= 0xE0 && c <= 0xEF) ? 3
                : (c >= 0xF0 && c <= 0xF4) ? 4 : 0;
    if (need == 0 || need > remaining) return 0;
    for (size_t i = 1; i < need; i++) {
        if ((p[i] & 0xC0) != 0x80) return 0;
    }
    return need;
}

/// Complexity: O(n) time, O(1) space
size_t lf_tokens_estimate(const void *text, size_t len) {
    if (text == NULL || len == 0) return 0;
    const uint8_t *p = (const uint8_t *)text;
    size_t total = 0, i = 0;

    while (i < len) {
        lf_run_kind kind = (lf_run_kind)kClass[p[i]];
        if (kind == RUN_HIGH) {
            size_t n = utf8_seq_len(p + i, len - i);
            if (n == 0) {                                /* invalid: 1 per byte */
                total += 1;
                i += 1;
            } else {
                total += (n == 4) ? LF_TOK_EMOJI_COST : (n == 3) ? LF_TOK_WIDE_COST : LF_TOK_NARROW_COST;
                i += n;
            }
            continue;
        }
        if (kind == RUN_NONE) { total += 1; i++; continue; } /* control byte */
        size_t start = i;
        do { i++; } while (i < len && kClass[p[i]] == (uint8_t)kind);
        total += run_cost(kind, i - start);
    }
    return total;
}

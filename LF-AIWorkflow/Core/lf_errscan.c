#include "lf_errscan.h"

#include <errno.h>
#include <stdlib.h>
#include <string.h>

#define LF_ERRSCAN_DEFAULT_CONTEXT 2
#define LF_ERRSCAN_DEFAULT_TAIL_LINES 20
#define LF_ERRSCAN_MAX_CONTEXT 1024

static const char kGroupSeparator[] = "--\n";
static const char kTailHeader[] = "-- tail --\n";
#define SEP_LEN (sizeof kGroupSeparator - 1)
#define TAIL_HEADER_LEN (sizeof kTailHeader - 1)

/* Pattern table: keep all match rules here so Phase 4 can tune them. */
typedef struct {
    const char *text;
    size_t len;
    int case_sensitive;
} lf_errscan_pattern;

#define PAT(s, cs) { s, sizeof(s) - 1, cs }
static const lf_errscan_pattern kPatterns[] = {
    PAT("error:", 0),
    PAT("fatal", 0),
    PAT("failed", 0),
    PAT("FAIL", 1),
    PAT("\xE2\x9C\x98", 1),
};
#undef PAT

typedef struct {
    size_t start, len;   /* line text without '\n' and trailing '\r' */
} line_ref;

/// Complexity: O(1) time, O(1) space
static unsigned char lower(unsigned char c) {
    return (c >= 'A' && c <= 'Z') ? (unsigned char)(c + 32) : c;
}

/// Complexity: O(len * pattern) time, O(1) space
static int line_matches(const unsigned char *line, size_t len) {
    for (size_t pi = 0; pi < sizeof kPatterns / sizeof kPatterns[0]; pi++) {
        const lf_errscan_pattern *pat = &kPatterns[pi];
        if (len < pat->len) continue;
        for (size_t i = 0; i + pat->len <= len; i++) {
            size_t k = 0;
            if (pat->case_sensitive) {
                while (k < pat->len && line[i + k] == (unsigned char)pat->text[k]) k++;
            } else {
                while (k < pat->len && lower(line[i + k]) == (unsigned char)pat->text[k]) k++;
            }
            if (k == pat->len) return 1;
        }
    }
    return 0;
}

/// Largest k <= budget that does not split a UTF-8 sequence of p[0..n).
/// Complexity: O(1) time, O(1) space
static size_t utf8_cut(const unsigned char *p, size_t n, size_t budget) {
    if (budget >= n) return n;
    size_t k = budget;
    while (k > 0 && (p[k] & 0xC0) == 0x80) k--;
    return k;
}

/// Line starting at `pos`: sets text length (CR stripped) and the offset of the next line.
/// Complexity: O(line) time, O(1) space
static line_ref next_line(const unsigned char *log, size_t len, size_t pos, size_t *next) {
    const unsigned char *nl = memchr(log + pos, '\n', len - pos);
    size_t end = nl ? (size_t)(nl - log) : len;
    *next = nl ? end + 1 : len;
    size_t tl = end - pos;
    if (tl > 0 && log[pos + tl - 1] == '\r') tl--;
    line_ref r = { pos, tl };
    return r;
}

typedef struct {
    const unsigned char *log;
    char *out;
    size_t pos;
    size_t budget;      /* max bytes for the error section */
    int truncated;
    int full;
} sink;

/// Appends a line (optionally preceded by a separator) if it fits. A line that does not fit
/// is cut at a UTF-8 boundary only when nothing has been written yet.
/// Complexity: O(line) time, O(1) space
static void emit(sink *s, line_ref ln, int with_sep) {
    size_t need = (with_sep ? SEP_LEN : 0) + ln.len + 1;
    if (s->pos + need > s->budget) {
        s->truncated = 1;
        s->full = 1;
        if (s->pos == 0 && s->budget >= 2) {
            size_t cut = utf8_cut(s->log + ln.start, ln.len, s->budget - 1);
            memcpy(s->out, s->log + ln.start, cut);
            s->out[cut] = '\n';
            s->pos = cut + 1;
        }
        return;
    }
    if (with_sep) { memcpy(s->out + s->pos, kGroupSeparator, SEP_LEN); s->pos += SEP_LEN; }
    memcpy(s->out + s->pos, s->log + ln.start, ln.len);
    s->pos += ln.len;
    s->out[s->pos++] = '\n';
}

typedef struct {
    size_t start;        /* byte offset of first tail line; len when no tail */
    size_t bytes;        /* output bytes of the tail lines (excl. header) */
    size_t first_cut;    /* when != SIZE_MAX, first line is cut to this many bytes */
    int truncated;
} tail_plan;

/// Walks backwards from the end to pick the tail lines that fit `line_budget` bytes.
/// Complexity: O(tail bytes) time, O(1) space
static tail_plan plan_tail(const unsigned char *log, size_t len, size_t tail_lines, size_t line_budget) {
    tail_plan t = { len, 0, SIZE_MAX, 0 };
    if (len == 0 || tail_lines == 0 || line_budget < 2) return t;
    size_t line_end = (log[len - 1] == '\n') ? len - 1 : len;   /* end of last line (excl. '\n') */
    for (size_t k = 0; k < tail_lines; k++) {
        size_t start = 0;
        for (size_t i = line_end; i > 0; i--) {
            if (log[i - 1] == '\n') { start = i; break; }
        }
        size_t tl = line_end - start;
        if (tl > 0 && log[start + tl - 1] == '\r') tl--;
        if (t.bytes + tl + 1 > line_budget) {
            t.truncated = 1;
            if (k == 0) {
                t.first_cut = utf8_cut(log + start, tl, line_budget - 1);
                t.bytes = t.first_cut + 1;
                t.start = start;
            }
            break;
        }
        t.bytes += tl + 1;
        t.start = start;
        if (start == 0) break;
        line_end = start - 1;
    }
    return t;
}

/// Complexity: O(1) time, O(1) space
lf_errscan_options lf_errscan_default_options(size_t max_output_bytes) {
    lf_errscan_options o = { LF_ERRSCAN_DEFAULT_CONTEXT, LF_ERRSCAN_DEFAULT_CONTEXT,
                             LF_ERRSCAN_DEFAULT_TAIL_LINES, max_output_bytes };
    return o;
}

/// Complexity: O(n) time, O(c + out) space
long lf_errscan_extract(const void *vlog, size_t len, const lf_errscan_options *opts,
                        char *out, size_t out_cap, int *truncated) {
    if (truncated != NULL) *truncated = 0;
    if (opts == NULL || out == NULL || opts->max_output_bytes == 0 ||
        out_cap < opts->max_output_bytes || (vlog == NULL && len > 0)) {
        errno = EINVAL;
        return -1;
    }
    if (len == 0) return 0;
    const unsigned char *log = vlog;
    size_t cap = opts->max_output_bytes;

    /* Tail: reserved first, at most half of the budget. */
    size_t tail_budget = cap / 2;
    tail_plan tail = { len, 0, SIZE_MAX, 0 };
    if (tail_budget > TAIL_HEADER_LEN + 1) {
        tail = plan_tail(log, len, opts->tail_lines, tail_budget - TAIL_HEADER_LEN);
    }
    int has_tail = tail.start < len;
    size_t tail_reserve = has_tail ? TAIL_HEADER_LEN + tail.bytes : 0;

    size_t before = opts->context_before < LF_ERRSCAN_MAX_CONTEXT ? opts->context_before : LF_ERRSCAN_MAX_CONTEXT;
    line_ref *ring = before ? malloc(before * sizeof *ring) : NULL;
    if (before && ring == NULL) { errno = ENOMEM; return -1; }

    sink s = { log, out, 0, cap - tail_reserve, 0, 0 };
    size_t ring_count = 0, ring_head = 0;   /* ring_head = slot of the oldest entry */
    size_t line_idx = 0, emitted_until = 0, after_left = 0;
    int emitted_any = 0, any_match = 0;
    size_t pos = 0;

    while (pos < len && !s.full) {
        int in_tail = pos >= tail.start;
        if (in_tail && any_match) break;   /* tail lines are emitted by the tail section */
        size_t next;
        line_ref ln = next_line(log, len, pos, &next);
        int matched = line_matches(log + ln.start, ln.len);
        if (matched) {
            any_match = 1;
            size_t oldest = line_idx - ring_count;
            size_t first = oldest > emitted_until ? oldest : emitted_until;
            int sep = emitted_any && first > emitted_until;
            for (size_t k = first; k < line_idx && !s.full; k++) {
                line_ref prev = ring[(ring_head + (k - oldest)) % before];
                if (prev.start >= tail.start) break;
                emit(&s, prev, sep);
                sep = 0;
                emitted_any = 1;
            }
            if (in_tail) break;
            if (!s.full) { emit(&s, ln, sep); emitted_any = 1; emitted_until = line_idx + 1; }
            after_left = opts->context_after;
        } else if (after_left > 0 && !in_tail) {
            emit(&s, ln, 0);
            if (!s.full) { emitted_until = line_idx + 1; after_left--; }
        }
        if (before) {
            if (ring_count < before) {
                ring[(ring_head + ring_count) % before] = ln;
                ring_count++;
            } else {
                ring[ring_head] = ln;
                ring_head = (ring_head + 1) % before;
            }
        }
        line_idx++;
        pos = next;
        if (matched && s.full) break;
    }
    free(ring);

    if (!any_match) return 0;

    size_t total = s.pos;
    if (has_tail) {
        memcpy(out + total, kTailHeader, TAIL_HEADER_LEN);
        total += TAIL_HEADER_LEN;
        size_t p3 = tail.start;
        int first = 1;
        while (p3 < len) {
            size_t next;
            line_ref ln = next_line(log, len, p3, &next);
            size_t n = (first && tail.first_cut != SIZE_MAX) ? tail.first_cut : ln.len;
            memcpy(out + total, log + ln.start, n);
            total += n;
            out[total++] = '\n';
            first = 0;
            p3 = next;
        }
    }
    if (tail.truncated) s.truncated = 1;
    if (truncated != NULL) *truncated = s.truncated;
    return (long)total;
}

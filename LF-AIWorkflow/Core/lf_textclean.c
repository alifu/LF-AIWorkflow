#include <errno.h>
#include <stdlib.h>
#include <string.h>
#include "LFCore.h"

#define FNV_OFFSET 14695981039346656037ULL
#define FNV_PRIME 1099511628211ULL

/// Complexity: O(n) time, O(1) space
size_t lf_text_collapse_ws(char *buf, size_t len) {
    if (!buf) return 0;
    size_t w = 0, nl = 0;
    int pending = 0;
    for (size_t i = 0; i < len; i++) {
        unsigned char c = (unsigned char)buf[i];
        if (c == '\r') continue;
        if (c == ' ' || c == '\t') { pending = 1; continue; }
        if (c == '\n') {
            pending = 0;
            if (nl < 2) buf[w++] = '\n';
            nl++;
            continue;
        }
        if (c < 0x20 || c == 0x7f) continue;
        if (pending) buf[w++] = ' ';
        pending = 0;
        buf[w++] = (char)c;
        nl = 0;
    }
    return w;
}

/// Complexity: O(n) time, O(1) space
uint64_t lf_text_hash(const void *p, size_t n) {
    uint64_t h = FNV_OFFSET;
    const unsigned char *b = (const unsigned char *)p;
    for (size_t i = 0; b && i < n; i++) { h ^= b[i]; h *= FNV_PRIME; }
    return h;
}

/// Smallest power of two >= 2*items (min 16); 0 on overflow.
/// Complexity: O(log n) time, O(1) space
static size_t table_size(size_t items, size_t elem) {
    if (items > SIZE_MAX / 4 / (elem > 8 ? elem : 8)) return 0;
    size_t cap = 16;
    while (cap < items * 2) cap <<= 1;
    if (cap > SIZE_MAX / elem) return 0;
    return cap;
}

static int spans_valid(const lf_text_span *pages, size_t n) {
    for (size_t i = 0; i < n; i++)
        if (!pages[i].ptr && pages[i].len) return 0;
    return 1;
}

typedef struct {
    const char *p;
    size_t len;
    uint64_t hash;
    size_t count;
    size_t last_page;
} line_entry;

/// Next line in [p, end): sets *len without the newline, returns pointer past the newline.
/// Complexity: O(line) time, O(1) space
static const char *next_line(const char *p, const char *end, size_t *len) {
    const char *nl = memchr(p, '\n', (size_t)(end - p));
    if (!nl) { *len = (size_t)(end - p); return end; }
    *len = (size_t)(nl - p);
    return nl + 1;
}

static int is_blank(const char *p, size_t len) {
    for (size_t i = 0; i < len; i++)
        if (p[i] != ' ' && p[i] != '\t' && p[i] != '\r') return 0;
    return 1;
}

/// Finds or inserts the slot of a line; returns NULL never (table is never full).
/// Complexity: O(1) expected time, O(1) space
static line_entry *find_slot(line_entry *tab, size_t mask, const char *p, size_t len, uint64_t h) {
    size_t i = (size_t)h & mask;
    for (;;) {
        line_entry *e = &tab[i];
        if (e->count == 0 && e->p == NULL) return e;
        if (e->hash == h && e->len == len && memcmp(e->p, p, len) == 0) return e;
        i = (i + 1) & mask;
    }
}

/// Complexity: O(total bytes) expected time, O(total lines) space
long lf_textclean_boilerplate(const lf_text_span *pages, size_t n, size_t min_pages,
                              char **outs, const size_t *out_caps, size_t *out_lens) {
    if (n > 0 && (!pages || !outs || !out_caps || !out_lens)) { errno = EINVAL; return -1; }
    if (!spans_valid(pages, n)) { errno = EINVAL; return -1; }
    for (size_t i = 0; i < n; i++) {
        if (out_caps[i] < pages[i].len || (pages[i].len && !outs[i])) { errno = EINVAL; return -1; }
    }
    int active = n >= min_pages && n > 0;
    size_t threshold = (n + 1) / 2;
    line_entry *tab = NULL;
    size_t mask = 0;
    if (active) {
        size_t lines = 0;
        for (size_t i = 0; i < n; i++) {
            const char *p = pages[i].ptr, *end = p ? p + pages[i].len : p;
            while (p && p < end) { size_t l; p = next_line(p, end, &l); lines++; }
        }
        size_t cap = table_size(lines, sizeof(line_entry));
        if (!cap) { errno = ENOMEM; return -1; }
        tab = calloc(cap, sizeof(line_entry));
        if (!tab) { errno = ENOMEM; return -1; }
        mask = cap - 1;
        for (size_t i = 0; i < n; i++) {
            const char *p = pages[i].ptr, *end = p ? p + pages[i].len : p;
            while (p && p < end) {
                size_t l;
                const char *start = p;
                p = next_line(p, end, &l);
                if (is_blank(start, l)) continue;
                line_entry *e = find_slot(tab, mask, start, l, lf_text_hash(start, l));
                if (e->p == NULL) {
                    e->p = start; e->len = l; e->hash = lf_text_hash(start, l);
                    e->count = 1; e->last_page = i;
                } else if (e->last_page != i) {
                    e->count++; e->last_page = i;
                }
            }
        }
    }
    long removed = 0;
    for (size_t i = 0; i < n; i++) {
        const char *p = pages[i].ptr, *end = p ? p + pages[i].len : p;
        size_t w = 0;
        while (p && p < end) {
            size_t l;
            const char *start = p;
            p = next_line(p, end, &l);
            size_t total = (size_t)(p - start);
            if (active && !is_blank(start, l)) {
                line_entry *e = find_slot(tab, mask, start, l, lf_text_hash(start, l));
                if (e->count >= threshold) { removed++; continue; }
            }
            memcpy(outs[i] + w, start, total);
            w += total;
        }
        out_lens[i] = w;
    }
    free(tab);
    return removed;
}

/// Complexity: O(total bytes) expected time, O(n) space
int lf_textclean_dedupe(const lf_text_span *pages, size_t n, long *dup_of) {
    if (n > 0 && (!pages || !dup_of)) { errno = EINVAL; return -1; }
    size_t cap = n ? table_size(n, sizeof(long)) : 0;
    if (n > 0 && (!cap || n > SIZE_MAX / sizeof(uint64_t))) { errno = ENOMEM; return -1; }
    if (!spans_valid(pages, n)) { errno = EINVAL; return -1; }
    if (n == 0) return 0;
    long *tab = malloc(cap * sizeof(long));
    uint64_t *hashes = malloc(n * sizeof(uint64_t));
    if (!tab || !hashes) { free(tab); free(hashes); errno = ENOMEM; return -1; }
    for (size_t i = 0; i < cap; i++) tab[i] = -1;
    size_t mask = cap - 1;
    for (size_t i = 0; i < n; i++) {
        uint64_t h = lf_text_hash(pages[i].ptr, pages[i].len);
        hashes[i] = h;
        dup_of[i] = -1;
        size_t s = (size_t)h & mask;
        for (;;) {
            long j = tab[s];
            if (j < 0) { tab[s] = (long)i; break; }
            if (hashes[j] == h && pages[j].len == pages[i].len &&
                (pages[i].len == 0 || memcmp(pages[j].ptr, pages[i].ptr, pages[i].len) == 0)) {
                dup_of[i] = j;
                break;
            }
            s = (s + 1) & mask;
        }
    }
    free(tab);
    free(hashes);
    return 0;
}

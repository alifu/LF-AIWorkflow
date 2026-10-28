#include "lf_ndjson.h"

#include <errno.h>
#include <stdlib.h>
#include <string.h>

struct lf_ndjson {
    size_t max_line;
    unsigned char *buf;   /* pending tail, or backlog after a callback stop */
    size_t len;
    size_t cap;
    uint64_t oversize;
    int discarding;       /* dropping bytes until next '\n' */
    int backlog;          /* buf may hold complete lines (callback stopped) */
};

/// Complexity: O(1) time, O(1) space
lf_ndjson *lf_ndjson_create(size_t max_line) {
    lf_ndjson *fr = calloc(1, sizeof *fr);
    if (fr == NULL) {
        errno = ENOMEM;
        return NULL;
    }
    fr->max_line = max_line ? max_line : LF_NDJSON_DEFAULT_MAX_LINE;
    return fr;
}

/// Complexity: O(1) time, O(1) space
void lf_ndjson_destroy(lf_ndjson *fr) {
    if (fr == NULL) return;
    free(fr->buf);
    free(fr);
}

/// Complexity: O(1) time, O(1) space
uint64_t lf_ndjson_oversize_count(const lf_ndjson *fr) {
    return fr ? fr->oversize : 0;
}

/// Appends bytes to the pending buffer with geometric growth. 0 ok, -1 ENOMEM.
/// Complexity: O(n) amortized time, O(n) space
static int append_pending(lf_ndjson *fr, const unsigned char *data, size_t n) {
    if (n == 0) return 0;
    if (n > SIZE_MAX - fr->len) { errno = ENOMEM; return -1; }
    size_t need = fr->len + n;
    if (need > fr->cap) {
        size_t cap = fr->cap ? fr->cap : 256;
        while (cap < need) {
            if (cap > SIZE_MAX / 2) { cap = need; break; }
            cap *= 2;
        }
        unsigned char *nb = realloc(fr->buf, cap);
        if (nb == NULL) { errno = ENOMEM; return -1; }
        fr->buf = nb;
        fr->cap = cap;
    }
    memcpy(fr->buf + fr->len, data, n);
    fr->len = need;
    return 0;
}

/// Complexity: O(len) time, O(1) space
static int is_blank(const unsigned char *p, size_t len) {
    for (size_t i = 0; i < len; i++) {
        if (p[i] != ' ' && p[i] != '\t' && p[i] != '\r') return 0;
    }
    return 1;
}

/// Emits one complete line. Returns 1 emitted, 0 skipped, -1 oversize, 2 callback stop (emitted).
/// Complexity: O(len) time, O(1) space
static int emit_line(lf_ndjson *fr, const unsigned char *p, size_t len, lf_ndjson_line_cb cb, void *ctx) {
    if (len > 0 && p[len - 1] == '\r') len--;
    if (len > fr->max_line) {
        fr->oversize++;
        return 0;
    }
    if (is_blank(p, len)) return 0;
    if (cb != NULL && cb((const char *)p, len, ctx) != 0) return 2;
    return 1;
}

/// Complexity: O(k) amortized time, O(L) space
long lf_ndjson_feed(lf_ndjson *fr, const void *vdata, size_t len, lf_ndjson_line_cb cb, void *ctx) {
    if (fr == NULL) { errno = EINVAL; return -1; }
    const unsigned char *data = vdata;
    if (data == NULL) len = 0;

    int in_backlog = fr->backlog;
    if (in_backlog) {
        if (append_pending(fr, data, len) != 0) return -1;
        data = fr->buf;
        len = fr->len;
    }
    size_t prefix = in_backlog ? 0 : fr->len;   /* pending bytes belonging to the first line */
    size_t pos = 0;
    long count = 0;
    int stopped = 0;

    while (pos < len) {
        const unsigned char *nl = memchr(data + pos, '\n', len - pos);
        if (fr->discarding) {
            if (nl == NULL) { pos = len; break; }
            pos = (size_t)(nl - data) + 1;
            fr->discarding = 0;
            continue;
        }
        if (nl == NULL) break;
        size_t seg_len = (size_t)(nl - (data + pos));
        size_t next = (size_t)(nl - data) + 1;
        int r;
        if (prefix > 0) {
            if (seg_len > fr->max_line || fr->len + seg_len > fr->max_line + 1) {
                fr->oversize++;
                r = 0;
            } else {
                if (append_pending(fr, data + pos, seg_len) != 0) return -1;
                r = emit_line(fr, fr->buf, fr->len, cb, ctx);
            }
            fr->len = 0;
            prefix = 0;
        } else {
            r = emit_line(fr, data + pos, seg_len, cb, ctx);
        }
        pos = next;
        if (r == 1 || r == 2) count++;
        if (r == 2) { stopped = 1; break; }
    }

    size_t rem = len - pos;
    if (in_backlog) {
        memmove(fr->buf, fr->buf + pos, rem);
        fr->len = rem;
    } else {
        if (prefix == 0 && pos > 0) fr->len = 0;   /* pending already consumed */
        if (!fr->discarding && append_pending(fr, data + pos, rem) != 0) return -1;
    }
    fr->backlog = stopped;
    if (!stopped && !fr->discarding && fr->len > fr->max_line + 1) {
        fr->len = 0;
        fr->discarding = 1;
        fr->oversize++;
    }
    return count;
}

/// Complexity: O(L) time, O(L) space
long lf_ndjson_finish(lf_ndjson *fr, lf_ndjson_line_cb cb, void *ctx) {
    if (fr == NULL) { errno = EINVAL; return -1; }
    long count = 0;
    if (!fr->discarding && fr->len > 0) {
        count = lf_ndjson_feed(fr, "\n", 1, cb, ctx);
    }
    fr->len = 0;
    fr->backlog = 0;
    fr->discarding = 0;
    return count;
}

/* ---------------------------------------------------------------- field scan */

typedef struct {
    const char *p;
    const char *end;
} scan_cur;

/// Complexity: O(w) time, O(1) space
static void skip_ws(scan_cur *c) {
    while (c->p < c->end && (*c->p == ' ' || *c->p == '\t' || *c->p == '\r' || *c->p == '\n')) c->p++;
}

/// Positions after the closing quote of a string whose opening quote is at c->p. Outputs raw body.
/// Complexity: O(s) time, O(1) space
static int read_string(scan_cur *c, const char **body, size_t *body_len) {
    if (c->p >= c->end || *c->p != '"') return -1;
    const char *start = ++c->p;
    while (c->p < c->end) {
        if (*c->p == '\\') {
            c->p += 2;
            continue;
        }
        if (*c->p == '"') {
            *body = start;
            *body_len = (size_t)(c->p - start);
            c->p++;
            return 0;
        }
        c->p++;
    }
    c->p = c->end;
    return -1;
}

/// Skips one JSON value (string, scalar, or balanced object/array).
/// Complexity: O(v) time, O(1) space
static int skip_value(scan_cur *c) {
    skip_ws(c);
    if (c->p >= c->end) return -1;
    if (*c->p == '"') {
        const char *b; size_t n;
        return read_string(c, &b, &n);
    }
    if (*c->p == '{' || *c->p == '[') {
        long depth = 0;
        while (c->p < c->end) {
            char ch = *c->p;
            if (ch == '"') {
                const char *b; size_t n;
                if (read_string(c, &b, &n) != 0) return -1;
                continue;
            }
            c->p++;
            if (ch == '{' || ch == '[') depth++;
            else if (ch == '}' || ch == ']') {
                if (--depth == 0) return 0;
            }
        }
        return -1;
    }
    while (c->p < c->end && *c->p != ',' && *c->p != '}' && *c->p != ']' &&
           *c->p != ' ' && *c->p != '\t' && *c->p != '\r' && *c->p != '\n') c->p++;
    return 0;
}

/// Extracts the next dotted segment. Returns its length; advances *path past the dot.
/// Complexity: O(segment) time, O(1) space
static size_t next_segment(const char **path, const char **seg, int *last) {
    const char *s = *path;
    const char *dot = strchr(s, '.');
    size_t n = dot ? (size_t)(dot - s) : strlen(s);
    *seg = s;
    *last = dot == NULL;
    *path = dot ? dot + 1 : s + n;
    return n;
}

/// Locates the value for `path` inside the object at c->p; leaves c->p at the value start.
/// Returns 0 found, -1 with errno set.
/// Complexity: O(object) time, O(depth of path) space
static int find_value(scan_cur *c, const char *path) {
    const char *seg;
    int last;
    size_t seg_len = next_segment(&path, &seg, &last);
    skip_ws(c);
    if (c->p >= c->end || *c->p != '{') { errno = EINVAL; return -1; }
    c->p++;
    for (;;) {
        skip_ws(c);
        if (c->p >= c->end) { errno = EINVAL; return -1; }
        if (*c->p == '}') { errno = ENOENT; return -1; }
        const char *key; size_t key_len;
        if (read_string(c, &key, &key_len) != 0) { errno = EINVAL; return -1; }
        skip_ws(c);
        if (c->p >= c->end || *c->p != ':') { errno = EINVAL; return -1; }
        c->p++;
        skip_ws(c);
        if (key_len == seg_len && memcmp(key, seg, seg_len) == 0) {
            if (last) return 0;
            if (c->p < c->end && *c->p == '{') return find_value(c, path);
        }
        if (skip_value(c) != 0) { errno = EINVAL; return -1; }
        skip_ws(c);
        if (c->p < c->end && *c->p == ',') { c->p++; continue; }
        if (c->p < c->end && *c->p == '}') { errno = ENOENT; return -1; }
        errno = EINVAL;
        return -1;
    }
}

/// Complexity: O(line) time, O(1) space
int lf_ndjson_get_string(const char *line, size_t len, const char *path, const char **out, size_t *out_len) {
    if (path == NULL || *path == '\0' || out == NULL || out_len == NULL || (line == NULL && len > 0)) {
        errno = EINVAL;
        return -1;
    }
    scan_cur c = { line, line + len };
    if (find_value(&c, path) != 0) return -1;
    if (read_string(&c, out, out_len) != 0) { errno = EINVAL; return -1; }
    return 0;
}

/// Complexity: O(line) time, O(1) space
int lf_ndjson_get_int64(const char *line, size_t len, const char *path, int64_t *out) {
    if (path == NULL || *path == '\0' || out == NULL || (line == NULL && len > 0)) {
        errno = EINVAL;
        return -1;
    }
    scan_cur c = { line, line + len };
    if (find_value(&c, path) != 0) return -1;
    int negative = 0;
    if (c.p < c.end && *c.p == '-') { negative = 1; c.p++; }
    if (c.p >= c.end || *c.p < '0' || *c.p > '9') { errno = EINVAL; return -1; }
    uint64_t limit = negative ? (uint64_t)INT64_MAX + 1u : (uint64_t)INT64_MAX;
    uint64_t acc = 0;
    int overflow = 0;
    while (c.p < c.end && *c.p >= '0' && *c.p <= '9') {
        uint64_t d = (uint64_t)(*c.p - '0');
        if (acc > (limit - d) / 10) overflow = 1;
        else acc = acc * 10 + d;
        c.p++;
    }
    if (c.p < c.end && (*c.p == '.' || *c.p == 'e' || *c.p == 'E')) { errno = EINVAL; return -1; }
    if (overflow) { errno = ERANGE; return -1; }
    *out = negative ? (int64_t)(0 - acc) : (int64_t)acc;
    return 0;
}

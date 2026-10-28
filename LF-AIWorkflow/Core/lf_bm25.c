#include <errno.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>
#include "LFCore.h"

#define BM25_MIN_TOKEN 2
#define BM25_INIT_SLOTS 64

typedef struct { uint32_t chunk; uint32_t tf; } posting;

typedef struct {
    size_t off, len;
    uint64_t hash;
    uint32_t df;
    posting *p;
    size_t pn, pcap;
} term;

struct lf_bm25_index {
    size_t n;
    double k1, b, avgdl;
    uint32_t *doclen;
    term *terms;
    size_t nterms, tcap;
    char *arena;
    size_t alen, acap;
    size_t *slots;      /* term index + 1, 0 = empty */
    size_t nslots;      /* power of two */
};

static int is_word(unsigned char c) {
    return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c >= 0x80;
}

static unsigned char lower(unsigned char c) {
    return (c >= 'A' && c <= 'Z') ? (unsigned char)(c + 32) : c;
}

/// Complexity: O(len) time, O(1) space
static uint64_t hash_lower(const char *s, size_t len) {
    uint64_t h = 14695981039346656037ULL;
    for (size_t i = 0; i < len; i++) { h ^= lower((unsigned char)s[i]); h *= 1099511628211ULL; }
    return h;
}

/// Next token in [s+*pos, s+len). Returns 1 and sets start/tlen, 0 at end.
/// Complexity: O(len) time, O(1) space
static int next_token(const char *s, size_t len, size_t *pos, size_t *start, size_t *tlen) {
    size_t i = *pos;
    while (i < len) {
        while (i < len && !is_word((unsigned char)s[i])) i++;
        size_t st = i;
        while (i < len && is_word((unsigned char)s[i])) i++;
        if (i - st >= BM25_MIN_TOKEN) { *pos = i; *start = st; *tlen = i - st; return 1; }
    }
    *pos = len;
    return 0;
}

static int term_matches(const lf_bm25_index *ix, const term *t, const char *s, size_t len, uint64_t h) {
    if (t->hash != h || t->len != len) return 0;
    for (size_t i = 0; i < len; i++)
        if ((unsigned char)ix->arena[t->off + i] != lower((unsigned char)s[i])) return 0;
    return 1;
}

/// Complexity: O(1) expected time, O(1) space
static long find_term(const lf_bm25_index *ix, const char *s, size_t len, uint64_t h) {
    size_t mask = ix->nslots - 1;
    for (size_t i = (size_t)h & mask;; i = (i + 1) & mask) {
        size_t v = ix->slots[i];
        if (v == 0) return -1;
        if (term_matches(ix, &ix->terms[v - 1], s, len, h)) return (long)(v - 1);
    }
}

/// Complexity: O(terms) time, O(terms) space
static int grow_slots(lf_bm25_index *ix) {
    size_t ns = ix->nslots * 2;
    size_t *slots = calloc(ns, sizeof(size_t));
    if (!slots) return -1;
    for (size_t t = 0; t < ix->nterms; t++) {
        size_t i = (size_t)ix->terms[t].hash & (ns - 1);
        while (slots[i]) i = (i + 1) & (ns - 1);
        slots[i] = t + 1;
    }
    free(ix->slots);
    ix->slots = slots;
    ix->nslots = ns;
    return 0;
}

/// Complexity: O(1) amortized time, O(len) space
static long add_term(lf_bm25_index *ix, const char *s, size_t len, uint64_t h) {
    if ((ix->nterms + 1) * 2 > ix->nslots && grow_slots(ix) != 0) return -1;
    if (ix->nterms == ix->tcap) {
        size_t nc = ix->tcap ? ix->tcap * 2 : 64;
        term *nt = realloc(ix->terms, nc * sizeof(term));
        if (!nt) return -1;
        ix->terms = nt;
        ix->tcap = nc;
    }
    if (ix->alen + len > ix->acap) {
        size_t nc = ix->acap ? ix->acap * 2 : 1024;
        while (nc < ix->alen + len) nc *= 2;
        char *na = realloc(ix->arena, nc);
        if (!na) return -1;
        ix->arena = na;
        ix->acap = nc;
    }
    for (size_t i = 0; i < len; i++) ix->arena[ix->alen + i] = (char)lower((unsigned char)s[i]);
    term *t = &ix->terms[ix->nterms];
    memset(t, 0, sizeof(*t));
    t->off = ix->alen;
    t->len = len;
    t->hash = h;
    ix->alen += len;
    size_t mask = ix->nslots - 1, i = (size_t)h & mask;
    while (ix->slots[i]) i = (i + 1) & mask;
    ix->slots[i] = ++ix->nterms;
    return (long)(ix->nterms - 1);
}

/// Complexity: O(1) amortized time, O(1) space
static int add_posting(term *t, uint32_t chunk) {
    if (t->pn > 0 && t->p[t->pn - 1].chunk == chunk) { t->p[t->pn - 1].tf++; return 0; }
    if (t->pn == t->pcap) {
        size_t nc = t->pcap ? t->pcap * 2 : 2;
        posting *np = realloc(t->p, nc * sizeof(posting));
        if (!np) return -1;
        t->p = np;
        t->pcap = nc;
    }
    t->p[t->pn].chunk = chunk;
    t->p[t->pn].tf = 1;
    t->pn++;
    t->df++;
    return 0;
}

/// Complexity: O(terms) time, O(1) space
void lf_bm25_free(lf_bm25_index *ix) {
    if (!ix) return;
    for (size_t i = 0; i < ix->nterms; i++) free(ix->terms[i].p);
    free(ix->terms);
    free(ix->arena);
    free(ix->slots);
    free(ix->doclen);
    free(ix);
}

/// Complexity: O(total bytes) expected time, O(total tokens) space
lf_bm25_index *lf_bm25_create(const lf_text_span *chunks, size_t n, double k1, double b) {
    if ((n > 0 && !chunks) || n > UINT32_MAX || !(k1 >= 0) || !(b >= 0 && b <= 1)) {
        errno = EINVAL;
        return NULL;
    }
    lf_bm25_index *ix = calloc(1, sizeof(*ix));
    if (!ix) return NULL;
    ix->n = n;
    ix->k1 = k1;
    ix->b = b;
    ix->nslots = BM25_INIT_SLOTS;
    ix->slots = calloc(ix->nslots, sizeof(size_t));
    ix->doclen = calloc(n ? n : 1, sizeof(uint32_t));
    if (!ix->slots || !ix->doclen) goto fail;
    double total = 0;
    for (size_t c = 0; c < n; c++) {
        if (chunks[c].len > 0 && !chunks[c].ptr) { errno = EINVAL; goto fail_keep; }
        size_t pos = 0, st, tl;
        while (next_token(chunks[c].ptr, chunks[c].len, &pos, &st, &tl)) {
            const char *tok = chunks[c].ptr + st;
            uint64_t h = hash_lower(tok, tl);
            long ti = find_term(ix, tok, tl, h);
            if (ti < 0) ti = add_term(ix, tok, tl, h);
            if (ti < 0 || add_posting(&ix->terms[ti], (uint32_t)c) != 0) goto fail;
            ix->doclen[c]++;
            total++;
        }
    }
    ix->avgdl = n ? total / (double)n : 0;
    return ix;
fail:
    errno = ENOMEM;
fail_keep: {
    int e = errno;
    lf_bm25_free(ix);
    errno = e;
    return NULL;
}
}

/* Heap of (id, score); root is the WORST kept entry (lowest score, then highest id). */
static int worse(double sa, uint32_t ia, double sb, uint32_t ib) {
    return sa < sb || (sa == sb && ia > ib);
}

/// Complexity: O(log k) time, O(1) space
static void sift_down(uint32_t *ids, double *sc, size_t n, size_t i) {
    for (;;) {
        size_t l = 2 * i + 1, r = l + 1, w = i;
        if (l < n && worse(sc[l], ids[l], sc[w], ids[w])) w = l;
        if (r < n && worse(sc[r], ids[r], sc[w], ids[w])) w = r;
        if (w == i) return;
        uint32_t ti = ids[i]; ids[i] = ids[w]; ids[w] = ti;
        double ts = sc[i]; sc[i] = sc[w]; sc[w] = ts;
        i = w;
    }
}

/// Complexity: O(log k) time, O(1) space
static void sift_up(uint32_t *ids, double *sc, size_t i) {
    while (i > 0) {
        size_t p = (i - 1) / 2;
        if (!worse(sc[i], ids[i], sc[p], ids[p])) return;
        uint32_t ti = ids[i]; ids[i] = ids[p]; ids[p] = ti;
        double ts = sc[i]; sc[i] = sc[p]; sc[p] = ts;
        i = p;
    }
}

/// Adds the BM25 contribution of term `t` (once per query term) to acc[].
/// Complexity: O(postings) time, O(1) space
static void score_term(const lf_bm25_index *ix, const term *t, double *acc, unsigned char *hit) {
    double idf = log(1.0 + ((double)ix->n - t->df + 0.5) / (t->df + 0.5));
    for (size_t i = 0; i < t->pn; i++) {
        uint32_t c = t->p[i].chunk;
        double tf = t->p[i].tf;
        double norm = ix->avgdl > 0 ? 1.0 - ix->b + ix->b * ix->doclen[c] / ix->avgdl : 1.0;
        acc[c] += idf * (tf * (ix->k1 + 1.0)) / (tf + ix->k1 * norm);
        hit[c] = 1;
    }
}

/// Complexity: O(q + postings touched + n + m log k) time, O(n + k) space
long lf_bm25_query(const lf_bm25_index *ix, const char *q, size_t qlen, size_t k,
                   uint32_t *ids, double *scores) {
    if (!ix || (qlen > 0 && !q) || (k > 0 && (!ids || !scores))) { errno = EINVAL; return -1; }
    if (k == 0 || qlen == 0 || ix->n == 0) return 0;
    double *acc = calloc(ix->n, sizeof(double));
    unsigned char *hit = calloc(ix->n, 1);
    long *seen = NULL;
    size_t nseen = 0, qcap = 0;
    long result = -1;
    if (!acc || !hit) { errno = ENOMEM; goto done; }
    size_t pos = 0, st, tl;
    while (next_token(q, qlen, &pos, &st, &tl)) {
        long ti = find_term(ix, q + st, tl, hash_lower(q + st, tl));
        if (ti < 0) continue;
        int dup = 0;
        for (size_t i = 0; i < nseen; i++) if (seen[i] == ti) { dup = 1; break; }
        if (dup) continue;
        if (nseen == qcap) {
            size_t nc = qcap ? qcap * 2 : 8;
            long *ns = realloc(seen, nc * sizeof(long));
            if (!ns) { errno = ENOMEM; goto done; }
            seen = ns;
            qcap = nc;
        }
        seen[nseen++] = ti;
        score_term(ix, &ix->terms[ti], acc, hit);
    }
    size_t cnt = 0;
    for (size_t c = 0; c < ix->n; c++) {
        if (!hit[c]) continue;
        if (cnt < k) {
            ids[cnt] = (uint32_t)c; scores[cnt] = acc[c];
            sift_up(ids, scores, cnt);
            cnt++;
        } else if (worse(scores[0], ids[0], acc[c], (uint32_t)c)) {
            ids[0] = (uint32_t)c; scores[0] = acc[c];
            sift_down(ids, scores, cnt, 0);
        }
    }
    for (size_t end = cnt; end > 1; end--) {  /* heap sort: worst moves to the back */
        uint32_t ti = ids[0]; ids[0] = ids[end - 1]; ids[end - 1] = ti;
        double ts = scores[0]; scores[0] = scores[end - 1]; scores[end - 1] = ts;
        sift_down(ids, scores, end - 1, 0);
    }
    result = (long)cnt;
done:
    free(acc); free(hit); free(seen);
    return result;
}

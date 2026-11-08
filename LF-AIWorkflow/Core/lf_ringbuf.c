#include "lf_ringbuf.h"

#include <errno.h>
#include <stdlib.h>
#include <string.h>

struct lf_ringbuf {
    size_t capacity;
    size_t head;    /* index of oldest byte */
    size_t size;
    uint64_t dropped;
    unsigned char bytes[];
};

/// Complexity: O(1) time, O(C) space
lf_ringbuf *lf_ringbuf_create(size_t capacity) {
    if (capacity == 0) {
        errno = EINVAL;
        return NULL;
    }
    if (capacity > SIZE_MAX - sizeof(struct lf_ringbuf)) {
        errno = ENOMEM;
        return NULL;
    }
    lf_ringbuf *rb = calloc(1, sizeof(struct lf_ringbuf) + capacity);
    if (rb == NULL) {
        errno = ENOMEM;
        return NULL;
    }
    rb->capacity = capacity;
    return rb;
}

/// Complexity: O(1) time, O(1) space
void lf_ringbuf_destroy(lf_ringbuf *rb) {
    free(rb);
}

/// Copies up to n bytes from the logical start (offset 0 = oldest) using at most 2 memcpy.
/// Complexity: O(n) time, O(1) space
static void copy_out(const lf_ringbuf *rb, void *out, size_t n) {
    size_t first = rb->capacity - rb->head;
    if (first > n) first = n;
    memcpy(out, rb->bytes + rb->head, first);
    if (n > first) memcpy((unsigned char *)out + first, rb->bytes, n - first);
}

/// Complexity: O(k) time, O(1) space, k = min(len, capacity)
size_t lf_ringbuf_write(lf_ringbuf *rb, const void *data, size_t len) {
    if (rb == NULL || data == NULL || len == 0) return 0;
    const unsigned char *src = data;
    if (len > rb->capacity) {
        rb->dropped += (uint64_t)(len - rb->capacity);
        src += len - rb->capacity;
        len = rb->capacity;
    }
    size_t free_space = rb->capacity - rb->size;
    if (len > free_space) {
        size_t overwrite = len - free_space;
        rb->dropped += (uint64_t)overwrite;
        rb->head = (rb->head + overwrite) % rb->capacity;
        rb->size -= overwrite;
    }
    size_t tail = (rb->head + rb->size) % rb->capacity;
    size_t first = rb->capacity - tail;
    if (first > len) first = len;
    memcpy(rb->bytes + tail, src, first);
    if (len > first) memcpy(rb->bytes, src + first, len - first);
    rb->size += len;
    return len;
}

/// Complexity: O(m) time, O(1) space, m = min(out_cap, size)
size_t lf_ringbuf_read(lf_ringbuf *rb, void *out, size_t out_cap) {
    if (rb == NULL || out == NULL || out_cap == 0 || rb->size == 0) return 0;
    size_t n = out_cap < rb->size ? out_cap : rb->size;
    copy_out(rb, out, n);
    rb->head = (rb->head + n) % rb->capacity;
    rb->size -= n;
    return n;
}

/// Complexity: O(C) time, O(1) space
size_t lf_ringbuf_snapshot(const lf_ringbuf *rb, void *out, size_t out_cap) {
    if (rb == NULL || out == NULL || out_cap == 0 || rb->size == 0) return 0;
    size_t n = out_cap < rb->size ? out_cap : rb->size;
    copy_out(rb, out, n);
    return n;
}

/// Complexity: O(1) time, O(1) space
size_t lf_ringbuf_size(const lf_ringbuf *rb) { return rb ? rb->size : 0; }

/// Complexity: O(1) time, O(1) space
size_t lf_ringbuf_capacity(const lf_ringbuf *rb) { return rb ? rb->capacity : 0; }

/// Complexity: O(1) time, O(1) space
uint64_t lf_ringbuf_dropped(const lf_ringbuf *rb) { return rb ? rb->dropped : 0; }

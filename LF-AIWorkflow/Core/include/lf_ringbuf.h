#ifndef LF_RINGBUF_H
#define LF_RINGBUF_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Fixed-capacity byte ring buffer; opaque, single allocation (header + bytes).
typedef struct lf_ringbuf lf_ringbuf;

/// Creates a ring buffer. Returns NULL with EINVAL if capacity is 0, ENOMEM on failure.
/// Complexity: O(1) time, O(C) space
lf_ringbuf *lf_ringbuf_create(size_t capacity);

/// Frees the buffer. NULL-safe.
/// Complexity: O(1) time, O(1) space
void lf_ringbuf_destroy(lf_ringbuf *rb);

/// Appends bytes, overwriting the oldest when full. If len > capacity only the last
/// capacity bytes are kept. Returns the number of bytes of this call now stored.
/// Complexity: O(k) time, O(1) space, k = min(len, capacity)
size_t lf_ringbuf_write(lf_ringbuf *rb, const void *data, size_t len);

/// Consuming read of up to out_cap bytes, oldest first.
/// Complexity: O(m) time, O(1) space, m = min(out_cap, size)
size_t lf_ringbuf_read(lf_ringbuf *rb, void *out, size_t out_cap);

/// Non-consuming copy of up to out_cap bytes, oldest to newest.
/// Complexity: O(C) time, O(1) space
size_t lf_ringbuf_snapshot(const lf_ringbuf *rb, void *out, size_t out_cap);

/// Bytes currently stored.
/// Complexity: O(1) time, O(1) space
size_t lf_ringbuf_size(const lf_ringbuf *rb);

/// Total capacity in bytes.
/// Complexity: O(1) time, O(1) space
size_t lf_ringbuf_capacity(const lf_ringbuf *rb);

/// Total bytes overwritten or discarded since creation.
/// Complexity: O(1) time, O(1) space
uint64_t lf_ringbuf_dropped(const lf_ringbuf *rb);

#ifdef __cplusplus
}
#endif

#endif /* LF_RINGBUF_H */

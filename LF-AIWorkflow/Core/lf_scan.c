#include "lf_scan.h"

#include <errno.h>
#include <fcntl.h>
#include <fts.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/stat.h>
#include <unistd.h>

#define LF_FNV1A64_PRIME 0x100000001b3ULL
#define LF_SCAN_BUF_SIZE (64 * 1024)

/// Complexity: O(n) time, O(1) space
uint64_t lf_fnv1a64(const void *data, size_t len, uint64_t seed) {
    const unsigned char *p = data;
    if (p == NULL) return seed;
    uint64_t h = seed;
    for (size_t i = 0; i < len; i++) {
        h ^= p[i];
        h *= LF_FNV1A64_PRIME;
    }
    return h;
}

/// Hashes a file with a caller-provided LF_SCAN_BUF_SIZE buffer.
/// Complexity: O(size) time, O(1) space
static int hash_file_with(const char *path, unsigned char *buf, uint64_t *out) {
    /* NONBLOCK keeps a swapped-in FIFO from hanging open(); NOFOLLOW rejects swapped symlinks. */
    int fd = open(path, O_RDONLY | O_CLOEXEC | O_NONBLOCK | O_NOFOLLOW);
    if (fd < 0) return -1;
    struct stat st;
    int st_rc = fstat(fd, &st);
    if (st_rc < 0 || !S_ISREG(st.st_mode)) {
        int saved = st_rc < 0 ? errno : EINVAL;
        close(fd);
        errno = saved;
        return -1;
    }
    uint64_t h = LF_FNV1A64_OFFSET;
    for (;;) {
        ssize_t n = read(fd, buf, LF_SCAN_BUF_SIZE);
        if (n < 0) {
            if (errno == EINTR) continue;
            int saved = errno;
            close(fd);
            errno = saved;
            return -1;
        }
        if (n == 0) break;
        h = lf_fnv1a64(buf, (size_t)n, h);
    }
    close(fd);
    *out = h;
    return 0;
}

/// Complexity: O(size) time, O(1) space
int lf_fnv1a64_file(const char *path, uint64_t *out) {
    if (path == NULL || out == NULL) { errno = EINVAL; return -1; }
    unsigned char *buf = malloc(LF_SCAN_BUF_SIZE);
    if (buf == NULL) { errno = ENOMEM; return -1; }
    int r = hash_file_with(path, buf, out);
    int saved = errno;
    free(buf);
    errno = saved;
    return r;
}

/// Complexity: O(extensions * name) time, O(1) space
static int extension_matches(const FTSENT *ent, const lf_scan_options *o) {
    if (o->extensions == NULL) return 1;
    const char *name = ent->fts_name;
    const char *dot = strrchr(name, '.');
    if (dot == NULL || dot == name || dot[1] == '\0') return 0;
    for (size_t i = 0; i < o->extension_count; i++) {
        if (o->extensions[i] != NULL && strcasecmp(dot + 1, o->extensions[i]) == 0) return 1;
    }
    return 0;
}

/// Complexity: O(1) time, O(1) space
static int is_hidden(const FTSENT *ent) {
    return ent->fts_name[0] == '.';
}

/// Complexity: O(F + sum of sizes) time, O(depth) space
long lf_scan_walk(const char *root, const lf_scan_options *opts, lf_scan_cb cb, void *ctx) {
    if (root == NULL || cb == NULL) { errno = EINVAL; return -1; }
    lf_scan_options defaults = { -1, NULL, 0, 0, 0 };
    const lf_scan_options *o = opts ? opts : &defaults;

    struct stat st;
    if (stat(root, &st) < 0) return -1;

    unsigned char *buf = malloc(LF_SCAN_BUF_SIZE);
    if (buf == NULL) { errno = ENOMEM; return -1; }
    char *const paths[2] = { (char *)root, NULL };
    FTS *fts = fts_open(paths, FTS_PHYSICAL | FTS_NOCHDIR | FTS_COMFOLLOW, NULL);
    if (fts == NULL) {
        int saved = errno;
        free(buf);
        errno = saved;
        return -1;
    }

    long count = 0;
    FTSENT *ent;
    while ((ent = fts_read(fts)) != NULL) {
        if (ent->fts_info == FTS_D) {
            int too_deep = o->max_depth >= 0 && ent->fts_level >= o->max_depth;
            int hidden = ent->fts_level > 0 && !o->include_hidden && is_hidden(ent);
            if (too_deep || hidden) fts_set(fts, ent, FTS_SKIP);
            continue;
        }
        if (ent->fts_info != FTS_F || ent->fts_level == 0) continue;
        if (o->max_depth >= 0 && ent->fts_level > o->max_depth) continue;
        if (!o->include_hidden && is_hidden(ent)) continue;
        if (!extension_matches(ent, o)) continue;

        lf_scan_entry e;
        e.path = ent->fts_path;
        e.path_len = ent->fts_pathlen;
        e.size = (uint64_t)ent->fts_statp->st_size;
        e.depth = (int)ent->fts_level;
        e.hash = 0;
        e.hashed = 0;
        if (o->max_hash_bytes == 0 || e.size <= o->max_hash_bytes) {
            uint64_t h;
            if (hash_file_with(ent->fts_path, buf, &h) == 0) {
                e.hash = h;
                e.hashed = 1;
            }
        }
        count++;
        if (cb(&e, ctx) != 0) break;
    }
    fts_close(fts);
    free(buf);
    return count;
}

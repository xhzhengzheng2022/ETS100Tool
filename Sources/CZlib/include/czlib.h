#ifndef CZLIB_H
#define CZLIB_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Inflates a raw DEFLATE stream (no zlib/gzip wrapper).
///
/// - Parameters:
///   - src: compressed input bytes.
///   - srcLen: compressed input length.
///   - dst: output buffer.
///   - dstLen: output buffer capacity.
/// - Returns: number of bytes written, or -1 on error / truncation.
long czlib_inflate_raw(const uint8_t *src,
                       size_t srcLen,
                       uint8_t *dst,
                       size_t dstLen);

#ifdef __cplusplus
}
#endif

#endif

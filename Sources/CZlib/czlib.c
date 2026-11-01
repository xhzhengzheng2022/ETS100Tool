#include "include/czlib.h"

#include <string.h>
#include <zlib.h>

long czlib_inflate_raw(const uint8_t *src,
                       size_t srcLen,
                       uint8_t *dst,
                       size_t dstLen) {
    if (src == NULL || dst == NULL) {
        return -1;
    }

    z_stream stream;
    memset(&stream, 0, sizeof(stream));
    stream.next_in = (Bytef *)src;
    stream.avail_in = (uInt)srcLen;
    stream.next_out = (Bytef *)dst;
    stream.avail_out = (uInt)dstLen;

    if (inflateInit2(&stream, -MAX_WBITS) != Z_OK) {
        return -1;
    }

    int status = inflate(&stream, Z_FINISH);
    long written = (long)stream.total_out;
    inflateEnd(&stream);

    if (status != Z_STREAM_END) {
        return -1;
    }
    return written;
}

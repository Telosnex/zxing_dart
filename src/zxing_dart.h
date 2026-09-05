// zxing_dart — stable C ABI over a pinned zxing-cpp.
//
// Design rules (see image_ffmpeg/doc/PORTING_C_LIBRARIES.md):
//   * Coarse-grained calls: whole frame in, whole result out.
//   * Fixed-width integer types only; no enums in the ABI (int32_t instead).
//   * Caller allocates result structs; callee allocates variable-size members
//     with the Dart-VM-compatible allocator (see dart_alloc.h) and the caller
//     frees them via the paired _release fn (from C) or ffi.malloc.free
//     (from Dart).
//   * No exceptions cross this boundary. Every fn is total: it returns a
//     status code and never throws or unwinds.
//   * ABI changes bump ZXD_ABI_VERSION; Dart refuses to run on mismatch.
#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#define ZXD_NOEXCEPT noexcept
#else
#define ZXD_NOEXCEPT
#endif

#if defined(_WIN32)
#define ZXD_EXPORT __declspec(dllexport)
#else
#define ZXD_EXPORT __attribute__((visibility("default")))
#endif

#define ZXD_ABI_VERSION 3

// ---------------------------------------------------------------------------
// Status codes (returned as int32_t).
// ---------------------------------------------------------------------------
#define ZXD_OK 0
#define ZXD_NOT_FOUND 1        // no barcode detected (not an error)
#define ZXD_INVALID_ARGUMENT 2 // bad pointer/dimensions/format/payload
#define ZXD_ENCODE_ERROR 3     // payload not encodable
#define ZXD_INTERNAL_ERROR 4   // unexpected exception inside zxing-cpp

// ---------------------------------------------------------------------------
// Pixel formats for zxd_read.
// ---------------------------------------------------------------------------
#define ZXD_PIXEL_LUM8 0     // 8-bit luminance. Camera Y-plane. Fast path.
#define ZXD_PIXEL_RGBA8888 1 // 4 bytes/px, R first in memory.
#define ZXD_PIXEL_BGRA8888 2 // 4 bytes/px, B first in memory.

// ---------------------------------------------------------------------------
// Package-owned barcode format flags. Deliberately independent of zxing-cpp's
// internal ISO symbology IDs.
// ---------------------------------------------------------------------------
#define ZXD_FORMAT_ANY 0 // mask 0 == let zxing-cpp try all formats
#define ZXD_FORMAT_AZTEC (1 << 0)
#define ZXD_FORMAT_QR_CODE (1 << 1)
#define ZXD_FORMAT_DATA_MATRIX (1 << 2)

// ---------------------------------------------------------------------------
// zxd_read: decode one barcode from a pixel buffer.
// ---------------------------------------------------------------------------

typedef struct zxd_read_result {
    // Raw content bytes. Allocated with the Dart-compatible allocator; owned
    // by the caller after return. NULL iff bytes_len == 0.
    uint8_t* bytes;
    uint32_t bytes_len;
    // Content rendered as NUL-terminated UTF-8 text. Same ownership as
    // `bytes`. May be NULL.
    char* text;
    // Stable ZXD_FORMAT_* value of the decoded symbol (not an upstream enum).
    int32_t format;
    // Detection geometry in source-image pixel coordinates:
    // [TLx, TLy, TRx, TRy, BRx, BRy, BLx, BLy].
    int32_t corners[8];
} zxd_read_result;

// Decodes the first barcode found in `pixels`.
//
//   pixels           borrowed, never freed by this fn.
//   byte_length      total readable bytes at `pixels` (bounds-checked against
//                    width/height/row_stride before any pixel is touched).
//   row_stride_bytes bytes per row. 0 means "tightly packed"
//                    (width * bytes_per_pixel). Must otherwise be >=
//                    width * bytes_per_pixel. This is how camera Y-planes with
//                    padded rows are consumed zero-copy.
//   pixel_format     one of ZXD_PIXEL_*.
//   formats_mask     ZXD_FORMAT_* bits; 0 = all formats.
//   try_harder       nonzero enables tryHarder/tryRotate/tryInvert. Slower;
//                    intended for single still images, not camera streams.
//   out              caller-allocated; zeroed by this fn on entry. On ZXD_OK
//                    the caller owns the members and must call
//                    zxd_read_result_release (or free members from Dart).
//                    On any other status there is nothing to free.
ZXD_EXPORT int32_t zxd_read(
    const uint8_t* pixels,
    uint32_t byte_length,
    uint32_t width,
    uint32_t height,
    uint32_t row_stride_bytes,
    int32_t pixel_format,
    uint32_t formats_mask,
    int32_t try_harder,
    zxd_read_result* out) ZXD_NOEXCEPT;

// Frees the members of `result` (NOT `result` itself) and zeroes the struct.
// Safe to call multiple times, and safe on a zeroed struct.
ZXD_EXPORT void zxd_read_result_release(zxd_read_result* result) ZXD_NOEXCEPT;

// ---------------------------------------------------------------------------
// zxd_encode_aztec: payload in, module matrix out.
//
// Deliberately returns the symbol's bit matrix rather than pixels: rendering
// is the embedder's job (CustomPainter draws the modules; the visual layer
// around them is presentation, not codec).
// ---------------------------------------------------------------------------

typedef struct zxd_matrix {
    // Bit-packed modules, row-major, MSB-first within each byte, rows padded
    // to whole bytes: row_stride_bytes = (width + 7) / 8. Bit set = dark
    // module. Allocated with the Dart-compatible allocator; owned by the
    // caller after return.
    uint8_t* bits;
    uint32_t width;  // modules per row
    uint32_t height; // rows
} zxd_matrix;

// Encodes `payload` as an Aztec symbol.
//
//   payload      borrowed. Restricted to printable ASCII (0x20..0x7E). This is
//                a deliberate envelope contract, not a zxing limitation: the
//                pairing payload is `<prefix>:<base64url>` so that every
//                decoder in the fallback chain (Apple Vision, ML Kit, zxing)
//                round-trips it byte-exactly.
//   error_correction_percent  0..99, mapped by zxing-cpp/zint to the closest
//                supported Aztec level (10/23/36/50), or -1 for its default.
//   out          caller-allocated; zeroed on entry. On ZXD_OK caller owns
//                `bits` and must call zxd_matrix_release (or free from Dart).
ZXD_EXPORT int32_t zxd_encode_aztec(
    const uint8_t* payload,
    uint32_t payload_length,
    int32_t error_correction_percent,
    zxd_matrix* out) ZXD_NOEXCEPT;

// Encodes `payload` as a symbol of the single format named by `format`
// (one ZXD_FORMAT_* bit; masks with multiple bits are rejected).
//
// Added in ABI 3.
//
//   format       ZXD_FORMAT_AZTEC or ZXD_FORMAT_DATA_MATRIX. QR is decode-only
//                for now: no consumer needs QR writing, and an untested writer
//                path is a liability, not a feature.
//   error_correction_percent  Aztec: 0..99 or -1 (see zxd_encode_aztec).
//                DataMatrix: must be -1. Its Reed-Solomon budget is fixed by
//                symbol size; accepting a percentage here would silently lie.
//                DataMatrix output is always square (zint forceSquare):
//                rectangular DMRE sizes would break renderer aspect-ratio
//                assumptions for some payload lengths.
//   Other parameters and ownership are identical to zxd_encode_aztec.
ZXD_EXPORT int32_t zxd_encode(
    const uint8_t* payload,
    uint32_t payload_length,
    uint32_t format,
    int32_t error_correction_percent,
    zxd_matrix* out) ZXD_NOEXCEPT;

// Frees `matrix->bits` (NOT `matrix` itself) and zeroes the struct. Safe to
// call multiple times, and safe on a zeroed struct.
ZXD_EXPORT void zxd_matrix_release(zxd_matrix* matrix) ZXD_NOEXCEPT;

// Returns ZXD_ABI_VERSION of the loaded binary. Dart checks this before any
// other call and refuses to run on mismatch.
ZXD_EXPORT int32_t zxd_abi_version(void) ZXD_NOEXCEPT;

// Returns a process-lifetime, NUL-terminated ASCII build description owned by
// the library. The caller must not free it.
ZXD_EXPORT const char* zxd_build_info(void) ZXD_NOEXCEPT;

#ifdef __cplusplus
} // extern "C"
#endif

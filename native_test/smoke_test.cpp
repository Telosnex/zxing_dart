// End-to-end ABI smoke test: exercises zxing_dart strictly through the
// exported C ABI (no zxing-cpp headers), exactly as Dart will.
//
//   1. encode a pairing-envelope payload -> module matrix
//   2. rasterize the matrix to lum8 (scaled, white margin, padded stride)
//   3. read it back; assert byte-exact text and sane geometry
//   4. negative: noise image -> ZXD_NOT_FOUND
//   5. hostile args: overflow-y strides/dimensions -> ZXD_INVALID_ARGUMENT
//
// This is the day-one proof that the ABI round-trips. The full conformance
// corpus (synthetic camera torture, cross-decoder parity) lands separately.

#include "zxing_dart.h"

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

namespace {

int g_failures = 0;

#define CHECK(cond)                                                          \
    do {                                                                     \
        if (!(cond)) {                                                       \
            std::fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); \
            ++g_failures;                                                    \
        }                                                                    \
    } while (0)

bool matrixBit(const zxd_matrix& m, uint32_t x, uint32_t y)
{
    const uint32_t stride = (m.width + 7u) / 8u;
    return (m.bits[y * stride + (x >> 3)] & (0x80u >> (x & 7u))) != 0;
}

// Rasterize a module matrix to lum8: `scale` px per module, `margin` px of
// white on every side, rows padded with `rowPad` junk bytes to exercise the
// row_stride path.
struct Raster {
    std::vector<uint8_t> pixels;
    uint32_t width = 0;
    uint32_t height = 0;
    uint32_t stride = 0;
};

Raster rasterize(const zxd_matrix& m, uint32_t scale, uint32_t margin, uint32_t rowPad)
{
    Raster r;
    r.width = m.width * scale + margin * 2;
    r.height = m.height * scale + margin * 2;
    r.stride = r.width + rowPad;
    r.pixels.assign(static_cast<size_t>(r.stride) * r.height, 0xFF);
    // Fill pad bytes with junk so accidental reads of them break decoding.
    for (uint32_t y = 0; y < r.height; ++y) {
        for (uint32_t p = r.width; p < r.stride; ++p) {
            r.pixels[static_cast<size_t>(y) * r.stride + p] =
                static_cast<uint8_t>(y * 31u + p);
        }
    }
    for (uint32_t my = 0; my < m.height; ++my) {
        for (uint32_t mx = 0; mx < m.width; ++mx) {
            if (!matrixBit(m, mx, my)) {
                continue;
            }
            for (uint32_t dy = 0; dy < scale; ++dy) {
                const size_t row =
                    static_cast<size_t>(margin + my * scale + dy) * r.stride;
                std::memset(&r.pixels[row + margin + mx * scale], 0x00, scale);
            }
        }
    }
    return r;
}

void testRoundTrip(const std::string& payload, int32_t eccLevel)
{
    zxd_matrix matrix;
    CHECK(zxd_encode_aztec(
              reinterpret_cast<const uint8_t*>(payload.data()),
              static_cast<uint32_t>(payload.size()), eccLevel, &matrix) == ZXD_OK);
    CHECK(matrix.width > 0 && matrix.height > 0 && matrix.bits != nullptr);
    std::printf("  aztec ecc=%d: %ux%u modules for %zu byte payload\n",
                eccLevel, matrix.width, matrix.height, payload.size());

    const Raster raster = rasterize(matrix, /*scale=*/4, /*margin=*/16, /*rowPad=*/13);

    zxd_read_result result;
    const int32_t status = zxd_read(
        raster.pixels.data(), static_cast<uint32_t>(raster.pixels.size()),
        raster.width, raster.height, raster.stride, ZXD_PIXEL_LUM8,
        ZXD_FORMAT_AZTEC, /*try_harder=*/1, &result);
    CHECK(status == ZXD_OK);
    if (status == ZXD_OK) {
        CHECK(result.text != nullptr && payload == result.text);
        CHECK(result.bytes_len == payload.size());
        CHECK(result.bytes != nullptr &&
              std::memcmp(result.bytes, payload.data(), payload.size()) == 0);
        CHECK(result.format == ZXD_FORMAT_AZTEC);
        // All corners inside the raster, spanning a plausibly symbol-sized box.
        for (int i = 0; i < 4; ++i) {
            CHECK(result.corners[i * 2] >= 0 &&
                  result.corners[i * 2] < static_cast<int32_t>(raster.width));
            CHECK(result.corners[i * 2 + 1] >= 0 &&
                  result.corners[i * 2 + 1] < static_cast<int32_t>(raster.height));
        }
        CHECK(result.corners[2] - result.corners[0] >
              static_cast<int32_t>(matrix.width));
    }
    zxd_read_result_release(&result);
    zxd_read_result_release(&result); // double-release must be safe
    zxd_matrix_release(&matrix);
    zxd_matrix_release(&matrix); // double-release must be safe
}

void testNotFound()
{
    // Deterministic xorshift noise; astronomically unlikely to decode.
    const uint32_t w = 320, h = 240;
    std::vector<uint8_t> noise(static_cast<size_t>(w) * h);
    uint32_t s = 0x243F6A88u;
    for (auto& px : noise) {
        s ^= s << 13; s ^= s >> 17; s ^= s << 5;
        px = static_cast<uint8_t>(s);
    }
    zxd_read_result result;
    CHECK(zxd_read(noise.data(), static_cast<uint32_t>(noise.size()), w, h, 0,
                   ZXD_PIXEL_LUM8, ZXD_FORMAT_AZTEC, 0, &result) == ZXD_NOT_FOUND);
    CHECK(result.bytes == nullptr && result.text == nullptr);
}

void testHostileArgs()
{
    std::vector<uint8_t> buf(64 * 64, 0xFF);
    const uint32_t len = static_cast<uint32_t>(buf.size());
    zxd_read_result r;
    // Claimed dimensions exceed the buffer.
    CHECK(zxd_read(buf.data(), len, 64, 65, 0, ZXD_PIXEL_LUM8, 0, 0, &r) ==
          ZXD_INVALID_ARGUMENT);
    // Stride smaller than a row.
    CHECK(zxd_read(buf.data(), len, 64, 64, 63, ZXD_PIXEL_LUM8, 0, 0, &r) ==
          ZXD_INVALID_ARGUMENT);
    // RGBA needs 4x the bytes.
    CHECK(zxd_read(buf.data(), len, 64, 64, 0, ZXD_PIXEL_RGBA8888, 0, 0, &r) ==
          ZXD_INVALID_ARGUMENT);
    // 32-bit overflow bait: width*height wraps if computed naively.
    CHECK(zxd_read(buf.data(), len, 0x10000u, 0x10000u, 0, ZXD_PIXEL_LUM8, 0, 0,
                   &r) == ZXD_INVALID_ARGUMENT);
    // Unknown pixel format / null pointers.
    CHECK(zxd_read(buf.data(), len, 64, 64, 0, 99, 0, 0, &r) == ZXD_INVALID_ARGUMENT);
    CHECK(zxd_read(nullptr, 0, 64, 64, 0, ZXD_PIXEL_LUM8, 0, 0, &r) ==
          ZXD_INVALID_ARGUMENT);
    CHECK(zxd_read(buf.data(), len, 64, 64, 0, ZXD_PIXEL_LUM8, 0, 0, nullptr) ==
          ZXD_INVALID_ARGUMENT);

    zxd_matrix m;
    // Non-ASCII payload rejected per envelope contract.
    const uint8_t binary[] = {0x74, 0x6E, 0x78, 0x00, 0xFF};
    CHECK(zxd_encode_aztec(binary, sizeof(binary), -1, &m) == ZXD_INVALID_ARGUMENT);
    const uint8_t ok[] = "tnx2:ok";
    CHECK(zxd_encode_aztec(ok, 7, 9, &m) == ZXD_INVALID_ARGUMENT);  // ecc out of range
    CHECK(zxd_encode_aztec(nullptr, 7, -1, &m) == ZXD_INVALID_ARGUMENT);
    CHECK(zxd_encode_aztec(ok, 0, -1, &m) == ZXD_INVALID_ARGUMENT);
}

} // namespace

int main()
{
    CHECK(zxd_abi_version() == ZXD_ABI_VERSION);

    // Representative pairing envelope: "tnx2:" + base64url(82-byte payload).
    testRoundTrip(
        "tnx2:"
        "VGhpc0lzQU5vbmNlMTIzNDU2Nzg5MGFiY2RlZmdoaWprbG1ub3BxcnN0dXZ3eHl6"
        "QUJDREVGR0hJSktMTU5PUFFSU1RVVldYWVo0OTg3NjU0MzIxMA",
        /*eccLevel=*/-1);
    // Highest ECC, short payload.
    testRoundTrip("tnx2:short", /*eccLevel=*/8);

    testNotFound();
    testHostileArgs();

    if (g_failures == 0) {
        std::printf("PASS: all smoke tests\n");
        return 0;
    }
    std::fprintf(stderr, "%d FAILURE(S)\n", g_failures);
    return 1;
}

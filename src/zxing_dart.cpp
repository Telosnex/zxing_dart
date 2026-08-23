// zxing_dart shim implementation. See zxing_dart.h for the ABI contract.
//
// Exception discipline: zxing-cpp throws; Dart FFI cannot unwind. Every
// exported fn is `noexcept` with a catch-all that maps to a status code.

#include "zxing_dart.h"

#include "dart_alloc.h"

// zxing-cpp (pinned; see tool/fetch_zxing.sh)
#include "BitMatrix.h"
#include "MultiFormatWriter.h"
#include "ReadBarcode.h"
#include "Version.h"

#include <cstring>
#include <initializer_list>
#include <string>
#include <utility>
#include <vector>

namespace {

ZXing::ImageFormat toImageFormat(int32_t pixelFormat) noexcept
{
    switch (pixelFormat) {
    case ZXD_PIXEL_LUM8:
        return ZXing::ImageFormat::Lum;
    case ZXD_PIXEL_RGBA8888:
        return ZXing::ImageFormat::RGBA;
    case ZXD_PIXEL_BGRA8888:
        return ZXing::ImageFormat::BGRA;
    default:
        return ZXing::ImageFormat::None;
    }
}

uint32_t bytesPerPixel(ZXing::ImageFormat format) noexcept
{
    return format == ZXing::ImageFormat::Lum ? 1u : 4u;
}

// zxing-cpp 3.x replaced its historical bit-flag BarcodeFormat enum with ISO
// symbology/variant IDs. The C ABI intentionally keeps the v1 bit values, so
// never cast between these representations. This is the compatibility layer
// that makes the "stable C ABI" claim real across upstream major versions.
constexpr uint32_t kKnownFormatMask = (1u << 20) - 1;

ZXing::BarcodeFormats toZxingFormats(uint32_t mask)
{
    using F = ZXing::BarcodeFormat;
    std::vector<F> formats;
    const auto add = [&formats, mask](uint32_t bit, std::initializer_list<F> values) {
        if ((mask & bit) != 0)
            formats.insert(formats.end(), values.begin(), values.end());
    };

    add(1u << 0, {F::Aztec});
    add(1u << 1, {F::Codabar});
    add(1u << 2, {F::Code39});
    add(1u << 3, {F::Code93});
    add(1u << 4, {F::Code128});
    add(1u << 5, {F::DataBarOmni, F::DataBarStk, F::DataBarStkOmni});
    add(1u << 6, {F::DataBarExp, F::DataBarExpStk});
    add(1u << 7, {F::DataMatrix});
    add(1u << 8, {F::EAN8});
    add(1u << 9, {F::EAN13});
    add(1u << 10, {F::ITF});
    add(1u << 11, {F::MaxiCode});
    add(1u << 12, {F::PDF417, F::CompactPDF417});
    // In 2.x QRCode excluded MicroQRCode and RMQRCode. Use explicit model
    // variants rather than v3's broader QRCode symbology selector.
    add(1u << 13, {F::QRCodeModel1, F::QRCodeModel2});
    add(1u << 14, {F::UPCA});
    add(1u << 15, {F::UPCE});
    add(1u << 16, {F::MicroQRCode});
    add(1u << 17, {F::RMQRCode});
    add(1u << 18, {F::DXFilmEdge});
    add(1u << 19, {F::DataBarLtd});
    return ZXing::BarcodeFormats(std::move(formats));
}

int32_t fromZxingFormat(ZXing::BarcodeFormat format) noexcept
{
    using F = ZXing::BarcodeFormat;
    switch (format) {
    case F::Aztec:
    case F::AztecCode:
    case F::AztecRune: return 1 << 0;
    case F::Codabar: return 1 << 1;
    case F::Code39:
    case F::Code39Std:
    case F::Code39Ext:
    case F::Code32:
    case F::PZN: return 1 << 2;
    case F::Code93: return 1 << 3;
    case F::Code128: return 1 << 4;
    case F::DataBar:
    case F::DataBarOmni:
    case F::DataBarStk:
    case F::DataBarStkOmni: return 1 << 5;
    case F::DataBarExp:
    case F::DataBarExpStk: return 1 << 6;
    case F::DataMatrix: return 1 << 7;
    case F::EAN8: return 1 << 8;
    case F::EAN13:
    case F::ISBN: return 1 << 9;
    case F::ITF:
    case F::ITF14: return 1 << 10;
    case F::MaxiCode: return 1 << 11;
    case F::PDF417:
    case F::CompactPDF417:
    case F::MicroPDF417: return 1 << 12;
    case F::QRCode:
    case F::QRCodeModel1:
    case F::QRCodeModel2: return 1 << 13;
    case F::UPCA: return 1 << 14;
    case F::UPCE: return 1 << 15;
    case F::MicroQRCode: return 1 << 16;
    case F::RMQRCode: return 1 << 17;
    case F::DXFilmEdge: return 1 << 18;
    case F::DataBarLtd: return 1 << 19;
    default: return 0; // v3-only formats have no representation in ABI v1.
    }
}

} // namespace

extern "C" {

int32_t zxd_abi_version(void) noexcept
{
    return ZXD_ABI_VERSION;
}

const char* zxd_build_info(void) noexcept
{
    return "zxing_dart ABI 1; zxing-cpp " ZXING_VERSION_STR;
}

int32_t zxd_read(
    const uint8_t* pixels,
    uint32_t byte_length,
    uint32_t width,
    uint32_t height,
    uint32_t row_stride_bytes,
    int32_t pixel_format,
    uint32_t formats_mask,
    int32_t try_harder,
    zxd_read_result* out) noexcept
{
    if (out == nullptr) {
        return ZXD_INVALID_ARGUMENT;
    }
    std::memset(out, 0, sizeof(*out));

    if (pixels == nullptr || width == 0 || height == 0) {
        return ZXD_INVALID_ARGUMENT;
    }
    const ZXing::ImageFormat format = toImageFormat(pixel_format);
    if (format == ZXing::ImageFormat::None) {
        return ZXD_INVALID_ARGUMENT;
    }
    if ((formats_mask & ~kKnownFormatMask) != 0) {
        return ZXD_INVALID_ARGUMENT;
    }

    // Bounds-check the caller's claim before zxing touches a single pixel.
    // All math in uint64_t: width/height/stride are attacker-influencable
    // (camera plane descriptors), so 32-bit overflow here would be a
    // heap-overread primitive.
    const uint64_t bpp = bytesPerPixel(format);
    const uint64_t rowBytes = static_cast<uint64_t>(width) * bpp;
    const uint64_t stride =
        row_stride_bytes == 0 ? rowBytes : static_cast<uint64_t>(row_stride_bytes);
    if (stride < rowBytes) {
        return ZXD_INVALID_ARGUMENT;
    }
    const uint64_t required = stride * (static_cast<uint64_t>(height) - 1) + rowBytes;
    if (required > static_cast<uint64_t>(byte_length)) {
        return ZXD_INVALID_ARGUMENT;
    }
    // ImageView takes int; reject anything that would wrap.
    if (width > INT32_MAX || height > INT32_MAX || stride > INT32_MAX) {
        return ZXD_INVALID_ARGUMENT;
    }

    try {
        const ZXing::ImageView image(
            pixels,
            static_cast<int>(width),
            static_cast<int>(height),
            format,
            static_cast<int>(stride),
            /*pixStride=*/0);

        ZXing::ReaderOptions options;
        if (formats_mask != ZXD_FORMAT_ANY) {
            options.setFormats(toZxingFormats(formats_mask));
        }
        const bool harder = try_harder != 0;
        options.setTryHarder(harder);
        options.setTryRotate(harder);
        options.setTryInvert(harder);
        options.setMaxNumberOfSymbols(1);

        const auto results = ZXing::ReadBarcodes(image, options);
        if (results.empty() || !results.front().isValid()) {
            return ZXD_NOT_FOUND;
        }
        const auto& result = results.front();

        const auto& contentBytes = result.bytes();
        if (!contentBytes.empty()) {
            out->bytes = dart_malloc<uint8_t>(contentBytes.size());
            std::memcpy(out->bytes, contentBytes.data(), contentBytes.size());
            out->bytes_len = static_cast<uint32_t>(contentBytes.size());
        }

        const std::string text = result.text();
        out->text = dart_malloc<char>(text.size() + 1);
        std::memcpy(out->text, text.data(), text.size());
        out->text[text.size()] = '\0';

        out->format = fromZxingFormat(result.format());

        const auto& position = result.position();
        const auto storeCorner = [out](int index, ZXing::PointI point) {
            out->corners[index * 2] = point.x;
            out->corners[index * 2 + 1] = point.y;
        };
        storeCorner(0, position.topLeft());
        storeCorner(1, position.topRight());
        storeCorner(2, position.bottomRight());
        storeCorner(3, position.bottomLeft());

        return ZXD_OK;
    } catch (...) {
        zxd_read_result_release(out);
        return ZXD_INTERNAL_ERROR;
    }
}

void zxd_read_result_release(zxd_read_result* result) noexcept
{
    if (result == nullptr) {
        return;
    }
    dart_free(result->bytes);
    dart_free(result->text);
    std::memset(result, 0, sizeof(*result));
}

int32_t zxd_encode_aztec(
    const uint8_t* payload,
    uint32_t payload_length,
    int32_t ecc_level,
    zxd_matrix* out) noexcept
{
    if (out == nullptr) {
        return ZXD_INVALID_ARGUMENT;
    }
    std::memset(out, 0, sizeof(*out));

    if (payload == nullptr || payload_length == 0) {
        return ZXD_INVALID_ARGUMENT;
    }
    if (ecc_level < -1 || ecc_level > 8) {
        return ZXD_INVALID_ARGUMENT;
    }
    // Envelope contract: printable ASCII only (see header).
    for (uint32_t i = 0; i < payload_length; ++i) {
        if (payload[i] < 0x20 || payload[i] > 0x7E) {
            return ZXD_INVALID_ARGUMENT;
        }
    }

    try {
#if defined(__GNUC__)
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"
#endif
        // Deliberate compatibility choice; see ZXING_WRITERS=OLD in CMake.
        ZXing::MultiFormatWriter writer(ZXing::BarcodeFormat::Aztec);
#if defined(__GNUC__)
#pragma GCC diagnostic pop
#endif
        // Margin is presentation; the embedder decides quiet-zone treatment.
        writer.setMargin(0);
        if (ecc_level >= 0) {
            writer.setEccLevel(ecc_level);
        }

        const std::string contents(reinterpret_cast<const char*>(payload), payload_length);
        // width/height 0 => un-inflated matrix: exactly one cell per module.
        const ZXing::BitMatrix matrix = writer.encode(contents, /*width=*/0, /*height=*/0);

        const int width = matrix.width();
        const int height = matrix.height();
        if (width <= 0 || height <= 0) {
            return ZXD_ENCODE_ERROR;
        }

        const uint32_t rowStride = (static_cast<uint32_t>(width) + 7u) / 8u;
        const size_t totalBytes = static_cast<size_t>(rowStride) * static_cast<size_t>(height);
        out->bits = dart_malloc<uint8_t>(totalBytes);
        std::memset(out->bits, 0, totalBytes);
        for (int y = 0; y < height; ++y) {
            uint8_t* row = out->bits + static_cast<size_t>(y) * rowStride;
            for (int x = 0; x < width; ++x) {
                if (matrix.get(x, y)) {
                    row[x >> 3] |= static_cast<uint8_t>(0x80u >> (x & 7));
                }
            }
        }
        out->width = static_cast<uint32_t>(width);
        out->height = static_cast<uint32_t>(height);

        return ZXD_OK;
    } catch (...) {
        zxd_matrix_release(out);
        return ZXD_ENCODE_ERROR;
    }
}

void zxd_matrix_release(zxd_matrix* matrix) noexcept
{
    if (matrix == nullptr) {
        return;
    }
    dart_free(matrix->bits);
    std::memset(matrix, 0, sizeof(*matrix));
}

} // extern "C"

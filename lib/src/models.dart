import 'dart:typed_data';

/// Execution engine behind [ZxingDart].
enum ZxingRuntime {
  /// A pinned native code asset called through `dart:ffi`.
  native,

  /// A pinned Emscripten module running in a Web Worker.
  webAssembly,

  /// No backend exists for this platform.
  unsupported,
}

/// Runtime information discovered while loading the package.
final class ZxingCapabilities {
  const ZxingCapabilities({
    required this.runtime,
    required this.abiVersion,
    required this.buildInfo,
    required this.canReadBarcodes,
    required this.canEncodeAztec,
  });

  final ZxingRuntime runtime;
  final int abiVersion;
  final String buildInfo;
  final bool canReadBarcodes;
  final bool canEncodeAztec;

  @override
  String toString() =>
      'ZxingCapabilities(runtime: $runtime, abiVersion: $abiVersion, '
      'canReadBarcodes: $canReadBarcodes, canEncodeAztec: $canEncodeAztec, '
      'buildInfo: $buildInfo)';
}

/// Pixel layout accepted by [ZxingDart.readBarcode].
///
/// For mobile camera frames, [luminance8] should point at the Y plane and
/// [rowStride] should be the camera-provided bytes-per-row. This avoids an
/// RGBA conversion and avoids repacking padded rows.
enum BarcodePixelFormat {
  luminance8(0, 1),
  rgba8888(1, 4),
  bgra8888(2, 4);

  const BarcodePixelFormat(this.nativeValue, this.bytesPerPixel);

  final int nativeValue;
  final int bytesPerPixel;
}

/// Barcode symbologies currently exposed by the stable Dart API.
enum BarcodeFormat {
  aztec(1),
  qrCode(1 << 13);

  const BarcodeFormat(this.nativeValue);

  final int nativeValue;

  static BarcodeFormat? fromNativeValue(int value) {
    for (final format in values) {
      if (format.nativeValue == value) return format;
    }
    return null;
  }
}

/// One point in source-image pixel coordinates.
final class BarcodePoint {
  const BarcodePoint(this.x, this.y);

  final int x;
  final int y;

  @override
  bool operator ==(Object other) =>
      other is BarcodePoint && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'BarcodePoint($x, $y)';
}

/// Detection geometry in source-image coordinates, in visual corner order.
final class BarcodePosition {
  const BarcodePosition({
    required this.topLeft,
    required this.topRight,
    required this.bottomRight,
    required this.bottomLeft,
  });

  final BarcodePoint topLeft;
  final BarcodePoint topRight;
  final BarcodePoint bottomRight;
  final BarcodePoint bottomLeft;

  List<BarcodePoint> get corners =>
      List.unmodifiable([topLeft, topRight, bottomRight, bottomLeft]);
}

/// A successfully decoded barcode.
final class BarcodeResult {
  BarcodeResult({
    required Uint8List bytes,
    required this.text,
    required this.nativeFormat,
    required this.position,
  }) : bytes = Uint8List.fromList(bytes).asUnmodifiableView();

  /// An unmodifiable, caller-owned copy of the raw content bytes.
  final Uint8List bytes;

  /// zxing-cpp's UTF-8 representation of the content.
  final String text;

  /// The raw `ZXing::BarcodeFormat` value, retained for forward compatibility.
  final int nativeFormat;

  BarcodeFormat? get format => BarcodeFormat.fromNativeValue(nativeFormat);

  final BarcodePosition position;
}

/// A bit-packed machine-readable symbol, ready for a custom renderer.
///
/// Bits are row-major and MSB-first within each byte. Rows are independently
/// padded to whole bytes; a set bit is a dark module. The constructor copies
/// [bits], so the matrix never aliases native/Wasm memory.
final class BarcodeMatrix {
  BarcodeMatrix({
    required this.width,
    required this.height,
    required Uint8List bits,
  }) : bits = Uint8List.fromList(bits).asUnmodifiableView() {
    if (width <= 0 || height <= 0) {
      throw ArgumentError('Barcode matrix dimensions must be positive');
    }
    if (this.bits.length != rowStride * height) {
      throw ArgumentError.value(
        this.bits.length,
        'bits.length',
        'expected ${rowStride * height} for a $width x $height matrix',
      );
    }
    // Padding bits are canonical zero. Enforcing this makes matrices compare,
    // hash, serialize, and render identically across native and Wasm backends.
    final usedBitsInLastByte = width & 7;
    if (usedBitsInLastByte != 0) {
      final paddingMask = (1 << (8 - usedBitsInLastByte)) - 1;
      for (var y = 0; y < height; y++) {
        if ((this.bits[y * rowStride + rowStride - 1] & paddingMask) != 0) {
          throw ArgumentError.value(bits, 'bits', 'nonzero row padding bits');
        }
      }
    }
  }

  final int width;
  final int height;
  final Uint8List bits;

  int get rowStride => (width + 7) ~/ 8;

  bool isDark(int x, int y) {
    if (x < 0 || x >= width) {
      throw RangeError.range(x, 0, width - 1, 'x');
    }
    if (y < 0 || y >= height) {
      throw RangeError.range(y, 0, height - 1, 'y');
    }
    return (bits[y * rowStride + (x >> 3)] & (0x80 >> (x & 7))) != 0;
  }
}

/// An error returned by the portable C ABI or Wasm equivalent.
final class ZxingException implements Exception {
  const ZxingException(this.status, this.message);

  final int status;
  final String message;

  @override
  String toString() => 'ZxingException($status): $message';
}

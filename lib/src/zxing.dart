import 'dart:convert';
import 'dart:typed_data';

import 'backend/backend.dart';
import 'backend/backend_stub.dart'
    if (dart.library.ffi) 'backend/backend_native.dart'
    as platform;
import 'models.dart';

/// Cross-platform entry point for the pinned zxing-cpp build.
///
/// The API is asynchronous on every platform. Native work runs on a helper
/// isolate; browser work will run in a Web Worker. Initialization is lazy and
/// shared. This package intentionally does not own a camera or any widgets.
abstract final class ZxingDart {
  static Future<ZxingBackend>? _backend;

  static Future<ZxingBackend> _getBackend() => _backend ??= _loadBackend();

  static Future<ZxingBackend> _loadBackend() async {
    try {
      return await platform.loadBackend();
    } on Object {
      // A failed code-asset load or ABI check must not poison future attempts.
      _backend = null;
      rethrow;
    }
  }

  /// Loads the shared backend if necessary and reports its capabilities.
  static Future<ZxingCapabilities> get capabilities async =>
      (await _getBackend()).capabilities;

  /// Decodes the first matching barcode in an unpacked pixel buffer.
  ///
  /// For camera frames, pass the Y plane as [BarcodePixelFormat.luminance8]
  /// and preserve the camera's [rowStride]; no RGBA conversion or row repack is
  /// needed. A null [formats] lets zxing-cpp try every compiled symbology; the
  /// default limits work to Aztec. Returns null when no symbol is found.
  ///
  /// Do not mutate [pixels] until the returned Future completes. The helper
  /// isolate creates its own copy before native decoding begins.
  static Future<BarcodeResult?> readBarcode(
    Uint8List pixels, {
    required int width,
    required int height,
    int rowStride = 0,
    BarcodePixelFormat pixelFormat = BarcodePixelFormat.luminance8,
    Set<BarcodeFormat>? formats = const {BarcodeFormat.aztec},
    bool tryHarder = false,
  }) async {
    _validateFrame(
      pixels,
      width: width,
      height: height,
      rowStride: rowStride,
      pixelFormat: pixelFormat,
    );
    if (formats != null && formats.isEmpty) {
      throw ArgumentError.value(
        formats,
        'formats',
        'must be nonempty, or null to try every format',
      );
    }
    var formatsMask = 0;
    if (formats != null) {
      for (final format in formats) {
        formatsMask |= format.nativeValue;
      }
    }
    final snapshot = platform.snapshotBytes(pixels);
    return (await _getBackend()).readBarcode(
      snapshot,
      width: width,
      height: height,
      rowStride: rowStride,
      pixelFormat: pixelFormat,
      formatsMask: formatsMask,
      tryHarder: tryHarder,
    );
  }

  /// Encodes printable ASCII as an Aztec module matrix.
  ///
  /// [eccLevel] follows zxing-cpp's Aztec writer convention: -1 selects its
  /// default, otherwise use 0 through 8. Pairing payloads should be a canonical
  /// ASCII envelope such as `tnx2:<base64url>` rather than arbitrary binary, so
  /// fallback platform decoders round-trip the same content.
  static Future<BarcodeMatrix> encodeAztec(
    String payload, {
    int eccLevel = -1,
  }) async {
    if (payload.isEmpty) throw ArgumentError.value(payload, 'payload');
    if (eccLevel < -1 || eccLevel > 8) {
      throw ArgumentError.value(eccLevel, 'eccLevel', 'must be -1 or 0..8');
    }
    for (final codeUnit in payload.codeUnits) {
      if (codeUnit < 0x20 || codeUnit > 0x7e) {
        throw ArgumentError.value(
          payload,
          'payload',
          'must contain printable ASCII only',
        );
      }
    }
    final bytes = Uint8List.fromList(ascii.encode(payload));
    _validateUint32(bytes.length, 'payload.length');
    return (await _getBackend()).encodeAztec(bytes, eccLevel: eccLevel);
  }

  static void _validateFrame(
    Uint8List pixels, {
    required int width,
    required int height,
    required int rowStride,
    required BarcodePixelFormat pixelFormat,
  }) {
    if (pixels.isEmpty) throw ArgumentError.value(pixels, 'pixels');
    if (width <= 0 || width > 0x7fffffff) {
      throw ArgumentError.value(width, 'width', 'must fit a positive int32');
    }
    if (height <= 0 || height > 0x7fffffff) {
      throw ArgumentError.value(height, 'height', 'must fit a positive int32');
    }
    if (rowStride < 0 || rowStride > 0x7fffffff) {
      throw ArgumentError.value(rowStride, 'rowStride', 'must fit int32');
    }
    _validateUint32(pixels.length, 'pixels.length');

    final rowBytes = width * pixelFormat.bytesPerPixel;
    final effectiveStride = rowStride == 0 ? rowBytes : rowStride;
    if (effectiveStride < rowBytes || effectiveStride > 0x7fffffff) {
      throw ArgumentError.value(
        rowStride,
        'rowStride',
        'must be zero or at least $rowBytes bytes',
      );
    }
    final requiredLength = effectiveStride * (height - 1) + rowBytes;
    if (requiredLength > pixels.length) {
      throw ArgumentError.value(
        pixels.length,
        'pixels.length',
        'need at least $requiredLength bytes for the supplied geometry',
      );
    }
  }

  static void _validateUint32(int value, String name) {
    if (value < 0 || value > 0xffffffff) {
      throw ArgumentError.value(value, name, 'must fit uint32');
    }
  }
}

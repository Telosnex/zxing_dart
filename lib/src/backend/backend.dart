import 'dart:typed_data';

import '../models.dart';

/// Internal contract implemented by native FFI and browser Wasm adapters.
abstract interface class ZxingBackend {
  ZxingCapabilities get capabilities;

  Future<BarcodeResult?> readBarcode(
    Uint8List pixels, {
    required int width,
    required int height,
    required int rowStride,
    required BarcodePixelFormat pixelFormat,
    required int formatsMask,
    required bool tryHarder,
  });

  Future<BarcodeMatrix> encodeAztec(
    Uint8List asciiPayload, {
    required int errorCorrectionPercent,
  });
}

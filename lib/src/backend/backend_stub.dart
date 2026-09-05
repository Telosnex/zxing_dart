import 'dart:typed_data';

import '../models.dart';
import 'backend.dart';

Uint8List snapshotBytes(Uint8List bytes) => bytes;

Future<ZxingBackend> loadBackend() async => const _UnsupportedBackend();

final class _UnsupportedBackend implements ZxingBackend {
  const _UnsupportedBackend();

  @override
  ZxingCapabilities get capabilities => const ZxingCapabilities(
    runtime: ZxingRuntime.unsupported,
    abiVersion: 0,
    buildInfo: 'No zxing_dart backend for this platform',
    canReadBarcodes: false,
    canEncodeAztec: false,
    canEncodeDataMatrix: false,
  );

  @override
  Future<BarcodeResult?> readBarcode(
    Uint8List pixels, {
    required int width,
    required int height,
    required int rowStride,
    required BarcodePixelFormat pixelFormat,
    required int formatsMask,
    required bool tryHarder,
  }) => throw const ZxingException(4, 'Unsupported platform');

  @override
  Future<BarcodeMatrix> encodeAztec(
    Uint8List asciiPayload, {
    required int errorCorrectionPercent,
  }) => throw const ZxingException(4, 'Unsupported platform');

  @override
  Future<BarcodeMatrix> encodeDataMatrix(Uint8List asciiPayload) =>
      throw const ZxingException(4, 'Unsupported platform');
}

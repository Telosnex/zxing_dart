import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';
import 'package:zxing_dart/zxing_dart.dart';

import 'support/platform_setup_stub.dart'
    if (dart.library.js_interop) 'support/platform_setup_web.dart';

const _pairingPayload =
    'tnx2:'
    'VGhpc0lzQU5vbmNlMTIzNDU2Nzg5MGFiY2RlZmdoaWprbG1ub3BxcnN0dXZ3eHl6'
    'QUJDREVGR0hJSktMTU5PUFFSU1RVVldYWVo0OTg3NjU0MzIxMA';

void main() {
  configureZxingTestPlatform();

  test('capabilities load once and validate the pinned backend', () async {
    final first = await ZxingDart.capabilities;
    final second = await ZxingDart.capabilities;

    expect(identical(first, second), isTrue);
    expect(first.runtime, expectedRuntime);
    expect(first.abiVersion, 1);
    expect(first.buildInfo, 'zxing_dart ABI 1; zxing-cpp 3.1.1');
    expect(first.canReadBarcodes, isTrue);
    expect(first.canEncodeAztec, isTrue);
  });

  test('Aztec encode returns canonical painter-ready modules', () async {
    final matrix = await ZxingDart.encodeAztec(_pairingPayload);

    expect((matrix.width, matrix.height), (41, 41));
    expect(matrix.rowStride, 6);
    expect(matrix.bits.length, matrix.rowStride * matrix.height);
    // Locks the renderer-facing modules across the 2.3.0 -> 3.1.1 upgrade.
    // The classic writer is deliberate until a versioned API can express the
    // new zint-backed writer's different ECC semantics.
    expect(
      sha256.convert(matrix.bits).toString(),
      'bd57bfd2509940860a3303b52b09e00cd7c8d3446938656e7e7cc15a428a24c2',
    );
    expect(() => matrix.bits[0] = 0, throwsUnsupportedError);
    // Aztec's central bullseye is dark at the exact center.
    expect(matrix.isDark(matrix.width ~/ 2, matrix.height ~/ 2), isTrue);
    // Width 41 leaves seven padding bits in every row; they stay canonical 0.
    for (var y = 0; y < matrix.height; y++) {
      expect(
        matrix.bits[y * matrix.rowStride + matrix.rowStride - 1] & 0x7f,
        0,
      );
    }
    expect(() => matrix.isDark(-1, 0), throwsRangeError);
    expect(() => matrix.isDark(matrix.width, 0), throwsRangeError);
  });

  for (final pixelFormat in BarcodePixelFormat.values) {
    test('round-trips through ${pixelFormat.name} with padded rows', () async {
      final matrix = await ZxingDart.encodeAztec(_pairingPayload);
      final raster = _rasterize(
        matrix,
        pixelFormat: pixelFormat,
        scale: 4,
        margin: 16,
        rowPadding: 13,
      );
      final before = Uint8List.fromList(raster.bytes);

      final result = await ZxingDart.readBarcode(
        raster.bytes,
        width: raster.width,
        height: raster.height,
        rowStride: raster.stride,
        pixelFormat: pixelFormat,
        tryHarder: true,
      );

      expect(result, isNotNull);
      expect(result!.text, _pairingPayload);
      expect(result.bytes, ascii.encode(_pairingPayload));
      expect(() => result.bytes[0] = 0, throwsUnsupportedError);
      expect(result.format, BarcodeFormat.aztec);
      expect(result.nativeFormat, BarcodeFormat.aztec.nativeValue);
      expect(raster.bytes, before, reason: 'decode must not mutate input');
      for (final corner in result.position.corners) {
        expect(corner.x, inInclusiveRange(0, raster.width - 1));
        expect(corner.y, inInclusiveRange(0, raster.height - 1));
      }
    });
  }

  test('format filtering and no-symbol result are nonexceptional', () async {
    final matrix = await ZxingDart.encodeAztec('tnx2:format-filter');
    final raster = _rasterize(matrix);

    expect(
      await ZxingDart.readBarcode(
        raster.bytes,
        width: raster.width,
        height: raster.height,
        rowStride: raster.stride,
        formats: const {BarcodeFormat.qrCode},
        tryHarder: true,
      ),
      isNull,
    );

    final white = Uint8List(160 * 120)..fillRange(0, 160 * 120, 0xff);
    expect(await ZxingDart.readBarcode(white, width: 160, height: 120), isNull);
  });

  test('parallel calls remain isolated and deterministic', () async {
    final payloads = [
      for (var index = 0; index < 12; index++) 'tnx2:item-$index',
    ];
    final matrices = await Future.wait(
      payloads.map((payload) => ZxingDart.encodeAztec(payload, eccLevel: 8)),
    );
    final results = await Future.wait([
      for (var index = 0; index < matrices.length; index++)
        _readMatrix(matrices[index]),
    ]);

    expect([for (final result in results) result!.text], payloads);
  });

  test('validates all frame geometry before crossing FFI', () {
    expect(
      () => ZxingDart.readBarcode(Uint8List(0), width: 1, height: 1),
      throwsArgumentError,
    );
    expect(
      () => ZxingDart.readBarcode(Uint8List(4), width: 0, height: 1),
      throwsArgumentError,
    );
    expect(
      () => ZxingDart.readBarcode(Uint8List(3), width: 2, height: 2),
      throwsArgumentError,
    );
    expect(
      () => ZxingDart.readBarcode(
        Uint8List(16),
        width: 2,
        height: 2,
        rowStride: 7,
        pixelFormat: BarcodePixelFormat.rgba8888,
      ),
      throwsArgumentError,
    );
    expect(
      () => ZxingDart.readBarcode(
        Uint8List(4),
        width: 2,
        height: 2,
        formats: const {},
      ),
      throwsArgumentError,
    );
  });

  test('validates Aztec envelope and ECC before crossing FFI', () {
    expect(() => ZxingDart.encodeAztec(''), throwsArgumentError);
    expect(() => ZxingDart.encodeAztec('tnx2:\u0000'), throwsArgumentError);
    expect(() => ZxingDart.encodeAztec('tnx2:é'), throwsArgumentError);
    expect(
      () => ZxingDart.encodeAztec('tnx2:ok', eccLevel: -2),
      throwsArgumentError,
    );
    expect(
      () => ZxingDart.encodeAztec('tnx2:ok', eccLevel: 9),
      throwsArgumentError,
    );
  });

  test('BarcodeMatrix rejects malformed and noncanonical storage', () {
    expect(
      () => BarcodeMatrix(width: 9, height: 1, bits: Uint8List(1)),
      throwsArgumentError,
    );
    expect(
      () => BarcodeMatrix(
        width: 9,
        height: 1,
        bits: Uint8List.fromList([0x00, 0x01]),
      ),
      throwsArgumentError,
    );

    final matrix = BarcodeMatrix(
      width: 9,
      height: 1,
      bits: Uint8List.fromList([0x80, 0x80]),
    );
    expect(matrix.isDark(0, 0), isTrue);
    expect(matrix.isDark(8, 0), isTrue);
    expect(matrix.isDark(1, 0), isFalse);
  });
}

Future<BarcodeResult?> _readMatrix(BarcodeMatrix matrix) {
  final raster = _rasterize(matrix);
  return ZxingDart.readBarcode(
    raster.bytes,
    width: raster.width,
    height: raster.height,
    rowStride: raster.stride,
    tryHarder: true,
  );
}

final class _Raster {
  const _Raster({
    required this.bytes,
    required this.width,
    required this.height,
    required this.stride,
  });

  final Uint8List bytes;
  final int width;
  final int height;
  final int stride;
}

_Raster _rasterize(
  BarcodeMatrix matrix, {
  BarcodePixelFormat pixelFormat = BarcodePixelFormat.luminance8,
  int scale = 4,
  int margin = 16,
  int rowPadding = 13,
}) {
  final width = matrix.width * scale + margin * 2;
  final height = matrix.height * scale + margin * 2;
  final rowBytes = width * pixelFormat.bytesPerPixel;
  final stride = rowBytes + rowPadding;
  final bytes = Uint8List(stride * height)..fillRange(0, stride * height, 0xff);

  // Poison padding bytes; a decoder that mistakes width for stride or reads
  // beyond a row sees deterministic noise rather than a convenient white pad.
  for (var y = 0; y < height; y++) {
    for (var offset = rowBytes; offset < stride; offset++) {
      bytes[y * stride + offset] = (y * 31 + offset) & 0xff;
    }
  }

  for (var moduleY = 0; moduleY < matrix.height; moduleY++) {
    for (var moduleX = 0; moduleX < matrix.width; moduleX++) {
      if (!matrix.isDark(moduleX, moduleY)) continue;
      for (var dy = 0; dy < scale; dy++) {
        for (var dx = 0; dx < scale; dx++) {
          final x = margin + moduleX * scale + dx;
          final y = margin + moduleY * scale + dy;
          final offset = y * stride + x * pixelFormat.bytesPerPixel;
          switch (pixelFormat) {
            case BarcodePixelFormat.luminance8:
              bytes[offset] = 0;
            case BarcodePixelFormat.rgba8888:
            case BarcodePixelFormat.bgra8888:
              bytes
                ..[offset] = 0
                ..[offset + 1] = 0
                ..[offset + 2] = 0
                ..[offset + 3] = 0xff;
          }
        }
      }
    }
  }

  return _Raster(bytes: bytes, width: width, height: height, stride: stride);
}

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:barcode/barcode.dart';
import 'package:barcode/src/barcode_2d.dart';
import 'package:test/test.dart';
import 'package:zxing_dart/zxing_dart.dart';

import 'support/platform_setup_stub.dart'
    if (dart.library.js_interop) 'support/platform_setup_web.dart';
import 'support/synthetic_camera_corpus.dart';

void main() {
  configureZxingTestPlatform();

  late BarcodeMatrix zxingMatrix;
  late List<SyntheticCameraCase> primaryCorpus;

  setUpAll(() async {
    zxingMatrix = await ZxingDart.encodeAztec(syntheticPairingPayload);
    primaryCorpus = buildSyntheticCameraCorpus(zxingMatrix);
  });

  test('v1 recipe manifest is complete, unique, and camera-shaped', () {
    expect(primaryCorpus, hasLength(40));
    expect(primaryCorpus.map((testCase) => testCase.id).toSet(), hasLength(40));
    final tags = primaryCorpus.expand((testCase) => testCase.tags).toSet();
    expect(
      tags,
      containsAll(const {
        'rotation',
        'perspective',
        'resolution',
        'defocus',
        'motion-blur',
        'contrast',
        'sensor-noise',
        'exposure',
        'lighting',
        'vignette',
        'glare',
        'moire',
        'display-capture',
        'row-stride',
        'negative',
      }),
    );
    for (final testCase in primaryCorpus) {
      final frame = testCase.frame;
      expect(testCase.id, startsWith('v$syntheticCorpusVersion/'));
      expect(frame.width, greaterThan(0), reason: testCase.id);
      expect(frame.height, greaterThan(0), reason: testCase.id);
      expect(
        frame.rowStride,
        greaterThanOrEqualTo(frame.width * frame.pixelFormat.bytesPerPixel),
        reason: testCase.id,
      );
      expect(
        frame.bytes.length,
        frame.rowStride * frame.height,
        reason: testCase.id,
      );
    }
  });

  test(
    '40-case camera torture corpus decodes exactly or rejects safely',
    () async {
      for (final testCase in primaryCorpus) {
        final result = await _decode(testCase);
        switch (testCase.expectation) {
          case SyntheticExpectation.decodes:
            expect(result, isNotNull, reason: _reason(testCase));
            _expectExactResult(testCase, result!);
          case SyntheticExpectation.notFound:
            expect(result, isNull, reason: _reason(testCase));
        }
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'independent pure-Dart Aztec encoder survives hard transform subset',
    () async {
      final independent = _encodeWithPureDart(
        Barcode.aztec(),
        syntheticPairingPayload,
      );
      // package:barcode is a separate pure-Dart implementation. Canonical
      // inputs can legitimately produce the same modules as zxing-cpp, which
      // is useful parity rather than evidence of a self-round-trip.
      expect(identical(independent.bits, zxingMatrix.bits), isFalse);
      expect((independent.width, independent.height), (41, 41));
      final corpus = buildHardTransformCorpus(
        independent,
        expectedText: syntheticPairingPayload,
      );
      expect(corpus, hasLength(10));
      for (final testCase in corpus) {
        final result = await _decode(testCase);
        expect(result, isNotNull, reason: _reason(testCase));
        _expectExactResult(testCase, result!);
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'stable QR format translation survives the hard transform subset',
    () async {
      const payload = 'tnx2:qr-format-translation';
      final matrix = _encodeWithPureDart(Barcode.qrCode(), payload);
      final corpus = buildHardTransformCorpus(matrix, expectedText: payload);
      expect(corpus, hasLength(10));
      for (final testCase in corpus) {
        final frame = testCase.frame;
        final result = await ZxingDart.readBarcode(
          frame.bytes,
          width: frame.width,
          height: frame.height,
          rowStride: frame.rowStride,
          pixelFormat: frame.pixelFormat,
          formats: const {BarcodeFormat.qrCode},
          tryHarder: true,
        );
        expect(result, isNotNull, reason: _reason(testCase));
        _expectExactResult(
          testCase,
          result!,
          expectedFormat: BarcodeFormat.qrCode,
        );
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'compact highest-ECC symbol survives the hard transform subset',
    () async {
      const payload = 'tnx2:short-high-ecc';
      final matrix = await ZxingDart.encodeAztec(payload, eccLevel: 8);
      expect(matrix.width, lessThan(zxingMatrix.width));
      final corpus = buildHardTransformCorpus(matrix, expectedText: payload);
      expect(corpus, hasLength(10));
      for (final testCase in corpus) {
        final result = await _decode(testCase);
        expect(result, isNotNull, reason: _reason(testCase));
        _expectExactResult(testCase, result!);
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

Future<BarcodeResult?> _decode(SyntheticCameraCase testCase) {
  final frame = testCase.frame;
  return ZxingDart.readBarcode(
    frame.bytes,
    width: frame.width,
    height: frame.height,
    rowStride: frame.rowStride,
    pixelFormat: frame.pixelFormat,
    formats: const {BarcodeFormat.aztec},
    tryHarder: true,
  );
}

void _expectExactResult(
  SyntheticCameraCase testCase,
  BarcodeResult result, {
  BarcodeFormat expectedFormat = BarcodeFormat.aztec,
}) {
  expect(result.text, testCase.expectedText, reason: _reason(testCase));
  expect(
    result.bytes,
    ascii.encode(testCase.expectedText!),
    reason: _reason(testCase),
  );
  expect(result.format, expectedFormat, reason: _reason(testCase));

  final frame = testCase.frame;
  final corners = result.position.corners;
  for (final corner in corners) {
    expect(
      corner.x,
      inInclusiveRange(0, frame.width - 1),
      reason: _reason(testCase),
    );
    expect(
      corner.y,
      inInclusiveRange(0, frame.height - 1),
      reason: _reason(testCase),
    );
  }
  final detectedCenterX =
      corners.fold<int>(0, (sum, point) => sum + point.x) / corners.length;
  final detectedCenterY =
      corners.fold<int>(0, (sum, point) => sum + point.y) / corners.length;
  expect(
    math.sqrt(
      math.pow(detectedCenterX - testCase.symbolCenterX, 2) +
          math.pow(detectedCenterY - testCase.symbolCenterY, 2),
    ),
    lessThan(55),
    reason: '${_reason(testCase)}; detection geometry points at wrong object',
  );
  var twiceArea = 0;
  for (var index = 0; index < corners.length; index++) {
    final point = corners[index];
    final next = corners[(index + 1) % corners.length];
    twiceArea += point.x * next.y - next.x * point.y;
  }
  expect(
    twiceArea.abs(),
    greaterThan(1000),
    reason: '${_reason(testCase)}; degenerate detection geometry',
  );
}

BarcodeMatrix _encodeWithPureDart(Barcode encoder, String payload) {
  if (encoder is! Barcode2D) {
    throw StateError('package:barcode encoder stopped being two-dimensional');
  }
  final source = encoder.convert(Uint8List.fromList(ascii.encode(payload)));
  final pixels = source.pixels.toList(growable: false);
  final rowStride = (source.width + 7) ~/ 8;
  final bits = Uint8List(rowStride * source.height);
  for (var y = 0; y < source.height; y++) {
    for (var x = 0; x < source.width; x++) {
      if (pixels[y * source.width + x]) {
        bits[y * rowStride + (x >> 3)] |= 0x80 >> (x & 7);
      }
    }
  }
  return BarcodeMatrix(width: source.width, height: source.height, bits: bits);
}

String _reason(SyntheticCameraCase testCase) =>
    '${testCase.id} tags=${testCase.tags.join(',')}';

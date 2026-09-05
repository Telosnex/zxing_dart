import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:zxing_dart/zxing_dart.dart';

import 'support/platform_setup_stub.dart'
    if (dart.library.js_interop) 'support/platform_setup_web.dart';

/// DataMatrix write + read, both polarities. DataMatrix has no bullseye: its
/// finder is an L-shaped solid border plus a dashed clock track, which is why
/// it is the preferred substrate for stylized-but-decodable rendering.
void main() {
  setUpAll(configureZxingTestPlatform);

  const payload = 'tnx2:BMsvLUirbPB9-W9jZQhAXbXmEg';

  test('encodeDataMatrix produces a square symbol that round-trips', () async {
    final matrix = await ZxingDart.encodeDataMatrix(payload);
    expect(matrix.width, matrix.height, reason: 'square DM expected');
    expect(matrix.width, greaterThanOrEqualTo(18));

    for (final inverted in [false, true]) {
      const scale = 12, quietZone = 3;
      final side = (matrix.width + quietZone * 2) * scale;
      final image = Uint8List(side * side);
      for (var py = 0; py < side; py++) {
        for (var px = 0; px < side; px++) {
          final mx = px ~/ scale - quietZone;
          final my = py ~/ scale - quietZone;
          final dark = mx >= 0 &&
              my >= 0 &&
              mx < matrix.width &&
              my < matrix.height &&
              matrix.isDark(mx, my);
          final value = dark ? 20 : 235;
          image[py * side + px] = inverted ? 255 - value : value;
        }
      }
      final result = await ZxingDart.readBarcode(
        image,
        width: side,
        height: side,
        formats: const {BarcodeFormat.dataMatrix},
        tryHarder: true,
      );
      expect(result, isNotNull, reason: 'inverted=$inverted');
      expect(result!.text, payload, reason: 'inverted=$inverted');
      expect(result.format, BarcodeFormat.dataMatrix);
    }
  });

  test('encodeDataMatrix rejects non-ASCII payloads', () {
    expect(
      () => ZxingDart.encodeDataMatrix('tnx2:\u00e9'),
      throwsArgumentError,
    );
  });
}

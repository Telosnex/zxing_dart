import 'dart:typed_data';

import 'package:zxing_dart/zxing_dart.dart';

/// Encodes a payload as an Aztec symbol, draws it into a grayscale image and
/// reads it back.
Future<void> main() async {
  final matrix = await ZxingDart.encodeAztec('tnx2:hello');

  // One module is 4 x 4 pixels, with a quiet zone of 4 modules.
  const scale = 4;
  const quiet = 4;
  final width = (matrix.width + 2 * quiet) * scale;
  final height = (matrix.height + 2 * quiet) * scale;
  final pixels = Uint8List(width * height)..fillRange(0, width * height, 255);
  for (var y = 0; y < matrix.height; y++) {
    for (var x = 0; x < matrix.width; x++) {
      if (!matrix.isDark(x, y)) continue;
      for (var dy = 0; dy < scale; dy++) {
        final row = ((y + quiet) * scale + dy) * width;
        final start = row + (x + quiet) * scale;
        pixels.fillRange(start, start + scale, 0);
      }
    }
  }

  final result = await ZxingDart.readBarcode(
    pixels,
    width: width,
    height: height,
    pixelFormat: BarcodePixelFormat.luminance8,
  );
  print('${result?.format}: ${result?.text}'); // BarcodeFormat.aztec: tnx2:hello
}

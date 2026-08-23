// Reproduce one synthetic camera case as a portable-graymap image.
//
//   dart run tool/render_synthetic_case.dart v1/glare-edge /tmp/glare.pgm
//   dart run tool/render_synthetic_case.dart --list
//
// PGM is intentionally trivial and lossless: ImageMagick, Preview, ffmpeg, and
// most image viewers can open it, while the corpus itself remains generated.
import 'dart:io';
import 'dart:typed_data';

import 'package:zxing_dart/zxing_dart.dart';

import '../test/support/synthetic_camera_corpus.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length == 1 && arguments.single == '--list') {
    final cases = await _buildCases();
    for (final testCase in cases) {
      stdout.writeln(
        '${testCase.id}\t${testCase.expectation.name}\t'
        '${testCase.tags.join(',')}',
      );
    }
    return;
  }
  if (arguments.length != 2) {
    stderr.writeln(
      'Usage: dart run tool/render_synthetic_case.dart '
      '<v$syntheticCorpusVersion/case-id> <output.pgm>\n'
      '       dart run tool/render_synthetic_case.dart --list',
    );
    exitCode = 64;
    return;
  }

  final requested = arguments[0].startsWith('v')
      ? arguments[0]
      : 'v$syntheticCorpusVersion/${arguments[0]}';
  final cases = await _buildCases();
  final matches = cases.where((testCase) => testCase.id == requested);
  if (matches.isEmpty) {
    stderr.writeln('Unknown synthetic case: $requested (use --list)');
    exitCode = 64;
    return;
  }
  final testCase = matches.single;
  final frame = testCase.frame;
  final luminance = Uint8List(frame.width * frame.height);
  for (var y = 0; y < frame.height; y++) {
    for (var x = 0; x < frame.width; x++) {
      luminance[y * frame.width + x] = frame
          .bytes[y * frame.rowStride + x * frame.pixelFormat.bytesPerPixel];
    }
  }
  final header = Uint8List.fromList(
    'P5\n# ${testCase.id} tags=${testCase.tags.join(',')}\n'
            '${frame.width} ${frame.height}\n255\n'
        .codeUnits,
  );
  final output = File(arguments[1]);
  await output.writeAsBytes([...header, ...luminance], flush: true);
  stdout.writeln('wrote ${output.path}');
  stdout.writeln('case=${testCase.id}');
  stdout.writeln('expectation=${testCase.expectation.name}');
  stdout.writeln('pixelFormat=${frame.pixelFormat.name}');
  stdout.writeln('rowStride=${frame.rowStride}');
}

Future<List<SyntheticCameraCase>> _buildCases() async {
  final matrix = await ZxingDart.encodeAztec(syntheticPairingPayload);
  return buildSyntheticCameraCorpus(matrix);
}

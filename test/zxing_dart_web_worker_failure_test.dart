@TestOn('browser')
library;

import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:zxing_dart/zxing_dart.dart';

Future<BarcodeResult?> _request(int delay, int value) {
  final bytes = Uint8List.fromList([delay, value, 8, 9, 10]);
  return ZxingDart.readBarcode(bytes, width: bytes.length, height: 1);
}

void main() {
  setUpAll(() {
    ZxingDartWeb.workerCount = 1;
    ZxingDartWeb.workerUri = Uri.parse('support/pool_test_worker.mjs');
  });

  tearDownAll(() {
    ZxingDartWeb.workerCount = 1;
    ZxingDartWeb.workerUri = null;
  });

  test('one Worker serializes operations', () async {
    final stopwatch = Stopwatch()..start();
    final results = await Future.wait([_request(65, 10), _request(65, 11)]);
    stopwatch.stop();

    expect(results.map((result) => result!.text), ['10', '11']);
    expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(110));
  });

  test('a normal codec error does not poison its Worker', () async {
    await expectLater(
      _request(254, 1),
      throwsA(
        isA<ZxingException>().having((error) => error.status, 'status', 2),
      ),
    );
    expect((await _request(0, 73))!.text, '73');
  });

  test('a failed Worker is replaced and queued work continues once', () async {
    final failed = expectLater(
      _request(255, 1),
      throwsA(
        isA<ZxingException>().having((error) => error.status, 'status', -2),
      ),
    );
    final queued = _request(0, 83);

    await failed;
    expect((await queued)!.text, '83');
  });
}

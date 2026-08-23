@TestOn('browser')
library;

import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:zxing_dart/zxing_dart.dart';

Uint8List _requestBytes(int delay, int value, List<int> marker) =>
    Uint8List.fromList([delay, value, ...marker]);

Future<BarcodeResult?> _request(Uint8List bytes) => ZxingDart.readBarcode(
  bytes,
  width: bytes.length,
  height: 1,
  formats: const {BarcodeFormat.aztec},
);

void main() {
  setUpAll(() {
    ZxingDartWeb.workerCount = 2;
    ZxingDartWeb.workerUri = Uri.parse('support/pool_test_worker.mjs');
  });

  tearDownAll(() {
    ZxingDartWeb.workerCount = 1;
    ZxingDartWeb.workerUri = null;
  });

  test('two operations overlap with two independent Wasm Workers', () async {
    final marker = List<int>.generate(
      6,
      (index) => DateTime.now().microsecondsSinceEpoch >> (index * 8) & 0xff,
    );
    final results = await Future.wait([
      _request(_requestBytes(80, 10, marker)),
      _request(_requestBytes(80, 11, marker)),
    ]);

    expect(results.map((result) => result!.text), contains('2'));
  });

  test('central queue snapshots before dispatch and remains FIFO', () async {
    final completionOrder = <String>[];
    Future<void> run(int delay, int value) async {
      final result = await _request(
        _requestBytes(delay, value, [value, 91, 37]),
      );
      completionOrder.add(result!.text);
    }

    final first = run(180, 10);
    final second = run(70, 20);
    final bytes = _requestBytes(0, 30, [30, 91, 37]);
    final queued = _request(bytes);
    bytes[1] = 99;
    final fourth = run(0, 40);

    expect((await queued)!.text, '30');
    await Future.wait([first, second, fourth]);
    expect(completionOrder, ['20', '40', '10']);
    expect(bytes[1], 99);
  });
}

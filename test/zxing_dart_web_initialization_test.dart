@TestOn('browser')
library;

import 'package:test/test.dart';
import 'package:zxing_dart/zxing_dart.dart';

void main() {
  test('initialization failures do not poison a corrected retry', () async {
    ZxingDartWeb.workerCount = 0;
    await expectLater(ZxingDart.capabilities, throwsRangeError);

    ZxingDartWeb.workerCount = 1;
    ZxingDartWeb.workerUri = Uri.parse('support/abi_mismatch_worker.mjs');
    await expectLater(
      ZxingDart.capabilities,
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('ABI mismatch'),
        ),
      ),
    );

    ZxingDartWeb.workerUri = Uri.parse(
      'packages/zxing_dart/web/definitely_missing.mjs',
    );
    await expectLater(
      ZxingDart.capabilities,
      throwsA(
        isA<ZxingException>()
            .having((error) => error.status, 'status', -2)
            .having(
              (error) => error.message,
              'message',
              contains('definitely_missing.mjs'),
            ),
      ),
    );

    ZxingDartWeb.workerUri = Uri.parse(
      'packages/zxing_dart/web/zxing_dart_worker.mjs',
    );
    final capabilities = await ZxingDart.capabilities;
    expect(capabilities.runtime, ZxingRuntime.webAssembly);
    expect(capabilities.buildInfo, contains('zxing-cpp 2.3.0'));
  });
}

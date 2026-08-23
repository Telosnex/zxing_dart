import 'package:zxing_dart/zxing_dart.dart';

/// package:test maps packages/zxing_dart/ to this package's lib/ directory.
void configureZxingTestPlatform() {
  ZxingDartWeb.workerCount = 1;
  ZxingDartWeb.workerUri = Uri.parse(
    'packages/zxing_dart/web/zxing_dart_worker.mjs',
  );
}

ZxingRuntime get expectedRuntime => ZxingRuntime.webAssembly;

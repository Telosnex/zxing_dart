/// A pinned zxing-cpp behind one asynchronous Dart API.
///
/// Native platforms use a verified code asset through `dart:ffi`; browsers use
/// a separately compiled WebAssembly module behind the same API. The package
/// is camera-agnostic and UI-free.
library;

export 'src/zxing.dart' show ZxingDart;
export 'src/models.dart'
    show
        BarcodeFormat,
        BarcodeMatrix,
        BarcodePixelFormat,
        BarcodePoint,
        BarcodePosition,
        BarcodeResult,
        ZxingCapabilities,
        ZxingException,
        ZxingRuntime;

/// zxing_dart: one Dart API over a pinned zxing-cpp, native + web.
///
/// Status: milestone 1 (C ABI + macos-arm64 artifact + native smoke test).
/// The Dart facade lands in milestone 2 (ffigen bindings + helper-isolate
/// backend), following image_ffmpeg's backend/backend_{native,web,stub}.dart
/// conditional-import pattern:
///
///   ZxingDart.readBarcode(frame)   -> ReadResult?   (bytes, text, corners)
///   ZxingDart.encodeAztec(payload) -> ModuleMatrix  (bit-packed, painter-ready)
///
/// Deliberately camera-agnostic: callers hand this library pixel buffers
/// (camera Y-plane, decoded image, canvas ImageData) and draw encoded symbols
/// themselves. No camera plugin, image codec, or widget dependencies.
library;

// TODO(milestone 2): ffigen bindings against src/zxing_dart.h, backend facade,
// helper isolate, abi_version handshake.

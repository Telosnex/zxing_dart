## 0.1.0-dev

- Add a stable six-call C ABI over pinned zxing-cpp 2.3.0.
- Add asynchronous Dart encode/decode API with native helper-isolate backend.
- Add bundled Emscripten WebAssembly Worker backend and browser pool.
- Add SHA-256-pinned production artifacts for Android armv7/arm64/x64, iOS
  device/simulator, macOS arm64/x64, Linux arm64/x64, Windows x64, and web.
- Add native, VM, Chrome dart2js, Chrome dart2wasm, Safari, iOS Simulator,
  Android emulator, Linux container, and Windows/Wine conformance gates.
- Add deterministic synthetic camera corpus v1: 40 stable recipes and 60
  decode tasks per backend across zxing-cpp, an independent pure-Dart Aztec
  writer, and a compact high-ECC symbol.
- Add 6,144 deterministic malformed frame/descriptor ABI cases and an
  AddressSanitizer/UndefinedBehaviorSanitizer gate.

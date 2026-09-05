## 0.1.0-dev

- Add a stable seven-call C ABI over pinned zxing-cpp.
- Add asynchronous Aztec/Data Matrix encode and barcode decode APIs with a
  native helper-isolate backend.
- Add bundled Emscripten WebAssembly Worker backend and browser pool.
- Add SHA-256-pinned production artifacts for Android armv7/arm64/x64, iOS
  device/simulator, macOS arm64/x64, Linux arm64/x64, Windows x64, and web.
- Add native, VM, Chrome dart2js, Chrome dart2wasm, Safari, iOS Simulator,
  Android emulator, Linux container, and Windows/Wine conformance gates.
- Add deterministic synthetic camera corpus v1: 40 stable recipes and 70
  decode tasks per backend across zxing-cpp, an independent pure-Dart Aztec
  writer, a compact high-ECC symbol, and a QR format-translation bridge.
- Add 6,144 deterministic malformed frame/descriptor ABI cases and an
  AddressSanitizer/UndefinedBehaviorSanitizer gate.
- Upgrade zxing-cpp from 2.3.0 to 3.1.1 and adopt its bundled zint 2.16.0
  production writer. ABI 2 uses package-owned format flags and percentage-based
  Aztec error correction rather than preserving unreleased legacy semantics.
- Add ABI 3 generic encoding and Data Matrix format support, including square
  symbols on native and Web backends.
- Move native compilation to C++20. Preserve Linux glibc 2.31 using pinned GCC
  12-on-bullseye images; use pinned MinGW GCC 12 for Windows.

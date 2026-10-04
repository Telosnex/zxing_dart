# zxing_dart

A pinned [zxing-cpp](https://github.com/zxing-cpp/zxing-cpp) behind a small
stable C ABI, with one universal Dart entrypoint. Native backends via FFI +
committed, SHA-256-pinned artifacts; web backend via an Emscripten module and
worker. Third application of the porting template documented in
`image_ffmpeg/doc/PORTING_C_LIBRARIES.md` (after fllama and fonnx; this repo
follows image_ffmpeg, the most refined iteration).

Built for the Telosnex E2EE device-linking flow (Aztec pairing symbols), but
deliberately generic: bytes-in/bytes-out, camera-agnostic, UI-free.

## Why not an existing package?

Evaluated in depth (see `../flutter_zxing_audit` while it exists):

* `flutter_zxing` — validated the architecture; its `dart_alloc.h` allocator
  discipline is adopted here (MIT, attributed in-file). Not consumable for a
  security flow: no web, consumer-compiled submodule builds, documented
  fork-breakage, hard camera/UI coupling, no row-stride support, 143 lines of
  tests.
* `mobile_scanner` — three different proprietary decoders (ML Kit / Vision /
  BarcodeDetector) with per-platform behavior variance and a CDN-fetched WASM
  fallback. Kept as a fallback adapter behind the app-side reader interface.

## Layout

```text
src/zxing_dart.{h,cpp}   C ABI shim: read, encode, and release calls
src/dart_alloc.h         Dart-VM-symmetric allocator (from flutter_zxing, MIT)
native_test/             ABI-only C++ conformance tests (no zxing headers)
tool/fetch_zxing.sh      pinned fetch (commit hash verified post-checkout)
tool/build_macos.sh      milestone-1 build: macos-arm64 + smoke test
lib/                     Dart facade (milestone 2)
native_artifacts/        committed pinned binaries + complete manifest
```

## ABI rules

Documented in `src/zxing_dart.h`; highlights:

* No exceptions cross the boundary; every fn returns a status `int32_t`.
* All buffer claims bounds-checked in `uint64_t` before any pixel is read
  (camera plane descriptors are treated as attacker-influenced).
* Variable-size outputs allocated with `dart_allocator` so Dart's
  `ffi.malloc.free` is always symmetric; every result has a paired,
  double-call-safe `_release`.
* Encode returns a bit-packed **module matrix**, not pixels: rendering is the
  embedder's job (`CustomPainter` draws modules; visual styling stays outside
  the codec).
* Payloads are printable ASCII by contract (`tnx2:<base64url>` envelope) so
  every decoder in the fallback chain round-trips byte-exactly.

## Provenance

| Component | Version | License | Pin |
|---|---|---|---|
| zxing-cpp | v3.1.1 | Apache-2.0 | `287c85df6f961c8efbfb5ffd736cd9457b8b890e` |
| zint writer | v2.16.0 | BSD-3-Clause | `55541e139e62b9209b71cd9b0ba9010cec28b1d9` |
| dart_alloc.h | flutter_zxing 2.3.0 | MIT | adapted, attributed in-file |
| `barcode` test oracle | 2.2.9 | Apache-2.0 | exact dev-dependency pin |

The 2.3.0 → 3.1.1 API/toolchain/size analysis is recorded in
[`doc/ZXING_CPP_3_1_1_UPGRADE.md`](doc/ZXING_CPP_3_1_1_UPGRADE.md).

Pin bumps are reviewed changes accompanied by a full conformance run.

## Build & test (milestone 1)

```bash
tool/build_macos.sh   # fetch pin, build, run native smoke test
tool/build_all_native.sh # all twelve native production tuples
tool/build_web.sh     # pinned Emscripten ES module + Wasm
dart test             # verifies code-asset hash, ABI, Dart/FFI/isolate path
tool/test_all.sh      # VM + Chrome dart2js + Chrome dart2wasm + Safari
tool/test_ios_simulator.sh
ZXD_ANDROID_AVD=Medium_Phone_API_36.0 tool/test_android_device.sh
tool/test_linux_docker.sh linux-arm64
tool/test_linux_docker.sh linux-x64
tool/test_linux_dart_docker.sh linux-arm64
tool/test_linux_dart_docker.sh linux-x64
tool/test_windows_wine_docker.sh
tool/test_windows_dart_wine_docker.sh # x64 Linux CI host
tool/test_native_sanitizers.sh         # ABI corpus under ASan + UBSan

# Reproduce any synthetic camera scene as a lossless image:
dart run tool/render_synthetic_case.dart --list
dart run tool/render_synthetic_case.dart v1/glare-edge /tmp/glare.pgm
```

## Dart API (milestone 2)

```dart
final matrix = await ZxingDart.encodeAztec('tnx2:<base64url>');
// Draw matrix.isDark(x, y) with a CustomPainter.

final result = await ZxingDart.readBarcode(
  cameraYPlane,
  width: frameWidth,
  height: frameHeight,
  rowStride: cameraBytesPerRow,
  // luminance8 + Aztec are the defaults.
);
if (result != null) {
  print(result.text);
  print(result.position.corners); // acquisition-overlay geometry
}
```

Native calls run on helper isolates. Returned bytes and module matrices are
copied out of C-owned memory, made unmodifiable, and remain valid after the
paired native release functions run. Frame geometry is checked in Dart and
again in C using overflow-safe arithmetic.

Web calls use the same C ABI compiled with Emscripten. Each Wasm runtime lives
in a module Worker; a bounded pool serializes one operation per runtime,
transfers private call-time snapshots, routes responses by request ID, and
replaces a Worker that crashes without replaying the failed operation. No CDN
or platform barcode service is used. The 1.3 MiB Wasm binary and its loader are
committed package assets with hashes in `native_artifacts/manifest.json`.

## Milestones

1. ✅ C ABI + macos-arm64 build + native ABI smoke test
2. ✅ ffigen bindings, Dart facade, helper-isolate backend, pinned macOS code
   asset hook, immutable typed models, 10 Dart API/FFI/isolate tests
3. ✅ Emscripten module + worker pool + loader, deterministic pinned web
   artifacts, VM/Chrome dart2js/Chrome dart2wasm/Safari parity suite, Worker
   initialization/error/replacement tests
4. ✅ Complete native matrix: Android armv7/arm64/x64, iOS arm64 device +
   arm64/x64 simulator, macOS arm64/x64, Linux arm64/x64, Windows arm64/x64;
   restricted export surfaces, static C++ runtimes where appropriate, 16KB
   Android pages, verified hashes, and runtime ABI tests on every OS family
   (Windows x64 under Wine; Windows arm64 on a Windows arm64 host).
5. ✅ Package-owned conformance v1: 40 deterministic camera recipes covering
   rotation/perspective/distance/blur/motion/glare/moiré/exposure/noise/stride
   and compound scenes; 70 tasks per backend across production, independent
   pure-Dart writer, high-ECC, and QR format-bridge profiles; 6,144 malformed
   C-ABI cases under
   ASan/UBSan. See `test/SYNTHETIC_CORPUS.md`.
6. Consumed by Telosnex `PairingCodeReader`/`PairingCodeRenderer` adapters;
   adapter acceptance adds parity against platform decoders on real devices.

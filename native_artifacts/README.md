# Pinned production artifacts

Production code assets selected by `hook/build.dart`. Every native file is one
self-contained shim library with zxing-cpp and libc++ (Android) statically
folded in. Consumers do not invoke CMake, CocoaPods, Gradle native dependencies,
a system zxing installation, or a CDN.

## Source and toolchain pins

- zxing-cpp `d6068bcebeb8fd9f0d35a99b00d202be86a14dbe` (`v2.3.0`)
- native build profile `2`
- Apple: Xcode 26 / Apple clang 17; macOS 12, iOS 13
- Android: NDK `28.2.13676358`, API 24, static libc++, 16KB page alignment
- Web: Emscripten 5.0.0 (`a7c5deabd7c88ba1c38ebe988112256775f944c6`)

Artifacts expose only the six `zxd_*` C ABI symbols. Upstream C++ symbols are
hidden by an exported-symbol list (Apple) or ELF version script (Android).
Licenses and notices are under `licenses/`.

## Complete intentional matrix

| Target | Minimum | SHA-256 |
|---|---:|---|
| macOS arm64 | 12 | `1e270cbc35b5fd39b36a4cfc4790d371cb4c594b4665154cb2fbab9a5431d895` |
| macOS x64 | 12 | `d3bd9606f5fb720d50862763d05f04d5219d6435073e366b5cb26f8642519d9f` |
| iOS arm64 device | 13 | `0957bb83b02d8e82bfab1a63595900b68606536d4ec3af008ddda1ad2dae53bc` |
| iOS arm64 simulator | 14¹ | `a434546d8d781dfcc9e6460c54c69b396034d5bc01fa3548db2cb580daad952e` |
| iOS x64 simulator | 13 | `3772bfb533e76da42be09185ce800923b91c73b33b809b15d30abbac1530bc08` |
| Android armv7 | API 24 | `3b3501bb9120ff72fc1f5e78ade0791e74de544382805984493b5ae4bc8dec54` |
| Android arm64 | API 24 | `bb311390877085e6c058a413d36ac260d23b134135b356226479588b9e3dbbac` |
| Android x64 | API 24 | `9fafd7d0ef35c7cd9781dc1b8460f8284efde63de109bb832e649675743b808d` |
| Browser Wasm | module Worker + Wasm | `6d05811c77c07eb044310e1c2871d964e78ca86268be1350679495c182b0e8fb` |

¹ arm64 Simulator did not exist before iOS 14; x64 covers iOS 13 simulators.

Linux and Windows are intentionally unsupported. Unsupported tuples fail in
the build hook rather than silently selecting an unpinned or system library.

## Reproduction and verification

```bash
tool/build_native_artifact.sh macos-arm64  # one tuple
tool/build_all_native.sh                   # all eight native tuples
tool/build_web.sh                          # deterministic web artifacts
dart run tool/verify_artifacts.dart        # all committed native + web hashes
```

Every native build starts from a clean target directory, checks the exact
source commit, validates architecture/platform/minimum OS, ensures no unbundled
ZXing/libc++ dependency, verifies the complete six-symbol export surface, and
checks the embedded ABI/build-info string. macOS builds additionally execute
the ABI-only encode/decode smoke test, including x64 under Rosetta on arm64.

Runtime smoke tests against the exact committed cross-built artifacts:

```bash
tool/test_ios_simulator.sh
ZXD_ANDROID_AVD=Medium_Phone_API_36.0 tool/test_android_device.sh
```

The first compiles a simulator executable, boots an available simulator, and
executes the complete encode/decode ABI suite. The second uses a connected
Android target or optionally starts an AVD, chooses the matching ABI artifact,
and executes the same suite through Android's real dynamic loader.

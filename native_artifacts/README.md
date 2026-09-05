# Pinned production artifacts

Production code assets selected by `hook/build.dart`. Every native file is one
self-contained shim library with zxing-cpp, its zint writer, and the applicable
non-Apple C++ runtime statically folded in. Consumers do not invoke CMake,
CocoaPods, Gradle native dependencies, a system installation, or a CDN.

## Source and toolchain pins

- zxing-cpp `287c85df6f961c8efbfb5ffd736cd9457b8b890e` (`v3.1.1`)
- zint `55541e139e62b9209b71cd9b0ba9010cec28b1d9` (`v2.16.0`, bundled writer)
- native build profile `5`
- Apple: Xcode 26 / Apple clang 17; macOS 12, iOS 13
- Android: NDK `28.2.13676358`, API 24, static libc++, 16KB page alignment
- Linux: pinned GCC 12.3-on-bullseye, glibc 2.31, static libstdc++/libgcc
- Windows: pinned Debian bookworm-slim, MinGW-w64 GCC 12 POSIX x64,
  static runtimes
- Web: Emscripten 5.0.0 (`a7c5deabd7c88ba1c38ebe988112256775f944c6`)

Artifacts expose only the six `zxd_*` C ABI symbols. Upstream C++ symbols are
hidden by an exported-symbol list (Apple), ELF version script (Android/Linux),
or module definition file (Windows).
Licenses and notices are under `licenses/`, including zint's backend BSD terms,
LLVM/libc++ for Android, GCC 12's GPLv3 text and Runtime Library Exception, and
MinGW notices for statically linked Linux/Windows runtime components.

## Complete intentional matrix

| Target | Minimum | SHA-256 |
|---|---:|---|
| macOS arm64 | 12 | `2ddf922675a7b4b59df37c0357c6f9a03cd3c6d77e66c80dec01153d2ab53083` |
| macOS x64 | 12 | `c2f461c663eab7d2c8bb5964f32da2becafe520062ff1c630abe909cdd418717` |
| iOS arm64 device | 13 | `8452cb1df0f70567eaa73dac9500a9e14adc81adebeb9fe06d6aaf22a44616c1` |
| iOS arm64 simulator | 14¹ | `3884400b8acd3aa4514363f1ad11989ea2b6bd22c1fb9fda2db6e683d35e7325` |
| iOS x64 simulator | 13 | `fbbbde46665a1dd6eae285683286c406a4646242d2b40c75add909ec16e02942` |
| Android armv7 | API 24 | `218f6e1e8b2436b26b737f95d51ecb648c7dca13b2ff9f2646812f2f8b439daa` |
| Android arm64 | API 24 | `94027f6a3757daabe2ea3f6e7c73909382e8ac8c7465faf452eac6af990db9fd` |
| Android x64 | API 24 | `c8ee68f38df80d4bb386b48dcfe00d070b56fe3cf729ed41052961a6b0eb39aa` |
| Linux arm64 | glibc 2.31 baseline | `9ba19fa0cfaf7913de18daa19c671596015788c4940c573384c457e99bf9c1c1` |
| Linux x64 | glibc 2.31 baseline | `74ff39cc088e99e0c8bef0518e11bdd4b62c1fd2a591bafcc7eb4fd7c3018f84` |
| Windows x64 | MinGW/Win32 | `e234d2452e6726ca13f31d93f594b32b3ef083b86bdb7a7dcb3bc65ce4156394` |
| Browser Wasm | module Worker + Wasm | `ff2de858491cd0fb718253927ba74bb0346d1dc72ec88ba3b9522f41e26df3fe` |

¹ arm64 Simulator did not exist before iOS 14; x64 covers iOS 13 simulators.

Unsupported architecture tuples fail in the build hook rather than silently
selecting an unpinned or system library.

## Reproduction and verification

```bash
tool/build_native_artifact.sh macos-arm64  # one tuple
tool/build_all_native.sh                   # all eleven native tuples
tool/build_web.sh                          # deterministic web artifacts
dart run tool/verify_artifacts.dart        # all committed native + web hashes
```

Every native build starts from a clean target directory, checks the exact
source commit, validates architecture/platform/minimum OS, ensures no unbundled
ZXing/libc++ dependency, verifies the complete seven-symbol export surface, and
checks the embedded ABI/build-info string. macOS builds additionally execute
the ABI-only encode/decode smoke test, including x64 under Rosetta on arm64.

Runtime smoke tests against the exact committed cross-built artifacts:

```bash
tool/test_ios_simulator.sh
ZXD_ANDROID_AVD=Medium_Phone_API_36.0 tool/test_android_device.sh
tool/test_linux_docker.sh linux-arm64
tool/test_linux_docker.sh linux-x64
tool/test_linux_dart_docker.sh linux-arm64
tool/test_linux_dart_docker.sh linux-x64
tool/test_windows_wine_docker.sh
tool/test_windows_dart_wine_docker.sh # x64 Linux CI host
```

The first compiles a simulator executable, boots an available simulator, and
executes the complete encode/decode ABI suite. The second uses a connected
Android target or optionally starts an AVD, chooses the matching ABI artifact,
and executes the same suite through Android's real dynamic loader. Linux
artifacts run in clean matching-architecture bullseye containers; the Windows
DLL runs through Wine's real PE loader against a freshly generated import
library from the canonical export definition. Additional pinned Dart-container
tests execute the public API and therefore cover build-hook target selection,
artifact hash verification, `@Native` lookup, helper isolates, and conversion
of owned C results on both Linux architectures and the Windows x64 Dart VM.

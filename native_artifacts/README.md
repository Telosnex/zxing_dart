# Pinned production artifacts

Production code assets selected by `hook/build.dart`. Every native file is one
self-contained shim library with zxing-cpp—and the applicable non-Apple C++
runtime—statically folded in. Consumers do not invoke CMake, CocoaPods, Gradle
native dependencies, a system zxing installation, or a CDN.

## Source and toolchain pins

- zxing-cpp `287c85df6f961c8efbfb5ffd736cd9457b8b890e` (`v3.1.1`)
- native build profile `4`
- Apple: Xcode 26 / Apple clang 17; macOS 12, iOS 13
- Android: NDK `28.2.13676358`, API 24, static libc++, 16KB page alignment
- Linux: pinned GCC 12.3-on-bullseye, glibc 2.31, static libstdc++/libgcc
- Windows: pinned Debian bookworm-slim, MinGW-w64 GCC 12 POSIX x64,
  static runtimes
- Web: Emscripten 5.0.0 (`a7c5deabd7c88ba1c38ebe988112256775f944c6`)

Artifacts expose only the six `zxd_*` C ABI symbols. Upstream C++ symbols are
hidden by an exported-symbol list (Apple), ELF version script (Android/Linux),
or module definition file (Windows).
Licenses and notices are under `licenses/`, including LLVM/libc++ for Android,
GCC 12's GPLv3 text and Runtime Library Exception, and MinGW notices for
statically linked Linux/Windows runtime components.

## Complete intentional matrix

| Target | Minimum | SHA-256 |
|---|---:|---|
| macOS arm64 | 12 | `edaebf613fb8ce9094ecf8c0476576fa58b87b54c52201c368e36fbb0e5b5b24` |
| macOS x64 | 12 | `6c9278ce2e9fb8d00ec741cdaa4184aa6c9fe78e17924cddf7dd7b7b6ac6d039` |
| iOS arm64 device | 13 | `4b3372d5d50a6f2a2d097ed37d45bea51e532b6c7b0c9ea35053a66cee0e4695` |
| iOS arm64 simulator | 14¹ | `12af8774185d43292598421593055b79f38ef3c8c3fdef66729001521a4537fa` |
| iOS x64 simulator | 13 | `1a0485ddc4471b3cd5d4b0d4dc819c34b0724b1cf7aca414852ceeaa6fda00e9` |
| Android armv7 | API 24 | `ae8f07033364f048ab6427e252247613432d6834b83cee1048fc0c48211182ca` |
| Android arm64 | API 24 | `75b9f109fcbb3c44045ce99c7d3cc882ea78656c4fc57f1bb4222ef517e992c6` |
| Android x64 | API 24 | `c29f0e291aa30f0f903f2603a5ccaae897e33c8bc8d9b1f5396a5970719b8a17` |
| Linux arm64 | glibc 2.31 baseline | `3709d7e991cd6ff9788d6400f94df20cee9fe2cb2a09b1876975b2526ffd44b9` |
| Linux x64 | glibc 2.31 baseline | `300f776be44e7ca133717a66acffa82a7a03cdd3a0b13d4bac7cd6407d40569c` |
| Windows x64 | MinGW/Win32 | `a8b54d40ace4a0d33e878fc619329bf327d9d747c3a6623c8c89646b51313d86` |
| Browser Wasm | module Worker + Wasm | `ff1f2d98b1ac85b22df85e6ea578c6aead8afba0606e8c2397bc098a159f4851` |

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
ZXing/libc++ dependency, verifies the complete six-symbol export surface, and
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

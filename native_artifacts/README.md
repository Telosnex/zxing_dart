# Native and web releases

`prebuilt.json` pins SHA-256-verified native libraries from an immutable GitHub
release, keyed by the build inputs. `web.json` pins the web runtime files of
the same release: the generated Emscripten module and Wasm binary, and the
hand-written worker and loader in `lib/web/` (kiln ADR 002).
`manifest.json` holds the upstream pins. No binary is in Git.

The release workflow runs the **same hook and source build** as local builds:
`dart run kiln:build`. It builds the web files with
`tool/kiln/build_web.dart` in the pinned `emscripten/emsdk:5.0.0` image and runs the
browser tests on them. All jobs must pass and agree on the source key
before publication (`.github/workflows/kiln_release.yml`). Only the repository owner can publish. Dry runs upload
Actions artifacts but do not create releases or push a manifest branch.

## Sources and runtime requirements

- zxing-cpp v3.1.1: `287c85df6f961c8efbfb5ffd736cd9457b8b890e`
- zint v2.16.0: `55541e139e62b9209b71cd9b0ba9010cec28b1d9`
- ABI 3, native profile 5, exactly seven `zxd_*` exports
- Web: Emscripten 5.0.0 (`a7c5deabd7c88ba1c38ebe988112256775f944c6`)

| Target | Minimum | Release builder |
|---|---|---|
| macOS arm64 / x64 | macOS 12 | macos-15, Xcode |
| iOS arm64 device | iOS 13 | macos-15, Xcode |
| iOS arm64 / x64 simulator | iOS 14 / 13 | macos-15, Xcode |
| Android arm / arm64 / x64 | API 24, 16KB alignment | NDK 28.2.13676358 |
| Linux arm64 / x64 | glibc 2.31 | native-architecture Actions runner, pinned GCC 12.3 bullseye image |
| Windows x64 | Win32 | pinned Debian 12, MinGW-w64 GCC 12 POSIX |
| Windows arm64 | Windows 10 UCRT | pinned Debian 12, SHA-256-pinned llvm-mingw 20260922 |

Windows libraries statically include their C++ runtimes, with only Windows
system DLL imports. Neither needs the Visual C++ redistributable. Linux
statically includes libstdc++/libgcc. Licenses/notices are in `LICENSE`.
Exact runner/compiler metadata and artifact hashes are in `prebuilt.json`.

## Build / verify

```sh
# Same hook entrypoint as Actions (needs Xcode on this target):
dart run kiln:build --target macos-arm64 \
  --repo Telosnex/zxing_dart --out /tmp/zxing-macos

# Download/cache path, with source-key and SHA-256 checks:
dart run kiln:check --download
dart test

# Upstream pins and profile:
dart run tool/verify_artifacts.dart

# Web files: install them into lib/web/ for the browser tests, from the
# release or from a local build (needs Emscripten 5.0.0):
dart run kiln:web install-dev
dart run tool/kiln/build_web.dart --out /tmp/zxd_web
dart run kiln:web install-dev --from /tmp/zxd_web

# After a change to lib/web/zxing_dart_worker.mjs or zxing_dart_loader.mjs:
dart run kiln:web stamp

# Standalone builds go to ignored build/native_artifacts/<target>/:
tool/build_native_artifact.sh macos-arm64
tool/build_all_native.sh
```

The Linux/Windows Docker wrappers remain **optional local reproductions** of
the Actions container environments; they are not the release orchestration.
The shared installer keeps local and Actions toolchain setup aligned.

The hook writes fetched sources, intermediate files and libraries only into
hook output directories, never the package sources. Source fetches and target
builds are locked. Apple minimum OS and Android API follow the hook request.
Unsupported targets or incompatible source-build hosts fail explicitly.

## ABI runtime scripts

Stage the released libraries first (or build them locally):

```sh
dart run tool/prebuilt_artifacts.dart # all; pass target names for a subset
tool/test_ios_simulator.sh
ZXD_ANDROID_AVD=Medium_Phone_API_36.0 tool/test_android_device.sh
tool/test_linux_docker.sh linux-arm64
tool/test_linux_docker.sh linux-x64
tool/test_windows_wine_docker.sh
```

These scripts test `build/native_artifacts/`, not files in Git. Native builds
validate architecture, dependency closure, exports and embedded ABI string.
macOS runs the complete ABI smoke/fuzz suite; Actions also executes it against
both Linux release libraries and enforces the glibc 2.31 ceiling. Windows ARM64
cannot run under Wine: use a Windows ARM64 host for runtime validation.

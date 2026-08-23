# Pinned native artifacts

Production code assets selected by `hook/build.dart`. Each is one self-contained
shim library with zxing-cpp statically folded in. Consumers do not invoke CMake,
CocoaPods, Gradle native dependencies, or a system zxing installation.

## Source pin

- zxing-cpp `d6068bcebeb8fd9f0d35a99b00d202be86a14dbe` (`v2.3.0`)
- native build profile `1`

Artifacts expose only the six `zxd_*` C ABI symbols. Upstream C++ symbols are
hidden by an exported-symbol list (Apple); equivalent version scripts will be
used for Android. Licenses and notices are under `licenses/`.

## Current matrix

| Target | Minimum | SHA-256 |
|---|---|---|
| macOS arm64 | macOS 12 | `a5b32e65531030b2b2689431de03b1a62e1a419eeb743d26fe4ca485553884f7` |

Android, iOS, and macOS x64 arrive with milestone 4. Linux and Windows are not
target platforms. Unsupported tuples fail in the build hook rather than
silently using an unpinned library.

## Reproduction

```bash
tool/build_macos.sh
```

The script fetches and verifies the immutable source commit, runs the ABI-only
native smoke test, verifies the complete exported-symbol set, copies the dylib
here, and prints the SHA-256 recorded in `manifest.json`.

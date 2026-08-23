# zxing-cpp 3.1.1 upgrade report

Upgraded from v2.3.0 (`d6068bcebeb8fd9f0d35a99b00d202be86a14dbe`)
to v3.1.1 (`287c85df6f961c8efbfb5ffd736cd9457b8b890e`).

## Compatibility changes handled

### C++20

3.1.1 uses concepts, ranges, and coroutine syntax. All native builds now use
C++20. Apple clang, NDK clang, and Emscripten already support it. Linux moved
from distro GCC 10 to pinned GCC 12.3 built on Debian bullseye, preserving the
existing glibc 2.31 floor. Windows moved to pinned MinGW GCC 12 POSIX.

### BarcodeFormat representation

2.x represented formats as bit flags; ABI v1 intentionally published those
values. 3.x represents formats as ISO symbology/variant IDs. Casting the old
mask into the new enum compiled but caused every filtered Aztec decode to return
`NOT_FOUND`.

The shim now translates every historical v1 bit explicitly on input and maps
3.x result IDs back to stable v1 values on output. An independent pure-Dart QR
fixture verifies the bridge in both directions on every native runtime, while
10 transformed QR scenes verify it through native and Web public APIs.

### Writer API

3.x deprecates `MultiFormatWriter` in favor of a new zint-backed creator. The
new writer also has different ECC configuration semantics. ABI v1 promises
zxing's historical Aztec ECC levels `0..8`, so this upgrade deliberately builds
3.1.1's retained `ZXING_WRITERS=OLD` implementation. The production 41×41
matrix and high-ECC 19×19 matrix are bit-identical to 2.3.0; their packed SHA-256
values are locked in tests. A future writer/API migration should be versioned
and reviewed independently from the decoder upgrade.

## Size impact

| Artifact | 2.3.0 | 3.1.1 | Change |
|---|---:|---:|---:|
| macOS arm64 | 944,096 | 1,090,816 | +15.5% |
| Android arm64 | 1,359,104 | 1,492,232 | +9.8% |
| Linux x64 | 2,022,616 | 2,406,368 | +19.0% |
| Windows x64 | 1,999,486 | 2,323,401 | +16.2% |
| WebAssembly | 1,100,459 | 1,251,569 | +13.7% |
| all native + Wasm | 15,611,469 | 17,902,682 | +14.7% |

No minimum OS/API was raised: macOS 12, iOS 13 (arm64 simulator 14), Android API
24, and Linux glibc 2.31 remain unchanged.

## Gates passed

- Exact six-symbol export surface and artifact hashes for all 11 native tuples
- Bit-identical Aztec writer output versus 2.3.0
- 70 synthetic acquisition tasks per backend, including independent Aztec and
  QR writers
- 6,144 malformed C ABI cases under ASan + UBSan
- VM, Chrome dart2js, Chrome dart2wasm, Safari
- macOS arm64/x64 (Rosetta), iOS Simulator, Android API 36 emulator
- Linux arm64/x64 clean glibc 2.31 containers
- Windows x64 under Wine

No decoder regression was observed in the current package-owned corpus.

# zxing-cpp 3.1.1 upgrade report

Upgraded from v2.3.0 (`d6068bcebeb8fd9f0d35a99b00d202be86a14dbe`)
to v3.1.1 (`287c85df6f961c8efbfb5ffd736cd9457b8b890e`) and its
pinned zint 2.16.0 writer (`55541e139e62b9209b71cd9b0ba9010cec28b1d9`).

## Compatibility changes handled

### C++20

3.1.1 uses concepts, ranges, and coroutine syntax. All native builds now use
C++20. Apple clang, NDK clang, and Emscripten already support it. Linux moved
from distro GCC 10 to pinned GCC 12.3 built on Debian bullseye, preserving the
existing glibc 2.31 floor. Windows moved to pinned MinGW GCC 12 POSIX.

### Package-owned format flags

2.x represented formats as bit flags; 3.x represents them as ISO symbology and
variant IDs. Passing a bit mask into the new enum compiled but silently caused
filtered Aztec reads to return `NOT_FOUND`.

The package had not been released, so ABI 2 now uses its own compact flags
(`Aztec = 1`, `QR = 2`) rather than preserving 2.x's incidental values. The shim
translates these package values explicitly at the C++ boundary. An independent
pure-Dart QR fixture verifies both directions on every native runtime, while 10
transformed QR scenes cover the public native and Web APIs.

### Production zint writer

3.x deprecates `MultiFormatWriter`. We now build `ZXING_WRITERS=NEW` and call
`CreateBarcodeFromText` with the bundled, independently pinned zint 2.16.0
backend. The old `eccLevel: 0..8` Dart option is gone before release;
`errorCorrectionPercent` accepts 0..99 and zxing-cpp maps it to zint's nearest
Aztec level (10%, 23%, 36%, or 50%). Null selects the writer default.

The production payload remains 41×41 and the short 50% ECC fixture remains
19×19, but module placement legitimately differs from the classic writer. The
new production packed-matrix SHA-256 is locked as
`19a061412d2dba9d524030cfb3077eb5d48da09d4956b4cb739d51c670b6d70c`.
The output matrix is read as a luminance plane (`0` is black), matching
`Barcode::symbol()` and avoiding an accidentally inverted symbol.

## Size impact of enabling the new writer

| Artifact | 3.1.1 classic | 3.1.1 + zint | Change |
|---|---:|---:|---:|
| macOS arm64 | 1,090,816 | 1,272,944 | +16.7% |
| Android arm64 | 1,492,232 | 1,626,104 | +9.0% |
| Linux x64 | 2,406,368 | 2,521,152 | +4.8% |
| Windows x64 | 2,323,401 | 2,459,758 | +5.9% |
| WebAssembly | 1,251,569 | 1,330,551 | +6.3% |
| all native + Wasm | 17,902,682 | 19,684,961 | +10.0% |

No minimum OS/API was raised: macOS 12, iOS 13 (arm64 simulator 14), Android API
24, and Linux glibc 2.31 remain unchanged.

## Gates

- Exact six-symbol export surface and artifact hashes for all 11 native tuples
- 70 synthetic acquisition tasks per backend, including independent Aztec and
  QR writers and zint default/high-ECC output
- 6,144 malformed C ABI cases under ASan + UBSan
- VM, Chrome dart2js, Chrome dart2wasm, Safari
- macOS arm64/x64 (Rosetta), iOS Simulator, Android API 36 emulator
- Linux arm64/x64 clean glibc 2.31 containers
- Windows x64 under Wine

No decoder or writer round-trip regression was observed in the package-owned
corpus.

#!/usr/bin/env bash
# Run the ABI smoke suite—including 6,144 malformed descriptor/pixel cases—
# under AddressSanitizer and UndefinedBehaviorSanitizer.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
[[ "$(uname -s)" == Darwin ]] || {
  echo 'This sanitizer profile currently requires Apple clang on macOS.' >&2
  exit 1
}
"$root/tool/fetch_zxing.sh"

build="$root/build/macos-arm64-sanitized"
rm -rf "$build"
san_flags='-fsanitize=address,undefined -fno-omit-frame-pointer -fno-sanitize-recover=all'
cmake -S "$root" -B "$build" \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DCMAKE_OSX_ARCHITECTURES="$(uname -m)" \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=12.0 \
  -DCMAKE_C_FLAGS="$san_flags" \
  -DCMAKE_CXX_FLAGS="$san_flags" \
  -DCMAKE_EXE_LINKER_FLAGS="$san_flags" \
  -DCMAKE_SHARED_LINKER_FLAGS="$san_flags" \
  -DZXD_BUILD_TESTS=ON
cmake --build "$build" --parallel \
  "$(sysctl -n hw.logicalcpu 2>/dev/null || echo 4)"
# Apple clang's ASan runtime does not implement LeakSanitizer. Heap bounds,
# use-after-free, double-free, and UB checks remain enabled.
ASAN_OPTIONS='abort_on_error=1:detect_leaks=0:strict_string_checks=1' \
UBSAN_OPTIONS='halt_on_error=1:print_stacktrace=1' \
  "$build/zxd_smoke_test"
echo 'PASS: native ABI suite under ASan + UBSan'

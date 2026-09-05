#!/usr/bin/env bash
# Builds the pinned zxing-cpp + zxing_dart shim as one Emscripten ES module.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"

if ! command -v em++ >/dev/null; then
  # Convenient for this monorepo; CI may instead activate emsdk beforehand.
  if [[ -f "$root/../emsdk/emsdk_env.sh" ]]; then
    export EMSDK_QUIET=1
    # shellcheck disable=SC1091
    source "$root/../emsdk/emsdk_env.sh" >/dev/null
  else
    echo "em++ not found; install/activate the Emscripten SDK" >&2
    exit 1
  fi
fi

"$root/tool/fetch_zxing.sh"

build_dir="$root/build/web"
# Exception catching is required: zxing-cpp uses exceptions for malformed and
# unencodable inputs, while our C ABI promises that none cross the boundary.
emcmake cmake -S "$root" -B "$build_dir" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_CXX_FLAGS_RELEASE='-O3 -DNDEBUG -fexceptions' \
  -DZXD_BUILD_TESTS=OFF
cmake --build "$build_dir" --target ZXing -j "$(sysctl -n hw.ncpu)"

zxing_lib="$build_dir/third_party/zxing-cpp/core/libZXing.a"
version_include="$build_dir/third_party/zxing-cpp/core"
if [[ ! -f "$zxing_lib" ]]; then
  echo "Expected zxing-cpp archive not found: $zxing_lib" >&2
  exit 1
fi

em++ "$root/src/zxing_dart.cpp" "$zxing_lib" \
  -I"$root/src" \
  -I"$root/third_party/zxing-cpp/core/src" \
  -I"$version_include" \
  -std=c++20 \
  -O3 \
  -DNDEBUG \
  -fexceptions \
  --no-entry \
  -sDISABLE_EXCEPTION_CATCHING=0 \
  -sMODULARIZE=1 \
  -sEXPORT_ES6=1 \
  -sENVIRONMENT=web,worker,node \
  -sALLOW_MEMORY_GROWTH=1 \
  -sFILESYSTEM=0 \
  -sEXPORTED_FUNCTIONS='["_malloc","_free","_zxd_abi_version","_zxd_build_info","_zxd_read","_zxd_read_result_release","_zxd_encode_aztec","_zxd_encode","_zxd_matrix_release"]' \
  -sEXPORTED_RUNTIME_METHODS='["UTF8ToString","HEAPU8"]' \
  -o "$root/lib/web/zxing_dart_module.mjs"

printf 'Built:\n'
ls -lh \
  "$root/lib/web/zxing_dart_module.mjs" \
  "$root/lib/web/zxing_dart_module.wasm"
shasum -a 256 \
  "$root/lib/web/zxing_dart_module.mjs" \
  "$root/lib/web/zxing_dart_module.wasm"

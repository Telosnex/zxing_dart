#!/usr/bin/env bash
# Builds the macos-arm64 shim + runs the native smoke test.
# Milestone 1 of the port plan; other targets follow image_ffmpeg's
# build_native_artifact.sh matrix (android arm64/arm32/x64, ios, macos-x64).
set -euo pipefail
cd "$(dirname "$0")/.."

./tool/fetch_zxing.sh

readonly BUILD_DIR="build/macos-arm64"
cmake -S . -B "${BUILD_DIR}" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DZXD_BUILD_TESTS=ON
cmake --build "${BUILD_DIR}" -j "$(sysctl -n hw.ncpu)"

"${BUILD_DIR}/zxd_smoke_test"

echo
echo "artifact: ${BUILD_DIR}/libzxing_dart.dylib"
shasum -a 256 "${BUILD_DIR}/libzxing_dart.dylib"

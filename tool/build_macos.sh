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
  -DCMAKE_OSX_DEPLOYMENT_TARGET=12.0 \
  -DZXD_BUILD_TESTS=ON
cmake --build "${BUILD_DIR}" -j "$(sysctl -n hw.ncpu)"

"${BUILD_DIR}/zxd_smoke_test"

exported="$(nm -gU "${BUILD_DIR}/libzxing_dart.dylib" | awk '{print $3}' | sort | tr '\n' ' ')"
expected="_zxd_abi_version _zxd_build_info _zxd_encode_aztec _zxd_matrix_release _zxd_read _zxd_read_result_release "
if [[ "${exported}" != "${expected}" ]]; then
  printf 'Unexpected exported symbol set:\n%s\n' "${exported}" >&2
  exit 1
fi

readonly ARTIFACT_DIR="native_artifacts/macos-arm64"
mkdir -p "${ARTIFACT_DIR}"
cp "${BUILD_DIR}/libzxing_dart.dylib" "${ARTIFACT_DIR}/libzxing_dart.dylib"

echo
echo "artifact: ${ARTIFACT_DIR}/libzxing_dart.dylib"
shasum -a 256 "${ARTIFACT_DIR}/libzxing_dart.dylib"

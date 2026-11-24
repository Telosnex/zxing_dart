#!/usr/bin/env bash
# Reproducible glibc 2.31 builds using GCC 12 on Debian bullseye. zxing-cpp 3.x
# needs newer C++20 parsing than bullseye's distro GCC 10, but changing the
# compiler does not need to raise the shipped glibc baseline.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
target="${1:-}"
case "$target" in
  linux-x64|linux-arm64) ;;
  *) echo "Usage: $0 <linux-x64|linux-arm64>" >&2; exit 64 ;;
esac
command -v docker >/dev/null || { echo 'docker is required' >&2; exit 1; }

if [[ "$target" == linux-x64 ]]; then
  platform=linux/amd64
  image='gcc@sha256:5c3421e670da08036f641a073da0191f82334ba6f102558dd2d73ded72318d2b'
else
  platform=linux/arm64
  image='gcc@sha256:877cfec017e7d18ddaf3376a2a575bd9c065ee34e6c20b8913938360992a0040'
fi

# Kiln supplies a pinned checkout and a path for the library. Mount only the
# sources. Stream the built library to the host to keep host file ownership.
if [[ -n "${ZXD_ZXING_SOURCE:-}" ]]; then
  output="${ZXD_OUTPUT:?Set ZXD_OUTPUT for the library}"
  mkdir -p "$(dirname "$output")"
  temp="$(mktemp "${output}.XXXXXX")"
  trap 'rm -f "$temp"' EXIT
  docker run --rm --platform "$platform" \
    -v "$root:/workspace:ro" \
    -v "${ZXD_ZXING_SOURCE%/}:/zxing-cpp:ro" \
    -w /workspace "$image" bash -c '
      set -euo pipefail
      git config --global --add safe.directory /zxing-cpp
      git config --global --add safe.directory /zxing-cpp/zint
      bash tool/install_build_toolchain.sh "$1" >&2
      ZXD_ZXING_SOURCE=/zxing-cpp ZXD_BUILD_JOBS="$2" \
        ZXD_BUILD_ROOT=/tmp/zxd-build ZXD_OUTPUT=/tmp/libzxing_dart.so \
        bash tool/build_native_artifact.sh "$1" >&2
      cat /tmp/libzxing_dart.so
    ' bash "$target" "${ZXD_BUILD_JOBS:-4}" > "$temp"
  chmod 755 "$temp"
  mv -f "$temp" "$output"
  exit
fi

docker run --rm --platform "$platform" \
  -v "$root:/workspace" \
  -w /workspace \
  "$image" \
  bash -lc '
    set -euo pipefail
    tool/install_build_toolchain.sh '"$target"'
    ZXD_BUILD_JOBS='"${ZXD_BUILD_JOBS:-4}"' tool/build_native_artifact.sh '"$target"'
  '

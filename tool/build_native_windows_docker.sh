#!/usr/bin/env bash
# Reproducible Windows cross-builds. No Windows SDK or Visual Studio is required.
#
# windows-x64: pinned Debian bookworm-slim/MinGW GCC 12. zxing-cpp 3.x requires
# C++20 syntax unavailable in bullseye's GCC 10.
# windows-arm64: the same pinned Debian image plus a SHA-256-pinned llvm-mingw
# release, because GCC has no Windows ARM64 target. The container runs on the
# host's native architecture; both llvm-mingw host builds are the same release.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
target="${1:-}"
case "$target" in
  windows-x64|windows-arm64) ;;
  *) echo "Usage: $0 <windows-x64|windows-arm64>" >&2; exit 64 ;;
esac
command -v docker >/dev/null || { echo 'docker is required' >&2; exit 1; }

readonly image='debian:bookworm-slim@sha256:abd67ffcfa541b485a3dff59865ab629aa048a6c613e639d36e7456b0b229241'

if [[ "$target" == windows-x64 ]]; then
  docker run --rm --platform linux/amd64 \
    -v "$root:/workspace" \
    -w /workspace \
    "$image" \
    bash -lc '
      set -euo pipefail
      tool/install_build_toolchain.sh windows-x64
      ZXD_BUILD_JOBS='"${ZXD_BUILD_JOBS:-4}"' tool/build_native_artifact.sh windows-x64
    '
  exit 0
fi

case "$(docker info --format '{{.Architecture}}')" in
  aarch64|arm64) platform=linux/arm64 ;;
  x86_64|amd64) platform=linux/amd64 ;;
  *) echo 'Unsupported Docker host architecture.' >&2; exit 1 ;;
esac

docker run --rm --platform "$platform" \
  -v "$root:/workspace" -w /workspace "$image" bash -lc '
    set -euo pipefail
    tool/install_build_toolchain.sh windows-arm64
    export PATH="/opt/llvm-mingw/bin:$PATH"
    ZXD_BUILD_JOBS='"${ZXD_BUILD_JOBS:-4}"' tool/build_native_artifact.sh windows-arm64
  '

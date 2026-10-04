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
      export DEBIAN_FRONTEND=noninteractive
      apt-get update -qq
      apt-get install -y --no-install-recommends \
        build-essential ca-certificates cmake git make python3 \
        gcc-mingw-w64-x86-64 g++-mingw-w64-x86-64 binutils-mingw-w64-x86-64
      ZXD_BUILD_JOBS='"${ZXD_BUILD_JOBS:-4}"' tool/build_native_artifact.sh windows-x64
    '
  exit 0
fi

readonly llvm_mingw_release=20260922
case "$(docker info --format '{{.Architecture}}')" in
  aarch64|arm64)
    platform=linux/arm64
    # Platform manifest from the same bookworm-slim index as windows-x64.
    host_image='debian@sha256:817e6cf99d6fc127ff4ffe8580049b60deba0adfbbb2bd65ddc3ef8fbb7aade0'
    llvm_mingw_host=aarch64
    llvm_mingw_sha256=07d21263c56bfe9a713db6fdb3f7434bf4c121a005e40397d3b4c0170fb06769
    ;;
  x86_64|amd64)
    platform=linux/amd64
    host_image='debian@sha256:362e64223cc0da95422b3b13c045186fc0a81250e765d31c025fbddf257f6143'
    llvm_mingw_host=x86_64
    llvm_mingw_sha256=bb7bb7654b33d5aa8712acb837c963b2e0c56352560c76105270a3268c665c21
    ;;
  *) echo 'Unsupported Docker host architecture.' >&2; exit 1 ;;
esac
llvm_mingw_name="llvm-mingw-$llvm_mingw_release-ucrt-ubuntu-22.04-$llvm_mingw_host"

docker run --rm --platform "$platform" \
  -v "$root:/workspace" \
  -w /workspace \
  -e LLVM_MINGW_URL="https://github.com/mstorsjo/llvm-mingw/releases/download/$llvm_mingw_release/$llvm_mingw_name.tar.xz" \
  -e LLVM_MINGW_SHA256="$llvm_mingw_sha256" \
  -e LLVM_MINGW_NAME="$llvm_mingw_name" \
  "$host_image" \
  bash -lc '
    set -euo pipefail
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y --no-install-recommends \
      binutils ca-certificates cmake curl git make perl python3 xz-utils
    curl -fsSL "$LLVM_MINGW_URL" -o /tmp/llvm-mingw.tar.xz
    echo "$LLVM_MINGW_SHA256  /tmp/llvm-mingw.tar.xz" | sha256sum -c -
    tar -xJf /tmp/llvm-mingw.tar.xz -C /opt
    export PATH="/opt/$LLVM_MINGW_NAME/bin:$PATH"
    aarch64-w64-mingw32-clang --version
    ZXD_BUILD_JOBS='"${ZXD_BUILD_JOBS:-4}"' tool/build_native_artifact.sh windows-arm64
  '

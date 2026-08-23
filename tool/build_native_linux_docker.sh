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

docker run --rm --platform "$platform" \
  -v "$root:/workspace" \
  -w /workspace \
  "$image" \
  bash -lc '
    set -euo pipefail
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y --no-install-recommends \
      ca-certificates cmake git make python3 binutils
    g++ -dumpfullversion | grep "^12\."
    ZXD_BUILD_JOBS='"${ZXD_BUILD_JOBS:-4}"' tool/build_native_artifact.sh '"$target"'
  '

#!/usr/bin/env bash
# Reproducible Windows x64 cross-build with the same pinned Debian image as
# image_ffmpeg. Produces a PE DLL; no Windows SDK or Visual Studio is required.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
target="${1:-}"
[[ "$target" == windows-x64 ]] || {
  echo "Usage: $0 windows-x64" >&2
  exit 64
}
command -v docker >/dev/null || { echo 'docker is required' >&2; exit 1; }

docker run --rm --platform linux/amd64 \
  -v "$root:/workspace" \
  -w /workspace \
  debian:bullseye-slim@sha256:cba95a21c96c1f5fc2470081829363eed57706634f7dc26e8c6712934303d57a \
  bash -lc '
    set -euo pipefail
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y --no-install-recommends \
      build-essential ca-certificates cmake git make python3 \
      gcc-mingw-w64-x86-64 g++-mingw-w64-x86-64 binutils-mingw-w64-x86-64
    ZXD_BUILD_JOBS='"${ZXD_BUILD_JOBS:-4}"' tool/build_native_artifact.sh windows-x64
  '

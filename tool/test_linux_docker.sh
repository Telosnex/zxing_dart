#!/usr/bin/env bash
# Runtime-test the exact staged Linux artifact in a clean container of the
# matching architecture. Both image digests are children of the pinned
# Debian bullseye-slim manifest used by the production build wrappers.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
target="${1:-}"
case "$target" in
  linux-x64)
    platform=linux/amd64
    image='debian@sha256:de70627667ac77b32ab6858f1acddfb04a4ff3acc1095ac17dbc19fe5725bcb6'
    ;;
  linux-arm64)
    platform=linux/arm64
    image='debian@sha256:256e2eb1c47e91d91d1332b436b2efac5cd2511dc82fb78850fd01770cce2162'
    ;;
  *) echo "Usage: $0 <linux-x64|linux-arm64>" >&2; exit 64 ;;
esac
command -v docker >/dev/null || { echo 'docker is required' >&2; exit 1; }

docker run --rm --platform "$platform" \
  -v "$root:/workspace" -w /workspace "$image" \
  bash -lc '
    set -euo pipefail
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y --no-install-recommends g++ >/dev/null
    target='"$target"'
    build="build/${target}-runtime-smoke"
    rm -rf "$build" && mkdir -p "$build"
    g++ -std=c++17 -O2 -I src native_test/smoke_test.cpp \
      -L "build/native_artifacts/$target" -lzxing_dart \
      -Wl,-rpath,'"'"'$ORIGIN'"'"' -o "$build/zxd_smoke_test"
    cp "build/native_artifacts/$target/libzxing_dart.so" "$build/"
    "$build/zxd_smoke_test"
  '
echo "PASS: $target runtime-tested in clean $platform container"

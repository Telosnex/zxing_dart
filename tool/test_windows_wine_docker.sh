#!/usr/bin/env bash
# Runtime-test the exact staged Windows x64 DLL under Wine in a clean pinned
# Linux/amd64 container. The test executable links through an import library
# generated from our canonical seven-symbol .def file.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
command -v docker >/dev/null || { echo 'docker is required' >&2; exit 1; }

docker run --rm --platform linux/amd64 \
  -v "$root:/workspace" -w /workspace \
  debian:bookworm-slim@sha256:abd67ffcfa541b485a3dff59865ab629aa048a6c613e639d36e7456b0b229241 \
  bash -lc '
    set -euo pipefail
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y --no-install-recommends \
      g++-mingw-w64-x86-64-posix binutils-mingw-w64-x86-64 wine64 >/dev/null
    build=build/windows-x64-runtime-smoke
    rm -rf "$build" && mkdir -p "$build"
    x86_64-w64-mingw32-dlltool \
      -d src/exports_windows.def -D zxing_dart.dll \
      -l "$build/libzxing_dart.dll.a"
    x86_64-w64-mingw32-g++-posix \
      -std=c++17 -O2 -static -static-libgcc -static-libstdc++ \
      -I src native_test/smoke_test.cpp "$build/libzxing_dart.dll.a" \
      -o "$build/zxd_smoke_test.exe"
    cp build/native_artifacts/windows-x64/zxing_dart.dll "$build/"
    cd "$build"
    export WINEDEBUG=-all WINEPREFIX=/tmp/zxing-dart-wine
    /usr/lib/wine/wine64 ./zxd_smoke_test.exe
  '
echo 'PASS: windows-x64 runtime-tested under Wine'

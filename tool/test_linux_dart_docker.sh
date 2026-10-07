#!/usr/bin/env bash
# Run the public Dart API suite through package:hooks and @Native against the
# exact released Linux code asset. This validates more than the C ABI smoke
# test: target-key selection, hash verification, bundling, symbol lookup,
# helper-isolate ownership, and typed result conversion.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
target="${1:-}"
case "$target" in
  linux-x64)
    platform=linux/amd64
    image='dart@sha256:3784506017fcf7bd52f9c9d021efdfd60f6ceb2a63eb17c3cf73bfe909910b6f'
    ;;
  linux-arm64)
    platform=linux/arm64
    image='dart@sha256:b55cb6df7fc66c9c3175169bb33932db0be6fbce5242b099994245ed9db15eb7'
    ;;
  *) echo "Usage: $0 <linux-x64|linux-arm64>" >&2; exit 64 ;;
esac
command -v docker >/dev/null || { echo 'docker is required' >&2; exit 1; }

docker run --rm --platform "$platform" \
  -v "$root:/workspace:ro" "$image" bash -c '
    set -euo pipefail
    mkdir /tmp/package
    cd /workspace
    tar --exclude=.dart_tool --exclude=build --exclude=third_party \
      -cf - . | tar -xf - -C /tmp/package
    cd /tmp/package
    dart pub get >/dev/null
    dart test -r compact
  '
echo "PASS: public Dart API on $target"

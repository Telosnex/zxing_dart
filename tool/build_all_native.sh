#!/usr/bin/env bash
# Rebuild all intentionally supported native code-asset tuples serially.
# Set ZXD_BUILD_JOBS to control per-target compilation parallelism.
set -euo pipefail
cd "$(dirname "$0")/.."

for target in \
  macos-arm64 \
  macos-x64 \
  ios-arm64-iphoneos \
  ios-arm64-iphonesimulator \
  ios-x64-iphonesimulator \
  android-arm \
  android-arm64 \
  android-x64
do
  echo "=== $target ==="
  ./tool/build_native_artifact.sh "$target"
done

for target in linux-arm64 linux-x64; do
  echo "=== $target ==="
  ./tool/build_native_linux_docker.sh "$target"
done

for target in windows-arm64 windows-x64; do
  echo "=== $target ==="
  ./tool/build_native_windows_docker.sh "$target"
done

dart run tool/verify_artifacts.dart

#!/usr/bin/env bash
# Run the public Dart API suite with the Windows x64 Dart VM under Wine. A
# native Linux Dart of the exact same version prepares an offline pub cache;
# Windows Dart then performs its own build-hook run, selecting/verifying the PE
# code asset and exercising @Native + helper isolates through the public API.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
command -v docker >/dev/null || { echo 'docker is required' >&2; exit 1; }
if [[ "$(uname -s)/$(uname -m)" != Linux/x86_64 ]]; then
  echo 'Windows Dart/Wine test requires an x64 Linux Docker host. Nested' >&2
  echo 'Windows Dart JIT under Wine under amd64 emulation is not reliable.' >&2
  exit 77
fi

readonly image='dart@sha256:3784506017fcf7bd52f9c9d021efdfd60f6ceb2a63eb17c3cf73bfe909910b6f'
readonly sdk_url='https://storage.googleapis.com/dart-archive/channels/stable/release/3.13.1/sdk/dartsdk-windows-x64-release.zip'
readonly sdk_sha256='f3fd0fa8f3bc7982bbf08eb1bca84148fb4ee0767e75faa07ec9c11c40ab2ff7'

docker run --rm --platform linux/amd64 \
  -v "$root:/workspace:ro" \
  -e ZXD_WINDOWS_DART_URL="$sdk_url" \
  -e ZXD_WINDOWS_DART_SHA256="$sdk_sha256" \
  "$image" bash -c '
    set -euo pipefail
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y --no-install-recommends \
      ca-certificates curl unzip wine64 >/dev/null

    mkdir /tmp/package
    cd /workspace
    tar --exclude=.dart_tool --exclude=build --exclude=third_party \
      -cf - . | tar -xf - -C /tmp/package
    cd /tmp/package

    # Populate only this package dependency graph without asking Wine networking
    # to behave like Windows networking.
    export PUB_CACHE=/tmp/pub-cache
    dart pub get >/dev/null
    rm -rf .dart_tool

    curl -fsSL "$ZXD_WINDOWS_DART_URL" -o /tmp/dart-windows.zip
    echo "$ZXD_WINDOWS_DART_SHA256  /tmp/dart-windows.zip" | sha256sum -c -
    unzip -q /tmp/dart-windows.zip -d /tmp

    mkdir -p /tmp/xdg
    export XDG_RUNTIME_DIR=/tmp/xdg
    export WINEDEBUG=-all WINEPREFIX=/tmp/zxing-dart-wine
    export PUB_CACHE='"'"'Z:\tmp\pub-cache'"'"'
    dart_exe=/tmp/dart-sdk/bin/dart.exe
    /usr/lib/wine/wine64 "$dart_exe" pub get --offline
    /usr/lib/wine/wine64 "$dart_exe" test -r compact
  '
echo 'PASS: public Dart API on windows-x64 under Wine'

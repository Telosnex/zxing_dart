#!/usr/bin/env bash
# Full milestone-3 parity gate. Safari is serial because one Safari application
# instance cannot reliably host multiple package:test managers concurrently.
set -euo pipefail
cd "$(dirname "$0")/.."

dart analyze
dart run tool/verify_artifacts.dart
dart test -r compact
dart test -p chrome --compiler dart2js -r compact
dart test -p chrome --compiler dart2wasm -r compact

if [[ "$(uname -s)" == Darwin ]] && [[ "${ZXD_SKIP_SAFARI:-0}" != 1 ]]; then
  dart test -p safari --compiler dart2js -j 1 -r compact
fi

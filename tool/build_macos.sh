#!/usr/bin/env bash
# Backward-compatible milestone-1 entrypoint. The production artifact matrix is
# now centralized in build_native_artifact.sh so this command cannot overwrite
# a committed artifact with a different build profile.
set -euo pipefail
exec "$(cd "$(dirname "$0")" && pwd)/build_native_artifact.sh" macos-arm64

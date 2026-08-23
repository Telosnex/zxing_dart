#!/usr/bin/env bash
# Fetches zxing-cpp at the pinned revision into third_party/zxing-cpp.
#
# Pin policy (see image_ffmpeg/doc/PORTING_C_LIBRARIES.md): exact commit hash,
# verified after checkout; bumping the pin is a reviewed change accompanied by
# a full conformance run.
set -euo pipefail

# v3.1.1. Keep the immutable commit rather than trusting a movable tag during
# production rebuilds. Upgrades require the full synthetic + native matrix.
readonly PIN_COMMIT="287c85df6f961c8efbfb5ffd736cd9457b8b890e"
readonly REPO_URL="https://github.com/zxing-cpp/zxing-cpp.git"

cd "$(dirname "$0")/.."
readonly DEST="third_party/zxing-cpp"

if [[ -d "${DEST}/.git" ]]; then
  current="$(git -C "${DEST}" rev-parse HEAD)"
  if [[ "${current}" == "${PIN_COMMIT}" ]]; then
    echo "zxing-cpp already at pin ${PIN_COMMIT}"
    exit 0
  fi
  echo "zxing-cpp at ${current}, re-fetching pin ${PIN_COMMIT}"
  rm -rf "${DEST}"
fi

mkdir -p "${DEST}"
git -C "${DEST}" init -q
git -C "${DEST}" remote add origin "${REPO_URL}"
git -C "${DEST}" fetch -q --depth 1 origin "${PIN_COMMIT}"
git -C "${DEST}" checkout -q FETCH_HEAD
# NOTE: no submodules. zint is only needed for ZXING_WRITERS=NEW; we build the
# classic writers.

actual="$(git -C "${DEST}" rev-parse HEAD)"
if [[ "${actual}" != "${PIN_COMMIT}" ]]; then
  echo "PIN MISMATCH: expected ${PIN_COMMIT}, got ${actual}" >&2
  exit 1
fi
echo "zxing-cpp pinned at ${PIN_COMMIT}"

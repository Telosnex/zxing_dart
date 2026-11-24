#!/usr/bin/env bash
# Fetches zxing-cpp at the pinned revision into third_party/zxing-cpp.
#
# Pin policy (see image_ffmpeg/doc/PORTING_C_LIBRARIES.md): exact commit hash,
# verified after checkout; bumping the pin is a reviewed change accompanied by
# a full conformance run.
set -euo pipefail

# v3.2.0. Keep the immutable commit rather than trusting a movable tag during
# production rebuilds. Upgrades require the full synthetic + native matrix.
readonly PIN_COMMIT="f66b8ab4909e2ce33a1dc68add372e8d2ef99007"
readonly REPO_URL="https://github.com/zxing-cpp/zxing-cpp.git"
readonly ZINT_PIN_COMMIT="55541e139e62b9209b71cd9b0ba9010cec28b1d9"

cd "$(dirname "$0")/.."
readonly DEST="${ZXD_THIRD_PARTY:-$PWD/third_party}/zxing-cpp"

if [[ -d "${DEST}/.git" ]]; then
  current="$(git -C "${DEST}" rev-parse HEAD)"
  if [[ "${current}" == "${PIN_COMMIT}" ]]; then
    echo "zxing-cpp already at pin ${PIN_COMMIT}"
  else
    echo "zxing-cpp at ${current}, re-fetching pin ${PIN_COMMIT}"
    rm -rf "${DEST}"
  fi
fi

if [[ ! -d "${DEST}/.git" ]]; then
  mkdir -p "${DEST}"
  git -C "${DEST}" init -q
  git -C "${DEST}" remote add origin "${REPO_URL}"
  git -C "${DEST}" fetch -q --depth 1 origin "${PIN_COMMIT}"
  git -C "${DEST}" checkout -q FETCH_HEAD
fi

actual="$(git -C "${DEST}" rev-parse HEAD)"
if [[ "${actual}" != "${PIN_COMMIT}" ]]; then
  echo "PIN MISMATCH: expected ${PIN_COMMIT}, got ${actual}" >&2
  exit 1
fi

# The production writer uses the zint submodule. Check its commit separately.
git -C "${DEST}" submodule update --init --depth 1 zint
zint_actual="$(git -C "${DEST}/zint" rev-parse HEAD)"
if [[ "${zint_actual}" != "${ZINT_PIN_COMMIT}" ]]; then
  echo "ZINT PIN MISMATCH: expected ${ZINT_PIN_COMMIT}, got ${zint_actual}" >&2
  exit 1
fi
echo "zxing-cpp pinned at ${PIN_COMMIT}; zint pinned at ${ZINT_PIN_COMMIT}"

#!/usr/bin/env bash
# Cross-build one production zxing_dart native code asset from the pinned
# zxing-cpp source. Consumers never run this script: hook/build.dart only
# verifies and publishes the committed artifact.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
target="${1:-}"
profile_version=3
android_api="${ZXD_ANDROID_API:-24}"

usage() {
  cat >&2 <<'EOF'
Usage: tool/build_native_artifact.sh <target>

Targets:
  macos-arm64              macos-x64
  ios-arm64-iphoneos       ios-arm64-iphonesimulator
  ios-x64-iphonesimulator
  android-arm              android-arm64              android-x64
  linux-arm64              linux-x64
  windows-x64

Apple targets require Xcode. Android targets require ANDROID_NDK_HOME or a
standard Android SDK installation. Linux/Windows targets use Linux compilers
directly or the provided pinned Docker wrappers.
EOF
  exit 64
}

case "$target" in
  macos-arm64|macos-x64|ios-arm64-iphoneos|ios-arm64-iphonesimulator|ios-x64-iphonesimulator|android-arm|android-arm64|android-x64|linux-arm64|linux-x64|windows-x64) ;;
  *) usage ;;
esac

"$root/tool/fetch_zxing.sh"
command -v cmake >/dev/null || { echo 'cmake is required' >&2; exit 1; }

build_dir="$root/build/native/$target-v$profile_version"
artifact_dir="$root/native_artifacts/$target"
cmake_args=(
  -DCMAKE_BUILD_TYPE=Release
  -DZXD_BUILD_TESTS=OFF
  -DZXING_EXAMPLES=OFF
  -DZXING_UNIT_TESTS=OFF
)
os=
artifact_arch=
output_name=
verification_nm=
verification_readelf=
strip_tool=
run_smoke=false

case "$target" in
  macos-arm64|macos-x64)
    os=macos
    [[ "$target" == macos-arm64 ]] && artifact_arch=arm64 || artifact_arch=x86_64
    sdk_path="$(xcrun --sdk macosx --show-sdk-path)"
    cmake_args+=(
      -DCMAKE_OSX_ARCHITECTURES="$artifact_arch"
      -DCMAKE_OSX_DEPLOYMENT_TARGET=12.0
      -DCMAKE_OSX_SYSROOT="$sdk_path"
      -DZXD_BUILD_TESTS=ON
    )
    output_name=libzxing_dart.dylib
    strip_tool="$(xcrun --sdk macosx -f strip)"
    run_smoke=true
    ;;
  ios-arm64-iphoneos|ios-arm64-iphonesimulator|ios-x64-iphonesimulator)
    os=ios
    [[ "$target" == ios-x64-iphonesimulator ]] && artifact_arch=x86_64 || artifact_arch=arm64
    [[ "$target" == *-iphoneos ]] && sdk=iphoneos || sdk=iphonesimulator
    sdk_path="$(xcrun --sdk "$sdk" --show-sdk-path)"
    cmake_args+=(
      -DCMAKE_SYSTEM_NAME=iOS
      -DCMAKE_OSX_ARCHITECTURES="$artifact_arch"
      -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0
      -DCMAKE_OSX_SYSROOT="$sdk_path"
      -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY
    )
    output_name=libzxing_dart.dylib
    strip_tool="$(xcrun --sdk "$sdk" -f strip)"
    ;;
  android-arm|android-arm64|android-x64)
    os=android
    ndk="${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT:-}}"
    if [[ -z "$ndk" ]]; then
      # Keep this in sync with image_ffmpeg's reproducible artifact profile.
      ndk="$HOME/Library/Android/sdk/ndk/28.2.13676358"
    fi
    [[ -d "$ndk" ]] || {
      echo 'Set ANDROID_NDK_HOME to an Android NDK (profile uses 28.2.13676358).' >&2
      exit 1
    }
    case "$(uname -s)" in
      Darwin) ndk_host=darwin-x86_64 ;;
      Linux) ndk_host=linux-x86_64 ;;
      *) echo 'Android builds require macOS or Linux.' >&2; exit 1 ;;
    esac
    llvm_bin="$ndk/toolchains/llvm/prebuilt/$ndk_host/bin"
    case "$target" in
      android-arm)
        android_abi=armeabi-v7a; artifact_arch=arm
        ;;
      android-arm64)
        android_abi=arm64-v8a; artifact_arch=aarch64
        ;;
      android-x64)
        android_abi=x86_64; artifact_arch=x86_64
        ;;
    esac
    cmake_args+=(
      -DCMAKE_TOOLCHAIN_FILE="$ndk/build/cmake/android.toolchain.cmake"
      -DANDROID_ABI="$android_abi"
      -DANDROID_PLATFORM="android-$android_api"
      -DANDROID_STL=c++_static
    )
    output_name=libzxing_dart.so
    verification_nm="$llvm_bin/llvm-nm"
    verification_readelf="$llvm_bin/llvm-readelf"
    strip_tool="$llvm_bin/llvm-strip"
    ;;
  linux-arm64|linux-x64)
    os=linux
    [[ "$(uname -s)" == Linux ]] || {
      echo 'Linux artifacts must be built on Linux; use build_native_linux_docker.sh.' >&2
      exit 1
    }
    if [[ "$target" == linux-arm64 ]]; then
      artifact_arch=aarch64
      cc="${CC:-aarch64-linux-gnu-gcc}"
      cxx="${CXX:-aarch64-linux-gnu-g++}"
      strip_tool="${STRIP:-aarch64-linux-gnu-strip}"
      verification_nm="${NM:-aarch64-linux-gnu-nm}"
      verification_readelf="${READELF:-aarch64-linux-gnu-readelf}"
      cmake_args+=(
        -DCMAKE_SYSTEM_NAME=Linux
        -DCMAKE_SYSTEM_PROCESSOR=aarch64
        -DCMAKE_C_COMPILER="$cc"
        -DCMAKE_CXX_COMPILER="$cxx"
      )
    else
      artifact_arch=x86_64
      cc="${CC:-gcc}"
      cxx="${CXX:-g++}"
      strip_tool="${STRIP:-strip}"
      verification_nm="${NM:-nm}"
      verification_readelf="${READELF:-readelf}"
      cmake_args+=(
        -DCMAKE_C_COMPILER="$cc"
        -DCMAKE_CXX_COMPILER="$cxx"
        -DZXD_BUILD_TESTS=ON
      )
      run_smoke=true
    fi
    output_name=libzxing_dart.so
    ;;
  windows-x64)
    os=windows
    [[ "$(uname -s)" == Linux ]] || {
      echo 'Windows artifacts must be cross-built on Linux; use build_native_windows_docker.sh.' >&2
      exit 1
    }
    artifact_arch=x86_64
    # Debian's default MinGW alternative uses the win32 thread model, whose
    # libstdc++ lacks std::once_flag/call_once. zxing-cpp requires them, so pin
    # the POSIX-thread compiler variant and statically fold libwinpthread in.
    cc="${CC:-x86_64-w64-mingw32-gcc-posix}"
    cxx="${CXX:-x86_64-w64-mingw32-g++-posix}"
    strip_tool="${STRIP:-x86_64-w64-mingw32-strip}"
    verification_nm="${NM:-x86_64-w64-mingw32-nm}"
    verification_objdump="${OBJDUMP:-x86_64-w64-mingw32-objdump}"
    cmake_args+=(
      -DCMAKE_SYSTEM_NAME=Windows
      -DCMAKE_SYSTEM_PROCESSOR=x86_64
      -DCMAKE_C_COMPILER="$cc"
      -DCMAKE_CXX_COMPILER="$cxx"
      -DCMAKE_RC_COMPILER="${WINDRES:-x86_64-w64-mingw32-windres}"
      -DCMAKE_SHARED_LINKER_FLAGS=-Wl,--no-insert-timestamp
    )
    output_name=zxing_dart.dll
    ;;
esac

jobs="${ZXD_BUILD_JOBS:-$(sysctl -n hw.logicalcpu 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)}"
rm -rf "$build_dir"
cmake -S "$root" -B "$build_dir" "${cmake_args[@]}"
cmake --build "$build_dir" --target zxing_dart --parallel "$jobs"
if [[ "$run_smoke" == true ]]; then
  cmake --build "$build_dir" --target zxd_smoke_test --parallel "$jobs"
  if [[ "$os" == macos && "$artifact_arch" == x86_64 && "$(uname -m)" == arm64 ]]; then
    arch -x86_64 "$build_dir/zxd_smoke_test"
  else
    "$build_dir/zxd_smoke_test"
  fi
fi

built_artifact="$build_dir/$output_name"
[[ -f "$built_artifact" ]] || {
  echo "Expected artifact missing: $built_artifact" >&2
  exit 1
}
mkdir -p "$artifact_dir"
artifact="$artifact_dir/$output_name"
cp "$built_artifact" "$artifact"
if [[ "$os" == android || "$os" == linux ]]; then
  "$strip_tool" --strip-unneeded "$artifact"
elif [[ "$os" == windows ]]; then
  "$strip_tool" --strip-unneeded "$artifact"
else
  "$strip_tool" -x "$artifact"
fi

expected_exports="$build_dir/expected_exports.txt"
cat > "$expected_exports" <<'EOF'
zxd_abi_version
zxd_build_info
zxd_encode_aztec
zxd_matrix_release
zxd_read
zxd_read_result_release
EOF

if [[ "$os" == macos || "$os" == ios ]]; then
  actual_arch="$(lipo -archs "$artifact")"
  [[ "$actual_arch" == "$artifact_arch" ]] || {
    echo "Wrong architecture: expected $artifact_arch, got $actual_arch" >&2
    exit 1
  }
  install_name="$(otool -D "$artifact" | tail -1 | tr -d '[:space:]')"
  [[ "$install_name" == @rpath/libzxing_dart.dylib ]] || {
    echo "Unexpected install name: $install_name" >&2
    exit 1
  }
  if otool -L "$artifact" | tail -n +2 | grep -E 'ZXing|/opt/homebrew|/usr/local'; then
    echo 'Artifact has a non-system or unbundled dependency.' >&2
    exit 1
  fi
  nm -gU "$artifact" | awk '{print $3}' | sed 's/^_//' | sort > "$build_dir/actual_exports.txt"

  build_version="$(xcrun vtool -show-build "$artifact")"
  expected_platform=MACOS
  expected_min=12.0
  if [[ "$os" == ios ]]; then
    expected_min=13.0
    [[ "$target" == *-iphoneos ]] && expected_platform=IOS || expected_platform=IOSSIMULATOR
    # arm64 iOS Simulator is only available from iOS 14. The deployment flag
    # is intentionally 13 for source parity, but ld records the first runtime
    # on which that simulator architecture exists.
    [[ "$target" == ios-arm64-iphonesimulator ]] && expected_min=14.0
  fi
  grep -q "platform $expected_platform" <<<"$build_version" || {
    echo "Missing expected Apple platform $expected_platform" >&2; exit 1;
  }
  grep -q "minos $expected_min" <<<"$build_version" || {
    echo "Missing expected minimum OS $expected_min" >&2; exit 1;
  }
elif [[ "$os" == android || "$os" == linux ]]; then
  machine="$($verification_readelf -h "$artifact" | awk -F: '/Machine:/ {sub(/^[[:space:]]+/, "", $2); print $2}')"
  case "$target:$machine" in
    android-arm:'ARM') ;;
    android-arm64:'AArch64') ;;
    android-x64:'Advanced Micro Devices X86-64') ;;
    linux-arm64:'AArch64') ;;
    linux-x64:'Advanced Micro Devices X86-64') ;;
    *) echo "Unexpected ELF machine for $target: $machine" >&2; exit 1 ;;
  esac
  forbidden_dependency='ZXing|c\+\+_shared'
  [[ "$os" == linux ]] && forbidden_dependency='ZXing|libstdc\+\+|libgcc_s'
  if "$verification_readelf" -d "$artifact" | grep -E "NEEDED.*($forbidden_dependency)"; then
    echo 'Artifact unexpectedly has an unbundled C++/ZXing dependency.' >&2
    exit 1
  fi
  if [[ "$os" == linux ]]; then
    "$verification_readelf" -d "$artifact" | grep 'SONAME.*libzxing_dart.so' >/dev/null || {
      echo 'Linux artifact has no canonical libzxing_dart.so SONAME.' >&2; exit 1;
    }
    if "$verification_readelf" -d "$artifact" | grep -E 'RPATH|RUNPATH'; then
      echo 'Linux artifact unexpectedly embeds an RPATH/RUNPATH.' >&2; exit 1;
    fi
  fi
  if [[ "$os" == android ]]; then
    # Android 15+ supports 16KB page-size devices. Every LOAD segment must
    # have the requested 0x4000 alignment.
    "$verification_readelf" -lW "$artifact" \
      | awk '$1 == "LOAD" { print $NF }' > "$build_dir/load_alignments.txt"
    if [[ ! -s "$build_dir/load_alignments.txt" ]] || \
        grep -Evq '^0x0*4000$' "$build_dir/load_alignments.txt"; then
      echo 'ELF LOAD segments are not all 16KB-page aligned.' >&2
      exit 1
    fi
  fi
  "$verification_nm" -D --defined-only "$artifact" \
    | awk '{print $3}' | sed 's/@@.*//; /^ZXING_DART_1$/d' | sort -u \
    > "$build_dir/actual_exports.txt"
elif [[ "$os" == windows ]]; then
  machine="$($verification_objdump -f "$artifact" | awk '/architecture:/ {gsub(",", "", $2); print $2}')"
  [[ "$machine" == i386:x86-64 ]] || {
    echo "Unexpected PE machine: $machine" >&2; exit 1;
  }
  if "$verification_objdump" -p "$artifact" \
      | grep -Ei 'DLL Name:.*(ZXing|libstdc\+\+|libgcc_s|winpthread)'; then
    echo 'Windows artifact has an unbundled C++/ZXing runtime dependency.' >&2
    exit 1
  fi
  "$verification_objdump" -p "$artifact" \
    | awk '
        /\[Ordinal\/Name Pointer\] Table/ { exports=1; next }
        exports && /^\t\[[[:space:]]*[0-9]+\]/ { print $NF; next }
        exports && NF == 0 { exit }
      ' | sort -u \
    > "$build_dir/actual_exports.txt"
fi

if ! diff -u "$expected_exports" "$build_dir/actual_exports.txt"; then
  echo 'Artifact export surface does not match the six-call shim ABI.' >&2
  exit 1
fi

strings "$artifact" | grep 'zxing_dart ABI 1; zxing-cpp 2.3.0' >/dev/null || {
  echo 'Artifact build-info string is missing or unexpected.' >&2
  exit 1
}

sha256="$(shasum -a 256 "$artifact" | awk '{print $1}')"
size="$(wc -c < "$artifact" | tr -d ' ')"
echo "Built $artifact"
echo "target=$target"
echo "sha256=$sha256"
echo "size=$size"

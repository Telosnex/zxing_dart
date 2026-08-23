cmake_minimum_required(VERSION 3.16)

project(zxing_dart LANGUAGES CXX)

# zxing-cpp 3.x uses concepts/ranges and requires C++20. This also avoids the
# old C++17 char8_t alias incompatibility in current Emscripten/Android libc++.
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

option(ZXD_BUILD_TESTS "Build native conformance/smoke tests" OFF)

# zxing-cpp, pinned by tool/fetch_zxing.sh. Static, folded into our one
# shared lib so the shipped artifact is a single binary.
set(BUILD_SHARED_LIBS OFF)
set(ZXING_READERS ON)
# Preserve this package's documented Aztec ECC 0..8 behavior. v3's new
# zint-backed writer has percentage/string ECC semantics; the retained classic
# writer is the compatible API while the reader receives all 3.1.1 changes.
set(ZXING_WRITERS OLD)
set(ZXING_C_API OFF)
set(ZXING_EXAMPLES OFF)
set(ZXING_UNIT_TESTS OFF)
if(NOT EXISTS ${CMAKE_CURRENT_SOURCE_DIR}/third_party/zxing-cpp/core/CMakeLists.txt)
  message(FATAL_ERROR "zxing-cpp not found. Run: tool/fetch_zxing.sh")
endif()
add_subdirectory(third_party/zxing-cpp/core EXCLUDE_FROM_ALL)

if(EMSCRIPTEN)
  # tool/build_web.sh performs the final Emscripten ES-module link explicitly.
  add_library(zxing_dart STATIC src/zxing_dart.cpp)
else()
  add_library(zxing_dart SHARED src/zxing_dart.cpp)
endif()
target_link_libraries(zxing_dart PRIVATE ZXing)
set_target_properties(zxing_dart PROPERTIES
  CXX_VISIBILITY_PRESET hidden
  VISIBILITY_INLINES_HIDDEN ON
)

if(APPLE)
  # Static archives retain their own symbol visibility when folded into a
  # dylib. Export only our stable C ABI, never the hundreds of zxing-cpp C++
  # implementation symbols.
  target_link_options(zxing_dart PRIVATE
    "-Wl,-exported_symbols_list,${CMAKE_CURRENT_SOURCE_DIR}/src/exports_apple.txt"
  )
  set_target_properties(zxing_dart PROPERTIES
    BUILD_WITH_INSTALL_RPATH ON
    INSTALL_NAME_DIR "@rpath"
  )
endif()

if(ANDROID)
  find_library(log-lib log)
  target_link_libraries(zxing_dart PRIVATE ${log-lib})
  # 16KB page size support with NDK 27.x; default in NDK 28+.
  target_link_options(zxing_dart PRIVATE
    "-Wl,-z,max-page-size=16384"
    "-Wl,--version-script=${CMAKE_CURRENT_SOURCE_DIR}/src/exports_elf.map"
    "-Wl,--exclude-libs,ALL"
    "-Wl,-z,relro,-z,now"
  )
endif()

if(UNIX AND NOT APPLE AND NOT ANDROID AND NOT EMSCRIPTEN)
  target_link_options(zxing_dart PRIVATE
    -static-libgcc -static-libstdc++
    "-Wl,--version-script=${CMAKE_CURRENT_SOURCE_DIR}/src/exports_elf.map"
    "-Wl,--exclude-libs,ALL"
    "-Wl,-z,relro,-z,now"
  )
endif()

if(WIN32)
  # CoTaskMemAlloc/CoTaskMemFree are the allocator pair used by package:ffi on
  # Windows. A .def file makes the complete public surface auditable and keeps
  # all statically folded zxing-cpp symbols private.
  target_sources(zxing_dart PRIVATE src/exports_windows.def)
  target_link_libraries(zxing_dart PRIVATE ole32)
  if(MINGW)
    target_link_options(zxing_dart PRIVATE
      -static -static-libgcc -static-libstdc++
      "-Wl,--no-insert-timestamp"
    )
  endif()
  set_target_properties(zxing_dart PROPERTIES PREFIX "" OUTPUT_NAME "zxing_dart")
endif()

if(ZXD_BUILD_TESTS)
  add_executable(zxd_smoke_test native_test/smoke_test.cpp)
  target_include_directories(zxd_smoke_test PRIVATE src)
  target_link_libraries(zxd_smoke_test PRIVATE zxing_dart)
endif()

cmake_minimum_required(VERSION 3.16)

project(zxing_dart LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

option(ZXD_BUILD_TESTS "Build native conformance/smoke tests" OFF)

# zxing-cpp, pinned by tool/fetch_zxing.sh. Static, folded into our one
# shared lib so the shipped artifact is a single binary.
set(BUILD_SHARED_LIBS OFF)
set(ZXING_READERS ON)
set(ZXING_WRITERS ON)
if(NOT EXISTS ${CMAKE_CURRENT_SOURCE_DIR}/third_party/zxing-cpp/core/CMakeLists.txt)
  message(FATAL_ERROR "zxing-cpp not found. Run: tool/fetch_zxing.sh")
endif()
add_subdirectory(third_party/zxing-cpp/core EXCLUDE_FROM_ALL)

add_library(zxing_dart SHARED src/zxing_dart.cpp)
target_link_libraries(zxing_dart PRIVATE ZXing)
set_target_properties(zxing_dart PROPERTIES
  CXX_VISIBILITY_PRESET hidden
  VISIBILITY_INLINES_HIDDEN ON
)

if(ANDROID)
  find_library(log-lib log)
  target_link_libraries(zxing_dart PRIVATE ${log-lib})
  # 16KB page size support with NDK 27.x; default in NDK 28+.
  target_link_options(zxing_dart PRIVATE "-Wl,-z,max-page-size=16384")
endif()

if(ZXD_BUILD_TESTS)
  add_executable(zxd_smoke_test native_test/smoke_test.cpp)
  target_include_directories(zxd_smoke_test PRIVATE src)
  target_link_libraries(zxd_smoke_test PRIVATE zxing_dart)
endif()

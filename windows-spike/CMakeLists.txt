cmake_minimum_required(VERSION 3.25)
project(aureon_windows_native LANGUAGES CXX)

add_library(aureon_filesystem src/filesystem.cpp)
target_include_directories(aureon_filesystem PUBLIC include)
target_compile_features(aureon_filesystem PUBLIC cxx_std_20)

if(MSVC)
  target_compile_options(aureon_filesystem PRIVATE /W4 /permissive- /utf-8)
endif()

enable_testing()
add_executable(aureon_filesystem_tests tests/filesystem_tests.cpp)
target_link_libraries(aureon_filesystem_tests PRIVATE aureon_filesystem)
add_test(NAME aureon_filesystem_tests COMMAND aureon_filesystem_tests)

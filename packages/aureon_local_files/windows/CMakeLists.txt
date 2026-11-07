cmake_minimum_required(VERSION 3.14)
project(aureon_local_files_plugin LANGUAGES CXX)

add_library(aureon_local_files_plugin SHARED
  "aureon_local_files_plugin.cpp"
  "aureon_local_files_plugin_c_api.cpp"
)
apply_standard_settings(aureon_local_files_plugin)
set_target_properties(aureon_local_files_plugin PROPERTIES
  CXX_VISIBILITY_PRESET hidden
)
target_compile_features(aureon_local_files_plugin PUBLIC cxx_std_20)
target_include_directories(aureon_local_files_plugin PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_link_libraries(aureon_local_files_plugin PRIVATE flutter flutter_wrapper_plugin ole32 shell32)

cmake_minimum_required(VERSION 3.22.1)
project(thingboot_device LANGUAGES CXX)

add_library(thingboot_core STATIC IMPORTED GLOBAL)
set_target_properties(thingboot_core PROPERTIES
  IMPORTED_LOCATION "${CMAKE_CURRENT_SOURCE_DIR}/src/main/cpp/prebuilt/${ANDROID_ABI}/libthingboot_core.a")

add_library(thingboot_device SHARED "src/main/cpp/thingboot_device.cpp")
target_link_options(thingboot_device PRIVATE
  "-Wl,-z,max-page-size=16384"
  "-Wl,--version-script=${CMAKE_CURRENT_SOURCE_DIR}/src/main/cpp/exports.map")
target_link_libraries(thingboot_device PRIVATE thingboot_core c++_static)

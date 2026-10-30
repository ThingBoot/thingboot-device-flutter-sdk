cmake_minimum_required(VERSION 3.14)
project(thingboot_device LANGUAGES CXX)

add_library(thingboot_core STATIC IMPORTED GLOBAL)
set_target_properties(thingboot_core PROPERTIES
  IMPORTED_LOCATION "${CMAKE_CURRENT_SOURCE_DIR}/lib/thingboot_core.lib")
add_library(thingboot_core_debug STATIC IMPORTED GLOBAL)
set_target_properties(thingboot_core_debug PROPERTIES
  IMPORTED_LOCATION "${CMAKE_CURRENT_SOURCE_DIR}/lib/thingboot_core_debug.lib")

add_library(thingboot_device SHARED "cpp/thingboot_device.cpp")
if(MSVC)
  target_compile_options(thingboot_device PRIVATE /utf-8)
endif()
target_link_libraries(thingboot_device PRIVATE
  $<$<CONFIG:Debug>:thingboot_core_debug>
  $<$<NOT:$<CONFIG:Debug>>:thingboot_core>)

set(thingboot_device_bundled_libraries
  $<TARGET_FILE:thingboot_device>
  PARENT_SCOPE)

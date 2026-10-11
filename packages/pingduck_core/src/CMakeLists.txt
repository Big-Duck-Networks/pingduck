# Builds pingduck-core (the repo's core/ directory) as the plugin's shared
# library, for Android (Gradle externalNativeBuild), Windows and Linux.
# iOS and macOS compile the same sources through the podspecs instead.
cmake_minimum_required(VERSION 3.20)

project(pingduck_core_library LANGUAGES CXX)

set(PINGDUCK_BUILD_SHARED ON)
set(PINGDUCK_BUILD_CLI OFF)
set(PINGDUCK_BUILD_TESTS OFF)
set(PINGDUCK_PCAP OFF)  # raw ARP is for the headless agent, not the app
# The core is ../../../core from this package. Windows and Linux reach this
# file through pingduck_app/<platform>/flutter/ephemeral/.plugin_symlinks/,
# where that relative path doesn't hold (CMake doesn't resolve the link), so
# also try the repo root seen from there. PINGDUCK_CORE_DIR overrides both.
set(PINGDUCK_CORE_DIR "" CACHE PATH "pingduck-core source directory")
if(NOT PINGDUCK_CORE_DIR)
  foreach(candidate
      "${CMAKE_CURRENT_SOURCE_DIR}/../../../core"
      "${CMAKE_CURRENT_SOURCE_DIR}/../../../../../../../core")
    if(EXISTS "${candidate}/CMakeLists.txt")
      get_filename_component(PINGDUCK_CORE_DIR "${candidate}" ABSOLUTE)
      break()
    endif()
  endforeach()
endif()
if(NOT PINGDUCK_CORE_DIR)
  message(FATAL_ERROR "pingduck_core: core/ not found; set PINGDUCK_CORE_DIR")
endif()
add_subdirectory("${PINGDUCK_CORE_DIR}" "${CMAKE_CURRENT_BINARY_DIR}/core")

if(ANDROID)
  # Android 15+ devices may use 16 KB pages.
  target_link_options(pingduck PRIVATE "-Wl,-z,max-page-size=16384")
endif()

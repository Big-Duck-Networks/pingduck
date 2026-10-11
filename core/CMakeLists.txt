cmake_minimum_required(VERSION 3.20)
project(pingduck_core VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_VISIBILITY_PRESET hidden)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

if(CMAKE_SOURCE_DIR STREQUAL PROJECT_SOURCE_DIR)
  set(PINGDUCK_TOP_LEVEL ON)
else()
  set(PINGDUCK_TOP_LEVEL OFF)
endif()

option(PINGDUCK_BUILD_CLI "Build the pingduck command-line tool" ON)
option(PINGDUCK_BUILD_SHARED "Build libpingduck as a shared library (for Dart FFI)" ON)
option(PINGDUCK_BUILD_TESTS "Build the unit tests (run with ctest)" ${PINGDUCK_TOP_LEVEL})
# Instruments the library for libFuzzer and builds core/fuzz. Needs Clang or
# MSVC 2022, and turns the CLI and tests off (they cannot share instrumented code).
option(PINGDUCK_BUILD_FUZZERS "Build libFuzzer targets with ASan" OFF)
# GCC/Clang only, e.g. "address,undefined". Applies to every target.
set(PINGDUCK_SANITIZE "" CACHE STRING "Sanitizers to enable (-fsanitize=...)")
# AUTO: use libpcap when found (Linux agent); ON: require it; OFF: never.
set(PINGDUCK_PCAP "AUTO" CACHE STRING "libpcap ARP sniffing: AUTO, ON, OFF")

if(PINGDUCK_BUILD_FUZZERS)
  set(PINGDUCK_BUILD_CLI OFF)
  set(PINGDUCK_BUILD_TESTS OFF)
endif()

if(PINGDUCK_SANITIZE)
  if(MSVC)
    message(FATAL_ERROR "PINGDUCK_SANITIZE is for GCC/Clang; use PINGDUCK_BUILD_FUZZERS for ASan on MSVC")
  endif()
  add_compile_options(-fsanitize=${PINGDUCK_SANITIZE} -fno-omit-frame-pointer -fno-sanitize-recover=all)
  add_link_options(-fsanitize=${PINGDUCK_SANITIZE})
endif()

set(PINGDUCK_SOURCES
    src/core.cpp
    src/dns.cpp
    src/interfaces.cpp
    src/icmp.cpp
    src/mdns.cpp
    src/ssdp.cpp
    src/arp.cpp
    src/oui.cpp
    src/scan.cpp
    src/net_util.cpp
)

# Everything is compiled once into an object library: the shipped library is
# built from it, and the tests and fuzzers link it directly so they can reach
# internal parsers that the hidden-visibility shared library does not export.
add_library(pingduck_objects OBJECT ${PINGDUCK_SOURCES})
target_include_directories(pingduck_objects
  PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/include
  INTERFACE ${CMAKE_CURRENT_SOURCE_DIR}/src)
target_compile_definitions(pingduck_objects PRIVATE PINGDUCK_BUILDING PINGDUCK_VERSION="${PROJECT_VERSION}")

find_package(Threads REQUIRED)
target_link_libraries(pingduck_objects PUBLIC Threads::Threads)

if(WIN32)
  target_link_libraries(pingduck_objects PUBLIC ws2_32 iphlpapi)
endif()

if(MSVC)
  target_compile_options(pingduck_objects PRIVATE /W4 /permissive- /utf-8)
else()
  target_compile_options(pingduck_objects PRIVATE -Wall -Wextra -Wno-missing-field-initializers)
endif()

if(NOT PINGDUCK_PCAP STREQUAL "OFF" AND NOT WIN32 AND NOT ANDROID AND NOT IOS)
  find_library(PCAP_LIBRARY pcap)
  find_path(PCAP_INCLUDE_DIR pcap/pcap.h)
  if(PCAP_LIBRARY AND PCAP_INCLUDE_DIR)
    message(STATUS "pingduck: libpcap ARP sniffing enabled (${PCAP_LIBRARY})")
    target_compile_definitions(pingduck_objects PRIVATE PINGDUCK_WITH_PCAP)
    target_include_directories(pingduck_objects PRIVATE ${PCAP_INCLUDE_DIR})
    target_link_libraries(pingduck_objects PUBLIC ${PCAP_LIBRARY})
  elseif(PINGDUCK_PCAP STREQUAL "ON")
    message(FATAL_ERROR "PINGDUCK_PCAP=ON but libpcap was not found")
  endif()
endif()

if(PINGDUCK_BUILD_SHARED)
  add_library(pingduck SHARED)
else()
  add_library(pingduck STATIC)
endif()
target_link_libraries(pingduck PRIVATE pingduck_objects)
target_include_directories(pingduck PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/include)
target_compile_definitions(pingduck INTERFACE $<$<BOOL:${PINGDUCK_BUILD_SHARED}>:PINGDUCK_SHARED>)

if(PINGDUCK_BUILD_CLI)
  add_executable(pingduck_cli cli/main.cpp)
  set_target_properties(pingduck_cli PROPERTIES OUTPUT_NAME pingduck_cli)
  target_link_libraries(pingduck_cli PRIVATE pingduck)
  if(WIN32 AND PINGDUCK_BUILD_SHARED)
    # Put the DLL next to the exe so the CLI runs from the build dir.
    set_target_properties(pingduck pingduck_cli PROPERTIES
      RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)
  endif()
  install(TARGETS pingduck_cli RUNTIME DESTINATION bin)
endif()

# The agent's Docker build copies only the sources it ships, without tests/.
if(PINGDUCK_BUILD_TESTS AND EXISTS ${CMAKE_CURRENT_SOURCE_DIR}/tests/CMakeLists.txt)
  enable_testing()
  add_subdirectory(tests)
endif()

if(PINGDUCK_BUILD_FUZZERS)
  add_subdirectory(fuzz)
endif()

# Only when built on its own: the Flutter plugin bundles the library itself,
# and the Windows app's install prefix isn't a real path for these rules.
if(PINGDUCK_TOP_LEVEL)
  install(TARGETS pingduck LIBRARY DESTINATION lib ARCHIVE DESTINATION lib RUNTIME DESTINATION bin)
  install(DIRECTORY include/ DESTINATION include)
endif()

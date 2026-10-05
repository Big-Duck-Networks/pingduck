cmake_minimum_required(VERSION 3.20)
project(pingduck_core VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_VISIBILITY_PRESET hidden)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

option(PINGDUCK_BUILD_CLI "Build the pingduck command-line tool" ON)
option(PINGDUCK_BUILD_SHARED "Build libpingduck as a shared library (for Dart FFI)" ON)
# AUTO: use libpcap when found (Linux agent); ON: require it; OFF: never.
set(PINGDUCK_PCAP "AUTO" CACHE STRING "libpcap ARP sniffing: AUTO, ON, OFF")

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

if(PINGDUCK_BUILD_SHARED)
  add_library(pingduck SHARED ${PINGDUCK_SOURCES})
else()
  add_library(pingduck STATIC ${PINGDUCK_SOURCES})
endif()

target_include_directories(pingduck PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/include)
target_compile_definitions(pingduck
  PRIVATE PINGDUCK_BUILDING PINGDUCK_VERSION="${PROJECT_VERSION}"
  INTERFACE $<$<BOOL:${PINGDUCK_BUILD_SHARED}>:PINGDUCK_SHARED>)

find_package(Threads REQUIRED)
target_link_libraries(pingduck PRIVATE Threads::Threads)

if(WIN32)
  target_link_libraries(pingduck PRIVATE ws2_32 iphlpapi)
endif()

if(MSVC)
  target_compile_options(pingduck PRIVATE /W4 /permissive- /utf-8)
else()
  target_compile_options(pingduck PRIVATE -Wall -Wextra -Wno-missing-field-initializers)
endif()

if(NOT PINGDUCK_PCAP STREQUAL "OFF" AND NOT WIN32 AND NOT ANDROID AND NOT IOS)
  find_library(PCAP_LIBRARY pcap)
  find_path(PCAP_INCLUDE_DIR pcap/pcap.h)
  if(PCAP_LIBRARY AND PCAP_INCLUDE_DIR)
    message(STATUS "pingduck: libpcap ARP sniffing enabled (${PCAP_LIBRARY})")
    target_compile_definitions(pingduck PRIVATE PINGDUCK_WITH_PCAP)
    target_include_directories(pingduck PRIVATE ${PCAP_INCLUDE_DIR})
    target_link_libraries(pingduck PRIVATE ${PCAP_LIBRARY})
  elseif(PINGDUCK_PCAP STREQUAL "ON")
    message(FATAL_ERROR "PINGDUCK_PCAP=ON but libpcap was not found")
  endif()
endif()

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

install(TARGETS pingduck LIBRARY DESTINATION lib ARCHIVE DESTINATION lib RUNTIME DESTINATION bin)
install(DIRECTORY include/ DESTINATION include)

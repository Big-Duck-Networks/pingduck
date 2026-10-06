# libFuzzer targets for every parser that reads untrusted LAN input.
#
#   Clang (Linux/macOS):
#     cmake -S core -B build-fuzz -DCMAKE_CXX_COMPILER=clang++ -DPINGDUCK_BUILD_FUZZERS=ON
#   MSVC 2022 (x64, RelWithDebInfo; ASan's DLL must be on PATH to run):
#     cmake -S core -B build-fuzz -G "Visual Studio 17 2022" -A x64 -DPINGDUCK_BUILD_FUZZERS=ON
#
#   Run:  build-fuzz/fuzz/fuzz_mdns -dict=core/fuzz/dict/dns.dict -max_total_time=300 corpus/
#
# The library objects get coverage instrumentation; each target links the
# libFuzzer runtime. UBSan is added on Clang (MSVC has no UBSan).

set(PINGDUCK_FUZZERS fuzz_dns fuzz_mdns fuzz_ssdp fuzz_misc)

if(MSVC)
  set(instrument /fsanitize=address /fsanitize-coverage=inline-8bit-counters
                 /fsanitize-coverage=edge /fsanitize-coverage=trace-cmp /fsanitize-coverage=trace-div /Zi)
  set(link_runtime /fsanitize=address /fsanitize=fuzzer /Zi)
  # ASan is incompatible with incremental linking and /RTC.
  string(REGEX REPLACE "/RTC[^ ]*" "" CMAKE_CXX_FLAGS_DEBUG "${CMAKE_CXX_FLAGS_DEBUG}")
  add_link_options(/INCREMENTAL:NO /DEBUG)
elseif(CMAKE_CXX_COMPILER_ID MATCHES "Clang")
  set(instrument -fsanitize=fuzzer-no-link,address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer -g)
  set(link_runtime -fsanitize=fuzzer,address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer -g)
else()
  message(FATAL_ERROR "PINGDUCK_BUILD_FUZZERS needs Clang or MSVC")
endif()

target_compile_options(pingduck_objects PRIVATE ${instrument})
# The shipped library would need the fuzzer runtime too; it is not built here.
set_target_properties(pingduck PROPERTIES EXCLUDE_FROM_ALL ON)

foreach(name ${PINGDUCK_FUZZERS})
  add_executable(${name} ${name}.cpp)
  target_link_libraries(${name} PRIVATE pingduck_objects)
  target_compile_options(${name} PRIVATE ${link_runtime})
  if(NOT MSVC)
    target_link_options(${name} PRIVATE ${link_runtime})
  endif()
endforeach()

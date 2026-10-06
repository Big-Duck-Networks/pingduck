#
# pingduck-core for iOS. CocoaPods only compiles files inside the pod, so
# Classes/ holds one forwarder per core/src/*.cpp that #includes the shared
# source. Keep it in sync when core/src gains or loses a file.
#
Pod::Spec.new do |s|
  s.name             = 'pingduck_core'
  s.version          = '0.1.0'
  s.summary          = 'PingDuck LAN discovery engine (FFI).'
  s.description      = 'ICMP, mDNS, SSDP/UPnP discovery and diagnostics from pingduck-core.'
  s.homepage         = 'https://github.com/Big-Duck-Networks/pingduck'
  s.license          = { :file => '../LICENSE' }
  s.author           = 'Big Duck Networks'

  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'HEADER_SEARCH_PATHS' => '"$(PODS_TARGET_SRCROOT)/../../../core/include"',
    'GCC_PREPROCESSOR_DEFINITIONS' => '$(inherited) PINGDUCK_BUILDING=1 PINGDUCK_VERSION=\"0.1.0\"',
  }
  s.library = 'c++'
  s.swift_version = '5.0'
end

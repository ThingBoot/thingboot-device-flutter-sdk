Pod::Spec.new do |s|
  s.name = 'thingboot_device'
  s.version = '0.4.0'
  s.summary = 'ThingBoot Device Flutter SDK native core'
  s.description = 'Static native protocol core for ThingBoot Device Flutter SDK.'
  s.homepage = 'https://github.com/ThingBoot/thingboot-device-flutter-sdk'
  s.license = { :type => 'Proprietary' }
  s.author = 'ThingBoot'
  s.source = { :path => '.' }
  s.source_files = 'Classes/thingboot_device.cpp'
  s.vendored_libraries = 'Classes/prebuilt/libthingboot_core.a'
  s.preserve_paths = 'Classes/prebuilt/libthingboot_core.a', 'Classes/exports.txt'
  s.dependency 'FlutterMacOS'
  s.platform = :osx, '12.0'
  s.static_framework = false
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'MACOSX_DEPLOYMENT_TARGET' => '12.0',
    'OTHER_LDFLAGS' => '-Wl,-exported_symbols_list,$(PODS_TARGET_SRCROOT)/Classes/exports.txt'
  }
end

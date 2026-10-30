Pod::Spec.new do |s|
  s.name = 'thingboot_device'
  s.version = '0.5.0'
  s.summary = 'ThingBoot Device Flutter SDK native core'
  s.description = 'Static native protocol core for ThingBoot Device Flutter SDK.'
  s.homepage = 'https://github.com/ThingBoot/thingboot-device-flutter-sdk'
  s.license = { :type => 'Proprietary' }
  s.author = 'ThingBoot'
  s.source = { :path => '.' }
  s.source_files = 'Classes/thingboot_device.cpp'
  s.preserve_paths = 'Classes/prebuilt', 'Classes/ThingBootCore.xcframework', 'Classes/exports.txt'
  s.dependency 'Flutter'
  s.platform = :ios, '15.0'
  s.static_framework = true
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'IPHONEOS_DEPLOYMENT_TARGET' => '15.0'
  }
  s.user_target_xcconfig = {
    'LIBRARY_SEARCH_PATHS' => '$(inherited) "$(PODS_ROOT)/../.symlinks/plugins/thingboot_device/ios/Classes/prebuilt/$(PLATFORM_NAME)"',
    'OTHER_LDFLAGS' => '$(inherited) -all_load -Wl,-export_dynamic -l"thingboot_core"'
  }
end

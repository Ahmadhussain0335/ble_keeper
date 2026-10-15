#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint ble_keeper.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'ble_keeper'
  s.version          = '0.1.0-beta.2'
  s.summary          = 'Keeps a BLE peripheral connected in the background on iOS.'
  s.description      = <<-DESC
Owns the Core Bluetooth connection with state restoration so it survives the
Flutter UI, system termination and reboots.
                       DESC
  s.homepage         = 'https://github.com/Ahmadhussain0335/ble_keeper'
  s.license          = { :type => 'BSD-3-Clause', :file => '../LICENSE' }
  s.author           = { 'Ahmad Hussain' => 'https://github.com/Ahmadhussain0335' }
  s.source           = { :path => '.' }
  s.source_files = 'ble_keeper/Sources/ble_keeper/**/*.swift'
  s.dependency 'Flutter'
  s.frameworks = 'CoreBluetooth'
  s.platform = :ios, '15.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  # The plugin uses no required-reason APIs and collects no data; the
  # manifest states that explicitly.
  s.resource_bundles = {'ble_keeper_privacy' => ['ble_keeper/Sources/ble_keeper/PrivacyInfo.xcprivacy']}
end

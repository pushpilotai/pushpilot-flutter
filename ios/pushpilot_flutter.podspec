# CocoaPods spec for apps that build iOS with CocoaPods instead of Swift Package Manager.
Pod::Spec.new do |s|
  s.name             = 'pushpilot_flutter'
  s.version          = '2.1.1'
  s.summary          = 'Flutter plugin for the PushPilot SDK.'
  s.homepage         = 'https://pushpilot.ai'
  s.author           = { 'PushPilot' => 'https://pushpilot.ai' }
  s.source           = { :path => '.' }
  s.source_files     = 'pushpilot_flutter/Sources/pushpilot_flutter/**/*'
  s.dependency 'Flutter'
  # From CocoaPods trunk; for local development the app's Podfile points it at a pushpilot-ios checkout (see README).
  s.dependency 'PushPilot', '2.2.0'
  s.platform = :ios, '15.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.9'
end

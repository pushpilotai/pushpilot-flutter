# Podspec for the native PushPilot iOS SDK, which ships only as a Swift package. Local development only:
# it builds the sibling `pushpilot-ios` checkout (committed state of its current branch). At release this
# file belongs in the pushpilot-ios repository with `:git` set to its public URL and `:tag` to the version.
Pod::Spec.new do |s|
  s.name          = 'PushPilot'
  s.version       = '1.0.0'
  s.summary       = 'Registers an app installation with PushPilot and forwards its FCM push token.'
  s.homepage      = 'https://pushpilot.ai'
  s.author        = { 'PushPilot' => 'https://pushpilot.ai' }
  s.source        = { :git => File.expand_path('../../../pushpilot-ios', __dir__) }
  s.platform      = :ios, '15.0'
  s.swift_version = '5.9'
  s.source_files  = 'Sources/PushPilot/**/*.swift'
  s.resource_bundles = { 'PushPilot' => ['Sources/PushPilot/PrivacyInfo.xcprivacy'] }
end

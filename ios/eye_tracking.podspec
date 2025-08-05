Pod::Spec.new do |s|
  s.name             = 'eye_tracking'
  s.version          = '0.1.0'
  s.summary          = 'A Flutter plugin for real-time eye tracking'
  s.description      = <<-DESC
A Flutter plugin for real-time eye tracking with sub-degree accuracy on web, iOS, and Android.
                       DESC
  s.homepage         = 'https://pub.dev/packages/eye_tracking'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Eye Tracking Plugin' => 'support@eyetracking.dev' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform         = :ios, '12.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
  
  # Optional: Add any additional frameworks or dependencies
  s.frameworks = 'AVFoundation', 'CoreML', 'Vision'
end
#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint eye_tracking.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'eye_tracking'
  s.version          = '0.1.0'
  s.summary          = 'High-accuracy eye tracking for Flutter'
  s.description      = <<-DESC
A Flutter plugin for real-time eye tracking with sub-degree accuracy. 
Supports iOS, Android, and web platforms with calibration, gaze coordinates, 
eye state detection, and head pose estimation using ARKit and Vision frameworks.
                       DESC

  s.homepage         = 'https://github.com/Piyushhhhh/eye_tracking'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Piyush' => 'piyushhh01@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
  
  # Required frameworks for eye tracking
  s.frameworks = 'Vision', 'ARKit', 'AVFoundation', 'CoreML', 'VideoToolbox', 'Accelerate', 'UIKit'
  
  # Privacy usage descriptions will be added to the main app's Info.plist
  s.resource_bundles = {
    'EyeTrackingAssets' => ['Assets/**/*']
  }
end
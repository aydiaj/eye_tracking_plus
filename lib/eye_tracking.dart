// You have generated a new plugin project without specifying the `--platforms`
// flag. A plugin project with no platform support was generated. To add a
// platform, run `flutter create -t plugin --platforms <platforms> .` under the
// same directory. You can also find a detailed instruction on how to add
// platforms in the `pubspec.yaml` at
// https://flutter.dev/to/pubspec-plugin-platforms.

import 'eye_tracking_platform_interface.dart';

/// High-accuracy open-source eye tracking plugin for Flutter
///
/// Supports web, iOS, and Android with real-time gaze tracking,
/// calibration, eye state detection, head pose estimation, and more.
class EyeTracking {
  /// Get the current platform version
  Future<String?> getPlatformVersion() {
    return EyeTrackingPlatform.instance.getPlatformVersion();
  }

  /// Initialize the eye tracking system
  ///
  /// Must be called before any other methods.
  /// Returns true if initialization was successful.
  Future<bool> initialize() {
    return EyeTrackingPlatform.instance.initialize();
  }

  /// Request camera permission from the user
  ///
  /// Returns true if permission was granted.
  Future<bool> requestCameraPermission() {
    return EyeTrackingPlatform.instance.requestCameraPermission();
  }

  /// Check if camera permission has been granted
  Future<bool> hasCameraPermission() {
    return EyeTrackingPlatform.instance.hasCameraPermission();
  }

  /// Get the current state of the eye tracking system
  Future<EyeTrackingState> getState() {
    return EyeTrackingPlatform.instance.getState();
  }

  /// Start eye tracking
  ///
  /// Returns true if tracking started successfully.
  /// Requires initialization and camera permission.
  Future<bool> startTracking() {
    return EyeTrackingPlatform.instance.startTracking();
  }

  /// Stop eye tracking
  Future<bool> stopTracking() {
    return EyeTrackingPlatform.instance.stopTracking();
  }

  /// Pause eye tracking
  ///
  /// Can be resumed with [resumeTracking].
  Future<bool> pauseTracking() {
    return EyeTrackingPlatform.instance.pauseTracking();
  }

  /// Resume eye tracking after it was paused
  Future<bool> resumeTracking() {
    return EyeTrackingPlatform.instance.resumeTracking();
  }

  /// Start calibration process
  ///
  /// [points] - List of calibration points to use.
  /// For best accuracy, use 5-9 points distributed across the screen.
  ///
  /// Example:
  /// ```dart
  /// final points = [
  ///   CalibrationPoint(x: 0.1, y: 0.1, order: 0), // Top-left
  ///   CalibrationPoint(x: 0.9, y: 0.1, order: 1), // Top-right
  ///   CalibrationPoint(x: 0.5, y: 0.5, order: 2), // Center
  ///   CalibrationPoint(x: 0.1, y: 0.9, order: 3), // Bottom-left
  ///   CalibrationPoint(x: 0.9, y: 0.9, order: 4), // Bottom-right
  /// ];
  /// await eyeTracking.startCalibration(points);
  /// ```
  Future<bool> startCalibration(List<CalibrationPoint> points) {
    return EyeTrackingPlatform.instance.startCalibration(points);
  }

  /// Add a calibration point
  ///
  /// Call this for each calibration point while the user looks at it.
  /// Hold for ~2-3 seconds per point for best results.
  Future<bool> addCalibrationPoint(CalibrationPoint point) {
    return EyeTrackingPlatform.instance.addCalibrationPoint(point);
  }

  /// Finish the calibration process
  ///
  /// Call after all calibration points have been added.
  Future<bool> finishCalibration() {
    return EyeTrackingPlatform.instance.finishCalibration();
  }

  /// Clear all calibration data
  ///
  /// Useful for starting fresh calibration.
  Future<bool> clearCalibration() {
    return EyeTrackingPlatform.instance.clearCalibration();
  }

  /// Get the current calibration accuracy
  ///
  /// Returns a value between 0.0 and 1.0, where 1.0 is perfect accuracy.
  Future<double> getCalibrationAccuracy() {
    return EyeTrackingPlatform.instance.getCalibrationAccuracy();
  }

  /// Get real-time gaze tracking data
  ///
  /// Stream of [GazeData] containing x, y coordinates (in screen pixels),
  /// confidence level, and timestamp.
  Stream<GazeData> getGazeStream() {
    return EyeTrackingPlatform.instance.getGazeStream();
  }

  /// Get real-time eye state data
  ///
  /// Stream of [EyeState] containing information about whether each eye
  /// is open/closed and blink detection.
  Stream<EyeState> getEyeStateStream() {
    return EyeTrackingPlatform.instance.getEyeStateStream();
  }

  /// Get real-time head pose data
  ///
  /// Stream of [HeadPose] containing pitch, yaw, and roll angles in degrees.
  Stream<HeadPose> getHeadPoseStream() {
    return EyeTrackingPlatform.instance.getHeadPoseStream();
  }

  /// Get real-time face detection data
  ///
  /// Stream of list of [FaceDetection] objects for multiple face support.
  /// Each contains face landmarks and confidence information.
  Stream<List<FaceDetection>> getFaceDetectionStream() {
    return EyeTrackingPlatform.instance.getFaceDetectionStream();
  }

  /// Set the tracking frequency
  ///
  /// [fps] - Target frames per second (typically 30-60).
  /// Higher values provide smoother tracking but use more CPU.
  Future<bool> setTrackingFrequency(int fps) {
    return EyeTrackingPlatform.instance.setTrackingFrequency(fps);
  }

  /// Set the accuracy mode
  ///
  /// [mode] - One of 'high', 'medium', or 'fast'.
  /// - 'high': Best accuracy, higher CPU usage
  /// - 'medium': Balanced accuracy and performance
  /// - 'fast': Lower accuracy, minimal CPU usage
  Future<bool> setAccuracyMode(String mode) {
    return EyeTrackingPlatform.instance.setAccuracyMode(mode);
  }

  /// Enable or disable background tracking
  ///
  /// Note: Background tracking may be limited by platform policies.
  Future<bool> enableBackgroundTracking(bool enable) {
    return EyeTrackingPlatform.instance.enableBackgroundTracking(enable);
  }

  /// Get platform capabilities
  ///
  /// Returns a map describing what features are supported on this platform.
  Future<Map<String, dynamic>> getCapabilities() {
    return EyeTrackingPlatform.instance.getCapabilities();
  }

  /// Dispose and clean up resources
  ///
  /// Call this when you're done using eye tracking to free resources.
  Future<bool> dispose() {
    return EyeTrackingPlatform.instance.dispose();
  }

  /// Create a standard 5-point calibration pattern
  ///
  /// Returns calibration points for corners and center of screen.
  /// [screenWidth] and [screenHeight] should be in pixels.
  static List<CalibrationPoint> createStandardCalibration({
    double screenWidth = 1920,
    double screenHeight = 1080,
  }) {
    const margin = 0.1; // 10% margin from edges
    return [
      CalibrationPoint(
        x: screenWidth * margin,
        y: screenHeight * margin,
        order: 0,
      ), // Top-left
      CalibrationPoint(
        x: screenWidth * (1 - margin),
        y: screenHeight * margin,
        order: 1,
      ), // Top-right
      CalibrationPoint(
        x: screenWidth * 0.5,
        y: screenHeight * 0.5,
        order: 2,
      ), // Center
      CalibrationPoint(
        x: screenWidth * margin,
        y: screenHeight * (1 - margin),
        order: 3,
      ), // Bottom-left
      CalibrationPoint(
        x: screenWidth * (1 - margin),
        y: screenHeight * (1 - margin),
        order: 4,
      ), // Bottom-right
    ];
  }

  /// Create a 9-point calibration pattern for higher accuracy
  ///
  /// Returns calibration points in a 3x3 grid pattern.
  static List<CalibrationPoint> createNinePointCalibration({
    double screenWidth = 1920,
    double screenHeight = 1080,
  }) {
    final points = <CalibrationPoint>[];
    int order = 0;

    for (double x in [0.1, 0.5, 0.9]) {
      for (double y in [0.1, 0.5, 0.9]) {
        points.add(CalibrationPoint(
          x: screenWidth * x,
          y: screenHeight * y,
          order: order++,
        ));
      }
    }

    return points;
  }
}

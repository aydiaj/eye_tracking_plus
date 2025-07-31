import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'eye_tracking_method_channel.dart';

/// Data models for eye tracking
class GazeData {
  final double x;
  final double y;
  final double confidence;
  final DateTime timestamp;

  GazeData({
    required this.x,
    required this.y,
    required this.confidence,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() {
    return {
      'x': x,
      'y': y,
      'confidence': confidence,
      'timestamp': timestamp.millisecondsSinceEpoch,
    };
  }

  factory GazeData.fromMap(Map<String, dynamic> map) {
    return GazeData(
      x: map['x']?.toDouble() ?? 0.0,
      y: map['y']?.toDouble() ?? 0.0,
      confidence: map['confidence']?.toDouble() ?? 0.0,
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] ?? 0),
    );
  }
}

class EyeState {
  final bool leftEyeOpen;
  final bool rightEyeOpen;
  final bool leftEyeBlink;
  final bool rightEyeBlink;
  final DateTime timestamp;

  EyeState({
    required this.leftEyeOpen,
    required this.rightEyeOpen,
    required this.leftEyeBlink,
    required this.rightEyeBlink,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() {
    return {
      'leftEyeOpen': leftEyeOpen,
      'rightEyeOpen': rightEyeOpen,
      'leftEyeBlink': leftEyeBlink,
      'rightEyeBlink': rightEyeBlink,
      'timestamp': timestamp.millisecondsSinceEpoch,
    };
  }

  factory EyeState.fromMap(Map<String, dynamic> map) {
    return EyeState(
      leftEyeOpen: map['leftEyeOpen'] ?? false,
      rightEyeOpen: map['rightEyeOpen'] ?? false,
      leftEyeBlink: map['leftEyeBlink'] ?? false,
      rightEyeBlink: map['rightEyeBlink'] ?? false,
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] ?? 0),
    );
  }
}

class HeadPose {
  final double pitch;
  final double yaw;
  final double roll;
  final DateTime timestamp;

  HeadPose({
    required this.pitch,
    required this.yaw,
    required this.roll,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() {
    return {
      'pitch': pitch,
      'yaw': yaw,
      'roll': roll,
      'timestamp': timestamp.millisecondsSinceEpoch,
    };
  }

  factory HeadPose.fromMap(Map<String, dynamic> map) {
    return HeadPose(
      pitch: map['pitch']?.toDouble() ?? 0.0,
      yaw: map['yaw']?.toDouble() ?? 0.0,
      roll: map['roll']?.toDouble() ?? 0.0,
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] ?? 0),
    );
  }
}

class CalibrationPoint {
  final double x;
  final double y;
  final int order;

  CalibrationPoint({
    required this.x,
    required this.y,
    required this.order,
  });

  Map<String, dynamic> toMap() {
    return {
      'x': x,
      'y': y,
      'order': order,
    };
  }

  factory CalibrationPoint.fromMap(Map<String, dynamic> map) {
    return CalibrationPoint(
      x: map['x']?.toDouble() ?? 0.0,
      y: map['y']?.toDouble() ?? 0.0,
      order: map['order'] ?? 0,
    );
  }
}

class FaceDetection {
  final String faceId;
  final double confidence;
  final Map<String, dynamic> landmarks;
  final DateTime timestamp;

  FaceDetection({
    required this.faceId,
    required this.confidence,
    required this.landmarks,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() {
    return {
      'faceId': faceId,
      'confidence': confidence,
      'landmarks': landmarks,
      'timestamp': timestamp.millisecondsSinceEpoch,
    };
  }

  factory FaceDetection.fromMap(Map<String, dynamic> map) {
    return FaceDetection(
      faceId: map['faceId'] ?? '',
      confidence: map['confidence']?.toDouble() ?? 0.0,
      landmarks: Map<String, dynamic>.from(map['landmarks'] ?? {}),
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] ?? 0),
    );
  }
}

enum EyeTrackingState {
  uninitialized,
  initializing,
  ready,
  tracking,
  calibrating,
  paused,
  error,
}

abstract class EyeTrackingPlatform extends PlatformInterface {
  /// Constructs a EyeTrackingPlatform.
  EyeTrackingPlatform() : super(token: _token);

  static final Object _token = Object();

  static EyeTrackingPlatform _instance = MethodChannelEyeTracking();

  /// The default instance of [EyeTrackingPlatform] to use.
  ///
  /// Defaults to [MethodChannelEyeTracking].
  static EyeTrackingPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [EyeTrackingPlatform] when
  /// they register themselves.
  static set instance(EyeTrackingPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  // Basic platform info
  Future<String?> getPlatformVersion() {
    throw UnimplementedError('getPlatformVersion() has not been implemented.');
  }

  // Initialization and state management
  Future<bool> initialize() {
    throw UnimplementedError('initialize() has not been implemented.');
  }

  Future<bool> requestCameraPermission() {
    throw UnimplementedError(
        'requestCameraPermission() has not been implemented.');
  }

  Future<bool> hasCameraPermission() {
    throw UnimplementedError('hasCameraPermission() has not been implemented.');
  }

  Future<EyeTrackingState> getState() {
    throw UnimplementedError('getState() has not been implemented.');
  }

  // Tracking control
  Future<bool> startTracking() {
    throw UnimplementedError('startTracking() has not been implemented.');
  }

  Future<bool> stopTracking() {
    throw UnimplementedError('stopTracking() has not been implemented.');
  }

  Future<bool> pauseTracking() {
    throw UnimplementedError('pauseTracking() has not been implemented.');
  }

  Future<bool> resumeTracking() {
    throw UnimplementedError('resumeTracking() has not been implemented.');
  }

  // Calibration
  Future<bool> startCalibration(List<CalibrationPoint> points) {
    throw UnimplementedError('startCalibration() has not been implemented.');
  }

  Future<bool> addCalibrationPoint(CalibrationPoint point) {
    throw UnimplementedError('addCalibrationPoint() has not been implemented.');
  }

  Future<bool> finishCalibration() {
    throw UnimplementedError('finishCalibration() has not been implemented.');
  }

  Future<bool> clearCalibration() {
    throw UnimplementedError('clearCalibration() has not been implemented.');
  }

  Future<double> getCalibrationAccuracy() {
    throw UnimplementedError(
        'getCalibrationAccuracy() has not been implemented.');
  }

  // Data streams
  Stream<GazeData> getGazeStream() {
    throw UnimplementedError('getGazeStream() has not been implemented.');
  }

  Stream<EyeState> getEyeStateStream() {
    throw UnimplementedError('getEyeStateStream() has not been implemented.');
  }

  Stream<HeadPose> getHeadPoseStream() {
    throw UnimplementedError('getHeadPoseStream() has not been implemented.');
  }

  Stream<List<FaceDetection>> getFaceDetectionStream() {
    throw UnimplementedError(
        'getFaceDetectionStream() has not been implemented.');
  }

  // Configuration
  Future<bool> setTrackingFrequency(int fps) {
    throw UnimplementedError(
        'setTrackingFrequency() has not been implemented.');
  }

  Future<bool> setAccuracyMode(String mode) {
    throw UnimplementedError('setAccuracyMode() has not been implemented.');
  }

  Future<bool> enableBackgroundTracking(bool enable) {
    throw UnimplementedError(
        'enableBackgroundTracking() has not been implemented.');
  }

  // Utility methods
  Future<Map<String, dynamic>> getCapabilities() {
    throw UnimplementedError('getCapabilities() has not been implemented.');
  }

  Future<bool> dispose() {
    throw UnimplementedError('dispose() has not been implemented.');
  }
}

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'eye_tracking_platform_interface.dart';

/// An implementation of [EyeTrackingPlatform] that uses method channels.
class MethodChannelEyeTracking extends EyeTrackingPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('eye_tracking');

  // Event channels for real-time data streams
  static const EventChannel _gazeEventChannel =
      EventChannel('eye_tracking/gaze');
  static const EventChannel _eyeStateEventChannel =
      EventChannel('eye_tracking/eye_state');
  static const EventChannel _headPoseEventChannel =
      EventChannel('eye_tracking/head_pose');
  static const EventChannel _faceDetectionEventChannel =
      EventChannel('eye_tracking/face_detection');

  // Stream controllers for broadcasting data
  final _gazeController = StreamController<GazeData>.broadcast();
  final _eyeStateController = StreamController<EyeState>.broadcast();
  final _headPoseController = StreamController<HeadPose>.broadcast();
  final _faceDetectionController =
      StreamController<List<FaceDetection>>.broadcast();

  // Stream subscriptions
  StreamSubscription<dynamic>? _gazeSubscription;
  StreamSubscription<dynamic>? _eyeStateSubscription;
  StreamSubscription<dynamic>? _headPoseSubscription;
  StreamSubscription<dynamic>? _faceDetectionSubscription;

  MethodChannelEyeTracking() {
    _setupEventChannels();
  }

  void _setupEventChannels() {
    if (kDebugMode) {
      print('🔧 MethodChannel: Setting up event channels...');
    }

    // Setup gaze data stream
    if (kDebugMode) {
      print('🔧 MethodChannel: Setting up gaze event channel...');
    }
    _gazeSubscription = _gazeEventChannel.receiveBroadcastStream().listen(
      (dynamic data) {
        if (kDebugMode) {
          print('📊 MethodChannel: Received gaze data from iOS: $data');
        }
        if (data is Map<dynamic, dynamic>) {
          final gazeData = GazeData.fromMap(Map<String, dynamic>.from(data));
          _gazeController.add(gazeData);
        }
      },
      onError: (error) {
        if (kDebugMode) {
          print('❌ MethodChannel: Gaze stream error: $error');
        }
      },
    );
    if (kDebugMode) {
      print('✅ MethodChannel: Gaze event channel setup complete');
    }

    // Setup eye state stream
    if (kDebugMode) {
      print('🔧 MethodChannel: Setting up eye state event channel...');
    }
    _eyeStateSubscription =
        _eyeStateEventChannel.receiveBroadcastStream().listen(
      (dynamic data) {
        if (kDebugMode) {
          print('📊 MethodChannel: Received eye state data from iOS: $data');
        }
        if (data is Map<dynamic, dynamic>) {
          final eyeState = EyeState.fromMap(Map<String, dynamic>.from(data));
          _eyeStateController.add(eyeState);
        }
      },
      onError: (error) {
        if (kDebugMode) {
          print('❌ MethodChannel: Eye state stream error: $error');
        }
      },
    );
    if (kDebugMode) {
      print('✅ MethodChannel: Eye state event channel setup complete');
    }

    // Setup head pose stream
    if (kDebugMode) {
      print('🔧 MethodChannel: Setting up head pose event channel...');
    }
    _headPoseSubscription =
        _headPoseEventChannel.receiveBroadcastStream().listen(
      (dynamic data) {
        if (kDebugMode) {
          print('📊 MethodChannel: Received head pose data from iOS: $data');
        }
        if (data is Map<dynamic, dynamic>) {
          final headPose = HeadPose.fromMap(Map<String, dynamic>.from(data));
          _headPoseController.add(headPose);
        }
      },
      onError: (error) {
        if (kDebugMode) {
          print('❌ MethodChannel: Head pose stream error: $error');
        }
      },
    );
    if (kDebugMode) {
      print('✅ MethodChannel: Head pose event channel setup complete');
    }

    // Setup face detection stream
    if (kDebugMode) {
      print('🔧 MethodChannel: Setting up face detection event channel...');
    }
    _faceDetectionSubscription =
        _faceDetectionEventChannel.receiveBroadcastStream().listen(
      (dynamic data) {
        if (kDebugMode) {
          print(
              '📊 MethodChannel: Received face detection data from iOS: $data');
        }
        if (data is List<dynamic>) {
          final faces = data
              .cast<Map<dynamic, dynamic>>()
              .map((map) =>
                  FaceDetection.fromMap(Map<String, dynamic>.from(map)))
              .toList();
          _faceDetectionController.add(faces);
        }
      },
      onError: (error) {
        if (kDebugMode) {
          print('❌ MethodChannel: Face detection stream error: $error');
        }
      },
    );
    if (kDebugMode) {
      print('✅ MethodChannel: Face detection event channel setup complete');
      print('🎉 MethodChannel: All event channels setup completed!');
    }
  }

  @override
  Future<String?> getPlatformVersion() async {
    final version =
        await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }

  @override
  Future<bool> initialize() async {
    if (kDebugMode) {
      print('🔄 MethodChannel: Calling initialize...');
    }
    final result = await methodChannel.invokeMethod<bool>('initialize');
    if (kDebugMode) {
      print('📱 MethodChannel: Initialize result: $result');
    }
    return result ?? false;
  }

  @override
  Future<bool> requestCameraPermission() async {
    final result =
        await methodChannel.invokeMethod<bool>('requestCameraPermission');
    return result ?? false;
  }

  @override
  Future<bool> hasCameraPermission() async {
    final result =
        await methodChannel.invokeMethod<bool>('hasCameraPermission');
    return result ?? false;
  }

  @override
  Future<EyeTrackingState> getState() async {
    final result = await methodChannel.invokeMethod<String>('getState');
    return EyeTrackingState.values.firstWhere(
      (state) => state.name == result,
      orElse: () => EyeTrackingState.uninitialized,
    );
  }

  @override
  Future<bool> startTracking() async {
    if (kDebugMode) {
      print('🔄 MethodChannel: Calling startTracking...');
    }
    final result = await methodChannel.invokeMethod<bool>('startTracking');
    if (kDebugMode) {
      print('📱 MethodChannel: StartTracking result: $result');
    }
    return result ?? false;
  }

  @override
  Future<bool> stopTracking() async {
    final result = await methodChannel.invokeMethod<bool>('stopTracking');
    return result ?? false;
  }

  @override
  Future<bool> pauseTracking() async {
    final result = await methodChannel.invokeMethod<bool>('pauseTracking');
    return result ?? false;
  }

  @override
  Future<bool> resumeTracking() async {
    final result = await methodChannel.invokeMethod<bool>('resumeTracking');
    return result ?? false;
  }

  @override
  Future<bool> startCalibration(List<CalibrationPoint> points) async {
    final pointsData = points.map((point) => point.toMap()).toList();
    final result = await methodChannel.invokeMethod<bool>('startCalibration', {
      'points': pointsData,
    });
    return result ?? false;
  }

  @override
  Future<bool> addCalibrationPoint(CalibrationPoint point) async {
    final result =
        await methodChannel.invokeMethod<bool>('addCalibrationPoint', {
      'point': point.toMap(),
    });
    return result ?? false;
  }

  @override
  Future<bool> finishCalibration() async {
    final result = await methodChannel.invokeMethod<bool>('finishCalibration');
    return result ?? false;
  }

  @override
  Future<bool> clearCalibration() async {
    final result = await methodChannel.invokeMethod<bool>('clearCalibration');
    return result ?? false;
  }

  @override
  Future<double> getCalibrationAccuracy() async {
    final result =
        await methodChannel.invokeMethod<double>('getCalibrationAccuracy');
    return result ?? 0.0;
  }

  @override
  Stream<GazeData> getGazeStream() {
    return _gazeController.stream;
  }

  @override
  Stream<EyeState> getEyeStateStream() {
    return _eyeStateController.stream;
  }

  @override
  Stream<HeadPose> getHeadPoseStream() {
    return _headPoseController.stream;
  }

  @override
  Stream<List<FaceDetection>> getFaceDetectionStream() {
    return _faceDetectionController.stream;
  }

  @override
  Future<bool> setTrackingFrequency(int fps) async {
    final result =
        await methodChannel.invokeMethod<bool>('setTrackingFrequency', fps);
    return result ?? false;
  }

  @override
  Future<bool> setAccuracyMode(String mode) async {
    final result =
        await methodChannel.invokeMethod<bool>('setAccuracyMode', mode);
    return result ?? false;
  }

  @override
  Future<bool> enableBackgroundTracking(bool enable) async {
    final result = await methodChannel.invokeMethod<bool>(
        'enableBackgroundTracking', enable);
    return result ?? false;
  }

  @override
  Future<Map<String, dynamic>> getCapabilities() async {
    final result = await methodChannel
        .invokeMethod<Map<dynamic, dynamic>>('getCapabilities');
    return Map<String, dynamic>.from(result ?? {});
  }

  @override
  Future<bool> dispose() async {
    // Cancel all subscriptions
    await _gazeSubscription?.cancel();
    await _eyeStateSubscription?.cancel();
    await _headPoseSubscription?.cancel();
    await _faceDetectionSubscription?.cancel();

    // Close stream controllers
    await _gazeController.close();
    await _eyeStateController.close();
    await _headPoseController.close();
    await _faceDetectionController.close();

    final result = await methodChannel.invokeMethod<bool>('dispose');
    return result ?? false;
  }
}

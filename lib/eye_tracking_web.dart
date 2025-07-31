import 'dart:async';
import 'dart:html' as html;
import 'dart:js' as js;
import 'dart:js_util';
import 'dart:math' as math;

import 'package:flutter_web_plugins/flutter_web_plugins.dart';

import 'eye_tracking_platform_interface.dart';

/// Web implementation of [EyeTrackingPlatform]
class EyeTrackingWeb extends EyeTrackingPlatform {
  static void registerWith(Registrar registrar) {
    EyeTrackingPlatform.instance = EyeTrackingWeb();
  }

  // Stream controllers for real-time data
  final _gazeController = StreamController<GazeData>.broadcast();
  final _eyeStateController = StreamController<EyeState>.broadcast();
  final _headPoseController = StreamController<HeadPose>.broadcast();
  final _faceDetectionController =
      StreamController<List<FaceDetection>>.broadcast();

  // State management
  EyeTrackingState _currentState = EyeTrackingState.uninitialized;
  bool _isInitialized = false;
  bool _hasPermission = false;
  Timer? _trackingTimer;

  // Calibration data
  List<CalibrationPoint> _calibrationPoints = [];
  bool _isCalibrating = false;

  // WebGazer state
  bool _webGazerLoaded = false;
  bool _webGazerStarted = false;

  @override
  Future<String?> getPlatformVersion() async {
    return 'Web ${html.window.navigator.userAgent}';
  }

  @override
  Future<bool> initialize() async {
    if (_isInitialized) return true;

    try {
      _currentState = EyeTrackingState.initializing;

      // Load WebGazer.js
      await _loadWebGazer();

      _isInitialized = true;
      _currentState = EyeTrackingState.ready;

      return true;
    } catch (e) {
      print('Error initializing eye tracking: $e');
      _currentState = EyeTrackingState.error;
      return false;
    }
  }

  Future<void> _loadWebGazer() async {
    // Check if WebGazer is already loaded
    if (_webGazerLoaded && js.context.hasProperty('webgazer')) {
      return;
    }

    final completer = Completer<void>();

    final script = html.ScriptElement()
      ..src = 'https://webgazer.cs.brown.edu/webgazer.js'
      ..onLoad.listen((_) async {
        print('WebGazer.js loaded successfully');

        // Wait a bit for WebGazer to be fully available
        await Future.delayed(Duration(milliseconds: 1000));

        if (js.context.hasProperty('webgazer')) {
          _webGazerLoaded = true;
          print('WebGazer object is available');

          // Debug: Check what methods are available
          _debugWebGazerAPI();

          completer.complete();
        } else {
          completer.completeError('WebGazer object not found after loading');
        }
      })
      ..onError
          .listen((_) => completer.completeError('Failed to load WebGazer.js'));

    html.document.head!.append(script);
    await completer.future;
  }

  void _debugWebGazerAPI() {
    try {
      final webgazer = js.context['webgazer'];
      print('WebGazer object type: ${webgazer.runtimeType}');

      // Try to access some expected methods
      final methods = [
        'setGazeListener',
        'begin',
        'end',
        'pause',
        'resume',
        'setRegression',
        'setTracker'
      ];
      for (final method in methods) {
        final hasMethod = js.context['webgazer'].hasProperty(method);
        print('WebGazer.$method exists: $hasMethod');
      }
    } catch (e) {
      print('Error debugging WebGazer API: $e');
    }
  }

  @override
  Future<bool> requestCameraPermission() async {
    try {
      final mediaStream =
          await html.window.navigator.mediaDevices!.getUserMedia({
        'video': {'width': 640, 'height': 480}
      });

      _hasPermission = true;
      return true;
    } catch (e) {
      print('Camera permission denied: $e');
      _hasPermission = false;
      return false;
    }
  }

  @override
  Future<bool> hasCameraPermission() async {
    return _hasPermission;
  }

  @override
  Future<EyeTrackingState> getState() async {
    return _currentState;
  }

  @override
  Future<bool> startTracking() async {
    if (!_isInitialized || !_hasPermission || !_webGazerLoaded) {
      print(
          'Cannot start tracking: initialized=$_isInitialized, permission=$_hasPermission, webgazer=$_webGazerLoaded');
      return false;
    }

    try {
      _currentState = EyeTrackingState.tracking;

      await _initializeWebGazer();

      return true;
    } catch (e) {
      print('Error starting tracking: $e');
      _currentState = EyeTrackingState.error;
      return false;
    }
  }

  Future<void> _initializeWebGazer() async {
    if (_webGazerStarted) {
      // Just resume if already started
      try {
        js.context['webgazer'].callMethod('resume');
      } catch (e) {
        print('Error resuming WebGazer: $e');
      }
      return;
    }

    try {
      final webgazer = js.context['webgazer'];

      // Set up gaze listener using direct property access
      webgazer['setGazeListener'] = allowInterop((data, timestamp) {
        if (data != null && _currentState == EyeTrackingState.tracking) {
          _handleGazeData(data, timestamp);
        }
      });

      // Alternative: Try calling setGazeListener directly
      try {
        webgazer.callMethod('setGazeListener', [
          allowInterop((data, timestamp) {
            if (data != null && _currentState == EyeTrackingState.tracking) {
              _handleGazeData(data, timestamp);
            }
          })
        ]);
        print('Successfully set gaze listener using callMethod');
      } catch (e) {
        print('Failed to set gaze listener using callMethod: $e');

        // Try alternative approach
        try {
          js.context.callMethod('eval', [
            'webgazer.setGazeListener(function(data, timestamp) { window._gazeCallback(data, timestamp); })'
          ]);

          // Set up global callback
          js.context['_gazeCallback'] = allowInterop((data, timestamp) {
            if (data != null && _currentState == EyeTrackingState.tracking) {
              _handleGazeData(data, timestamp);
            }
          });
          print('Successfully set gaze listener using eval approach');
        } catch (e2) {
          print('Failed to set gaze listener using eval: $e2');
        }
      }

      // Configure WebGazer settings
      try {
        webgazer.callMethod('setRegression', ['ridge']);
        webgazer.callMethod('setTracker', ['clmtrackr']);
        webgazer.callMethod('showPredictionPoints', [false]);
        print('WebGazer configuration set successfully');
      } catch (e) {
        print('Error configuring WebGazer: $e');
        // Try eval approach for configuration
        try {
          js.context.callMethod('eval', [
            'webgazer.setRegression("ridge").setTracker("clmtrackr").showPredictionPoints(false)'
          ]);
          print('WebGazer configuration set using eval');
        } catch (e2) {
          print('Failed to configure WebGazer using eval: $e2');
        }
      }

      // Start WebGazer
      try {
        await promiseToFuture(webgazer.callMethod('begin'));
        print('WebGazer started using callMethod');
      } catch (e) {
        print('Failed to start WebGazer using callMethod: $e');
        // Try eval approach
        try {
          js.context.callMethod('eval', ['webgazer.begin()']);
          await Future.delayed(
              Duration(milliseconds: 1000)); // Give it time to start
          print('WebGazer started using eval');
        } catch (e2) {
          print('Failed to start WebGazer using eval: $e2');
          throw e2;
        }
      }

      _webGazerStarted = true;
      print('WebGazer initialization completed successfully');
    } catch (e) {
      print('Error initializing WebGazer: $e');
      throw e;
    }
  }

  void _handleGazeData(dynamic data, num timestamp) {
    try {
      // Handle different data formats that WebGazer might return
      double x = 0.0;
      double y = 0.0;

      if (data is Map) {
        x = (data['x'] ?? 0.0).toDouble();
        y = (data['y'] ?? 0.0).toDouble();
      } else if (data != null) {
        // Try accessing as JS object
        try {
          x = (getProperty(data, 'x') ?? 0.0).toDouble();
          y = (getProperty(data, 'y') ?? 0.0).toDouble();
        } catch (e) {
          print('Error parsing gaze data: $e');
          return;
        }
      }

      final gazeData = GazeData(
        x: x,
        y: y,
        confidence: 0.8,
        timestamp: DateTime.fromMillisecondsSinceEpoch(timestamp.toInt()),
      );

      _gazeController.add(gazeData);
    } catch (e) {
      print('Error handling gaze data: $e');
    }
  }

  @override
  Future<bool> stopTracking() async {
    try {
      _currentState = EyeTrackingState.ready;

      if (_webGazerStarted && js.context.hasProperty('webgazer')) {
        try {
          js.context['webgazer'].callMethod('pause');
        } catch (e) {
          js.context.callMethod('eval', ['webgazer.pause()']);
        }
      }

      return true;
    } catch (e) {
      print('Error stopping tracking: $e');
      return false;
    }
  }

  @override
  Future<bool> pauseTracking() async {
    if (_currentState != EyeTrackingState.tracking) return false;

    try {
      _currentState = EyeTrackingState.paused;
      if (_webGazerStarted && js.context.hasProperty('webgazer')) {
        try {
          js.context['webgazer'].callMethod('pause');
        } catch (e) {
          js.context.callMethod('eval', ['webgazer.pause()']);
        }
      }
      return true;
    } catch (e) {
      print('Error pausing tracking: $e');
      return false;
    }
  }

  @override
  Future<bool> resumeTracking() async {
    if (_currentState != EyeTrackingState.paused) return false;

    try {
      _currentState = EyeTrackingState.tracking;
      if (_webGazerStarted && js.context.hasProperty('webgazer')) {
        try {
          js.context['webgazer'].callMethod('resume');
        } catch (e) {
          js.context.callMethod('eval', ['webgazer.resume()']);
        }
      }
      return true;
    } catch (e) {
      print('Error resuming tracking: $e');
      return false;
    }
  }

  @override
  Future<bool> startCalibration(List<CalibrationPoint> points) async {
    if (_currentState != EyeTrackingState.ready &&
        _currentState != EyeTrackingState.tracking) {
      return false;
    }

    try {
      _calibrationPoints = List.from(points);
      _isCalibrating = true;
      _currentState = EyeTrackingState.calibrating;

      // Clear existing calibration if WebGazer is loaded
      if (_webGazerStarted && js.context.hasProperty('webgazer')) {
        try {
          js.context['webgazer'].callMethod('clearData');
        } catch (e) {
          js.context.callMethod('eval', ['webgazer.clearData()']);
        }
      }

      return true;
    } catch (e) {
      print('Error starting calibration: $e');
      return false;
    }
  }

  @override
  Future<bool> addCalibrationPoint(CalibrationPoint point) async {
    if (!_isCalibrating) return false;

    try {
      if (_webGazerStarted && js.context.hasProperty('webgazer')) {
        // Add calibration point to WebGazer multiple times for better accuracy
        for (int i = 0; i < 5; i++) {
          try {
            js.context['webgazer']
                .callMethod('recordScreenPosition', [point.x, point.y]);
          } catch (e) {
            js.context.callMethod('eval',
                ['webgazer.recordScreenPosition(${point.x}, ${point.y})']);
          }
          await Future.delayed(Duration(milliseconds: 100));
        }
      }
      return true;
    } catch (e) {
      print('Error adding calibration point: $e');
      return false;
    }
  }

  @override
  Future<bool> finishCalibration() async {
    if (!_isCalibrating) return false;

    try {
      _isCalibrating = false;
      _currentState = EyeTrackingState.ready;
      return true;
    } catch (e) {
      print('Error finishing calibration: $e');
      return false;
    }
  }

  @override
  Future<bool> clearCalibration() async {
    try {
      if (_webGazerStarted && js.context.hasProperty('webgazer')) {
        try {
          js.context['webgazer'].callMethod('clearData');
        } catch (e) {
          js.context.callMethod('eval', ['webgazer.clearData()']);
        }
      }
      _calibrationPoints.clear();
      return true;
    } catch (e) {
      print('Error clearing calibration: $e');
      return false;
    }
  }

  @override
  Future<double> getCalibrationAccuracy() async {
    return _calibrationPoints.length >= 5 ? 0.8 : 0.5;
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
    return true; // WebGazer handles this internally
  }

  @override
  Future<bool> setAccuracyMode(String mode) async {
    if (!_webGazerLoaded || !js.context.hasProperty('webgazer')) {
      return false;
    }

    try {
      final regressionMode = switch (mode) {
        'high' => 'ridge',
        'medium' => 'weightedRidge',
        'fast' => 'linear',
        _ => 'ridge'
      };

      try {
        js.context['webgazer'].callMethod('setRegression', [regressionMode]);
      } catch (e) {
        js.context
            .callMethod('eval', ['webgazer.setRegression("$regressionMode")']);
      }
      return true;
    } catch (e) {
      print('Error setting accuracy mode: $e');
      return false;
    }
  }

  @override
  Future<bool> enableBackgroundTracking(bool enable) async {
    return true; // Limited by browser policies
  }

  @override
  Future<Map<String, dynamic>> getCapabilities() async {
    return {
      'platform': 'web',
      'gaze_tracking': _webGazerLoaded,
      'eye_state_detection': false, // To be implemented with MediaPipe
      'head_pose_estimation': false, // To be implemented with MediaPipe
      'multiple_faces': false, // To be implemented with MediaPipe
      'calibration': _webGazerLoaded,
      'background_tracking': false,
      'max_faces': 1,
      'accuracy_modes': ['high', 'medium', 'fast'],
      'webgazer_loaded': _webGazerLoaded,
      'webgazer_started': _webGazerStarted,
    };
  }

  @override
  Future<bool> dispose() async {
    try {
      _trackingTimer?.cancel();

      await _gazeController.close();
      await _eyeStateController.close();
      await _headPoseController.close();
      await _faceDetectionController.close();

      // Stop WebGazer
      if (_webGazerStarted && js.context.hasProperty('webgazer')) {
        try {
          js.context['webgazer'].callMethod('end');
        } catch (e) {
          js.context.callMethod('eval', ['webgazer.end()']);
        }
      }

      return true;
    } catch (e) {
      print('Error disposing: $e');
      return false;
    }
  }
}

import 'dart:async';
import 'dart:html' as html;
import 'dart:js' as js;
import 'dart:js_util';

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

  // Throttling for gaze data
  DateTime? _lastGazeUpdate;
  static const Duration _gazeThrottleInterval =
      Duration(milliseconds: 33); // ~30 FPS

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
        // Wait a bit for WebGazer to be fully available
        await Future.delayed(const Duration(milliseconds: 1000));

        if (js.context.hasProperty('webgazer')) {
          _webGazerLoaded = true;
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

  @override
  Future<bool> requestCameraPermission() async {
    try {
      await html.window.navigator.mediaDevices!.getUserMedia({
        'video': {'width': 640, 'height': 480}
      });

      _hasPermission = true;
      return true;
    } catch (e) {
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
      return false;
    }

    try {
      _currentState = EyeTrackingState.tracking;
      await _initializeWebGazer();
      return true;
    } catch (e) {
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
        // Silently handle resume errors
      }
      return;
    }

    try {
      // Set up global callback for gaze data
      js.context['_gazeCallback'] = allowInterop((data, timestamp) {
        if (data != null && _currentState == EyeTrackingState.tracking) {
          _handleGazeData(data, timestamp);
        }
      });

      // Set up the gaze listener
      try {
        js.context.callMethod('eval', [
          'webgazer.setGazeListener(function(data, timestamp) {   if (window._gazeCallback) {     window._gazeCallback(data, timestamp);   } });'
        ]);
      } catch (e) {
        // Silently handle gaze listener setup errors
      }

      // Configure WebGazer settings
      try {
        js.context.callMethod('eval', [
          'webgazer.setRegression("ridge").setTracker("TFFacemesh").showPredictionPoints(false);'
        ]);
      } catch (e) {
        // Silently handle configuration errors
      }

      // Start WebGazer and wait for it to be ready
      try {
        js.context.callMethod('eval', ['webgazer.begin();']);

        // Wait for WebGazer to initialize
        await Future.delayed(const Duration(milliseconds: 3000));

        _webGazerStarted = true;

        // Auto-calibration: Add some default calibration points to help WebGazer
        // start producing meaningful gaze predictions
        _performAutoCalibration();
      } catch (e) {
        rethrow;
      }
    } catch (e) {
      rethrow;
    }
  }

  void _handleGazeData(dynamic data, num timestamp) {
    try {
      // Throttle updates to prevent UI freezing
      final now = DateTime.now();
      if (_lastGazeUpdate != null &&
          now.difference(_lastGazeUpdate!) < _gazeThrottleInterval) {
        return; // Skip this update to maintain stable frame rate
      }
      _lastGazeUpdate = now;

      if (data == null) {
        return;
      }

      double x = 0.0;
      double y = 0.0;

      // Try multiple approaches to extract coordinates
      bool coordinatesFound = false;

      // Approach 1: Direct property access if it's a Map
      if (data is Map) {
        final mapX = data['x'];
        final mapY = data['y'];
        if (mapX != null && mapY != null) {
          x = (mapX is num
              ? mapX.toDouble()
              : double.tryParse(mapX.toString()) ?? 0.0);
          y = (mapY is num
              ? mapY.toDouble()
              : double.tryParse(mapY.toString()) ?? 0.0);
          coordinatesFound = true;
        }
      }

      // Approach 2: JavaScript object property access using dart:js_util
      if (!coordinatesFound) {
        try {
          final jsX = getProperty(data, 'x');
          final jsY = getProperty(data, 'y');

          if (jsX != null && jsY != null) {
            x = (jsX is num
                ? jsX.toDouble()
                : double.tryParse(jsX.toString()) ?? 0.0);
            y = (jsY is num
                ? jsY.toDouble()
                : double.tryParse(jsY.toString()) ?? 0.0);
            coordinatesFound = true;
          }
        } catch (e) {
          // Silently handle getProperty errors
        }
      }

      // Approach 3: Try accessing as JsObject directly
      if (!coordinatesFound &&
          data.runtimeType.toString().contains('JsObject')) {
        try {
          // For JsObject, try to access properties directly through JavaScript
          js.context['_tempGazeData'] = data;

          // Simple extraction without complex eval
          final jsX = js.context.callMethod('eval', ['window._tempGazeData.x']);
          final jsY = js.context.callMethod('eval', ['window._tempGazeData.y']);

          if (jsX != null && jsY != null) {
            x = (jsX is num
                ? jsX.toDouble()
                : double.tryParse(jsX.toString()) ?? 0.0);
            y = (jsY is num
                ? jsY.toDouble()
                : double.tryParse(jsY.toString()) ?? 0.0);

            if (x > 0 && y > 0) {
              coordinatesFound = true;
            }
          }
        } catch (e) {
          // Silently handle JS eval errors
        }
      }

      // If still no coordinates, skip this update
      if (!coordinatesFound || (x == 0.0 && y == 0.0)) {
        return;
      }

      // Validate coordinates
      if (!x.isFinite || !y.isFinite) {
        return;
      }

      // Create and emit gaze data
      final gazeData = GazeData(
        x: x,
        y: y,
        confidence: coordinatesFound ? 0.8 : 0.3,
        timestamp: DateTime.fromMillisecondsSinceEpoch(timestamp.toInt()),
      );

      // Emit to stream with error handling
      if (!_gazeController.isClosed) {
        try {
          _gazeController.add(gazeData);
        } catch (e) {
          // Silently handle stream errors
        }
      }
    } catch (e) {
      // Silently handle processing errors
    }
  }

  Future<void> _performAutoCalibration() async {
    // Add some basic calibration points to help WebGazer learn
    final screenWidth = html.window.screen?.width?.toDouble() ?? 1920.0;
    final screenHeight = html.window.screen?.height?.toDouble() ?? 1080.0;

    // Use center and corner points for quick calibration
    final autoCalibrationPoints = [
      CalibrationPoint(
          x: screenWidth * 0.5, y: screenHeight * 0.5, order: 0), // Center
      CalibrationPoint(
          x: screenWidth * 0.2,
          y: screenHeight * 0.2,
          order: 1), // Top-left area
      CalibrationPoint(
          x: screenWidth * 0.8,
          y: screenHeight * 0.2,
          order: 2), // Top-right area
      CalibrationPoint(
          x: screenWidth * 0.2,
          y: screenHeight * 0.8,
          order: 3), // Bottom-left area
      CalibrationPoint(
          x: screenWidth * 0.8,
          y: screenHeight * 0.8,
          order: 4), // Bottom-right area
    ];

    try {
      for (int i = 0; i < autoCalibrationPoints.length; i++) {
        final point = autoCalibrationPoints[i];

        // Add multiple samples for each point
        for (int sample = 0; sample < 3; sample++) {
          try {
            js.context.callMethod('eval',
                ['webgazer.recordScreenPosition(${point.x}, ${point.y});']);
          } catch (e) {
            // Silently handle calibration point errors
          }
          await Future.delayed(const Duration(milliseconds: 200));
        }
      }

      // Give WebGazer a moment to process the calibration data
      await Future.delayed(const Duration(milliseconds: 1000));
    } catch (e) {
      // Silently handle auto-calibration errors
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
          await Future.delayed(const Duration(milliseconds: 100));
        }
      }
      return true;
    } catch (e) {
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
      return false;
    }
  }
}

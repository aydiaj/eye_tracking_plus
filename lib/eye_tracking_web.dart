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

  // Throttling for gaze data
  DateTime? _lastGazeUpdate;
  final Duration _gazeThrottleInterval = Duration(milliseconds: 33); // ~30 FPS

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

      // Set up global callback first
      js.context['_gazeCallback'] = allowInterop((data, timestamp) {
        print('🎯 GAZE CALLBACK FIRED! Data: $data, Timestamp: $timestamp');
        if (data != null && _currentState == EyeTrackingState.tracking) {
          _handleGazeData(data, timestamp);
        }
      });

      // Test if callback is set up correctly
      print('Global callback set up: ${js.context['_gazeCallback']}');

      // Use multiple approaches to set up the gaze listener
      try {
        // Approach 1: Direct eval with more debugging
        js.context.callMethod('eval', [
          'console.log("🔧 Setting up WebGazer gaze listener..."); ' +
              'webgazer.setGazeListener(function(data, timestamp) { ' +
              '  console.log("🎯 WebGazer callback fired! Data:", data, "Timestamp:", timestamp); ' +
              '  if (window._gazeCallback) { ' +
              '    window._gazeCallback(data, timestamp); ' +
              '  } else { ' +
              '    console.error("❌ _gazeCallback not found!"); ' +
              '  } ' +
              '}); ' +
              'console.log("✅ Gaze listener setup complete");'
        ]);
        print('✅ Gaze listener set using eval approach');
      } catch (e) {
        print('❌ Failed to set gaze listener: $e');
      }

      // Configure WebGazer settings with correct tracker name
      try {
        js.context.callMethod('eval', [
          'webgazer.setRegression("ridge").setTracker("TFFacemesh").showPredictionPoints(false);'
        ]);
        print(
            '✅ WebGazer configured: ridge regression, TFFacemesh tracker, no prediction points');
      } catch (e) {
        print('❌ Error configuring WebGazer: $e');
      }

      // Start WebGazer and wait for it to be ready
      try {
        js.context.callMethod('eval', ['webgazer.begin();']);
        print('🚀 WebGazer.begin() called');

        // Wait longer for WebGazer to fully initialize
        await Future.delayed(Duration(milliseconds: 3000));

        // Test if WebGazer is actually working
        try {
          final isReady = js.context.callMethod(
              'eval', ['typeof webgazer.getCurrentPrediction === "function"']);
          print('WebGazer getCurrentPrediction available: $isReady');

          // Force a prediction test and start a monitoring loop
          js.context.callMethod('eval', [
            'console.log("🧪 Testing WebGazer prediction..."); ' +
                'var pred = webgazer.getCurrentPrediction(); ' +
                'console.log("Current prediction:", pred); ' +
                '' +
                'console.log("🔄 Starting WebGazer monitoring..."); ' +
                'var checkCount = 0; ' +
                'function checkWebGazer() { ' +
                '  checkCount++; ' +
                '  var prediction = webgazer.getCurrentPrediction(); ' +
                '  var regression = webgazer.getRegression(); ' +
                '  console.log("📊 Check #" + checkCount + ":"); ' +
                '  console.log("  Prediction:", prediction); ' +
                '  console.log("  Regression loaded:", !!regression); ' +
                '  if (prediction && prediction.x !== undefined && prediction.y !== undefined) { ' +
                '    console.log("✅ WebGazer is producing valid predictions!"); ' +
                '  } else { ' +
                '    console.log("⚠️  WebGazer not producing predictions yet..."); ' +
                '  } ' +
                '  if (checkCount < 10) { ' +
                '    setTimeout(checkWebGazer, 2000); ' +
                '  } ' +
                '} ' +
                'setTimeout(checkWebGazer, 1000);'
          ]);

          // Check if the regression model is loaded
          js.context.callMethod('eval', [
            'console.log("WebGazer ready state:", webgazer.getRegression() ? "regression loaded" : "no regression");'
          ]);
        } catch (e) {
          print('Error testing WebGazer state: $e');
        }

        _webGazerStarted = true;
        print('✅ WebGazer initialization completed successfully');

        // Auto-calibration: Add some default calibration points to help WebGazer
        // start producing meaningful gaze predictions
        _performAutoCalibration();
      } catch (e) {
        print('❌ Error starting WebGazer: $e');
        throw e;
      }
    } catch (e) {
      print('❌ Error initializing WebGazer: $e');
      throw e;
    }
  }

  void _handleGazeData(dynamic data, num timestamp) {
    try {
      // Throttle updates to prevent UI freezing
      final now = DateTime.now();
      if (_lastGazeUpdate != null &&
          now.difference(_lastGazeUpdate!) < Duration(milliseconds: 100)) {
        return; // Skip this update - only allow 10 FPS
      }
      _lastGazeUpdate = now;

      if (data == null) {
        return;
      }

      // Log data type for debugging (but don't stop execution)
      if (timestamp.toInt() % 120 == 0) {
        // Log every 2 seconds or so
        print('📊 Processing gaze data: ${data.runtimeType} - $data');
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
          if (timestamp % 60 == 0) print('✅ Parsed as Dart Map: x=$x, y=$y');
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
            if (timestamp % 60 == 0)
              print('✅ Parsed using getProperty: x=$x, y=$y');
          }
        } catch (e) {
          if (timestamp % 60 == 0) print('❌ getProperty failed: $e');
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
              if (timestamp % 30 == 0)
                print('✅ Parsed using simple JS eval: x=$x, y=$y');
            }
          }
        } catch (e) {
          if (timestamp % 30 == 0) print('❌ Simple JS eval failed: $e');
        }
      }

      // If still no coordinates, check if WebGazer needs calibration
      if (!coordinatesFound || (x == 0.0 && y == 0.0)) {
        if (timestamp % 300 == 0) {
          // Every 5 seconds or so
          print(
              '⚠️  No valid gaze coordinates found. WebGazer might need calibration.');
          print(
              '   Consider calling calibration or check if face is properly detected.');

          // Check WebGazer's internal state
          try {
            js.context.callMethod('eval', [
              'console.log("📊 WebGazer status:"); ' +
                  'console.log("  isReady:", typeof webgazer.isReady === "function" ? webgazer.isReady() : "unknown"); ' +
                  'console.log("  regression model:", webgazer.getRegression() ? "loaded" : "not loaded"); ' +
                  'console.log("  current prediction:", webgazer.getCurrentPrediction());'
            ]);
          } catch (e) {
            print('Error checking WebGazer status: $e');
          }
        }
        return;
      }

      // Validate coordinates
      if (!x.isFinite || !y.isFinite) {
        if (timestamp % 60 == 0) print('❌ Invalid coordinates: x=$x, y=$y');
        return;
      }

      // Create and emit gaze data
      final gazeData = GazeData(
        x: x,
        y: y,
        confidence: coordinatesFound ? 0.8 : 0.3,
        timestamp: DateTime.fromMillisecondsSinceEpoch(timestamp.toInt()),
      );

      if (timestamp % 60 == 0) {
        print(
            '📍 Final gaze data: x=${gazeData.x}, y=${gazeData.y}, confidence=${gazeData.confidence}');
      }

      // Emit to stream with error handling
      if (!_gazeController.isClosed) {
        try {
          _gazeController.add(gazeData);
        } catch (e) {
          print('Error adding to gaze stream: $e');
        }
      }
    } catch (e) {
      print('❌ Error in _handleGazeData: $e');
    }
  }

  Future<void> _performAutoCalibration() async {
    print('🎯 Starting auto-calibration to help WebGazer...');

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
        print(
            '  📍 Auto-calibrating point ${i + 1}/${autoCalibrationPoints.length}: (${point.x.toInt()}, ${point.y.toInt()})');

        // Add multiple samples for each point
        for (int sample = 0; sample < 3; sample++) {
          try {
            js.context.callMethod('eval',
                ['webgazer.recordScreenPosition(${point.x}, ${point.y});']);
          } catch (e) {
            print('    ❌ Error recording calibration point: $e');
          }
          await Future.delayed(Duration(milliseconds: 200));
        }
      }

      print('✅ Auto-calibration completed');

      // Give WebGazer a moment to process the calibration data
      await Future.delayed(Duration(milliseconds: 1000));

      // Test if calibration helped
      try {
        js.context.callMethod('eval', [
          'console.log("🧪 Testing WebGazer after auto-calibration:"); ' +
              'var prediction = webgazer.getCurrentPrediction(); ' +
              'console.log("  Current prediction:", prediction); ' +
              'console.log("  Regression model loaded:", !!webgazer.getRegression());'
        ]);
      } catch (e) {
        print('Error testing post-calibration: $e');
      }
    } catch (e) {
      print('❌ Error during auto-calibration: $e');
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

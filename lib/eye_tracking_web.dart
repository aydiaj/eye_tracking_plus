import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math' as math;

import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:web/web.dart';

import 'eye_tracking_platform_interface.dart';

/// Web implementation of [EyeTrackingPlatform]
class EyeTrackingWeb extends EyeTrackingPlatform {
  static void registerWith(Registrar registrar) {
    EyeTrackingPlatform.instance = EyeTrackingWeb();
  }

  // Stream controllers for real-time data
  final _gazeController = StreamController<GazeData>.broadcast();
  final _stateController =
      StreamController<EyeTrackingState>.broadcast();
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

  // Calibration accuracy accumulation
  int _calibTrainSamples = 0;
  int _calibEvalSamples = 0;
  double _sumErrPx = 0.0;
  double _lastAccuracy01 = 0.0; // cache last computed accuracy

  // Confidence ingredients
  double _emaConf = 0.75;
  int _lastEpochMs = 0;

  bool _docHasFocus = true;
  bool _docVisible = true;

  // WebGazer state
  bool _webGazerLoaded = false;
  bool _webGazerStarted = false;

  // Throttling for gaze data
  DateTime? _lastGazeUpdate;
  static const Duration _gazeThrottleInterval = Duration(
    milliseconds: 33,
  ); // ~30 FPS

  @override
  Future<String?> getPlatformVersion() async {
    return 'Web ${window.navigator.userAgent}';
  }

  @override
  Future<bool> initialize() async {
    if (_isInitialized) return true;

    try {
      _emitNewState(EyeTrackingState.initializing);

      // Load WebGazer.js
      await _loadWebGazer();

      _isInitialized = true;
      initAttentionGuards();
      _emitNewState(EyeTrackingState.ready);

      return true;
    } catch (e) {
      _emitNewState(EyeTrackingState.error);
      return false;
    }
  }

  void initAttentionGuards() {
    _docHasFocus = true;
    _docVisible = (document.visibilityState == 'visible');

    document.addEventListener(
      'visibilitychange',
      ((Event _) =>
          _docVisible = (document.visibilityState == 'visible')).toJS,
    );

    window.addEventListener(
      'focus',
      ((Event _) => _docHasFocus = true).toJS,
    );
    window.addEventListener(
      'blur',
      ((Event _) => _docHasFocus = false).toJS,
    );

    // Optional pointer hints (nice-to-have; not required)
    document.addEventListener(
      'pointerover',
      ((Event _) => _docHasFocus = true).toJS,
    );
    document.addEventListener(
      'pointerleave',
      ((Event _) => _docHasFocus = false).toJS,
    );

    document.addEventListener(
      'mouseleave',
      ((Event _) => _docHasFocus = false).toJS,
    );

    document.addEventListener(
      'mouseenter',
      ((Event _) => _docHasFocus = true).toJS,
    );
  }

  Future<void> _loadWebGazer() async {
    // Check if WebGazer is already loaded
    if (_webGazerLoaded && _hasWebGazerProperty()) {
      return;
    }

    final completer = Completer<void>();

    final script = HTMLScriptElement()
      ..src = 'https://webgazer.cs.brown.edu/webgazer.js';

    script.addEventListener(
      'load',
      (Event event) {
        // Handle async work without making the event listener async
        Future.delayed(const Duration(milliseconds: 1000)).then((_) {
          if (_hasWebGazerProperty()) {
            _webGazerLoaded = true;
            completer.complete();
          } else {
            completer.completeError(
              'WebGazer object not found after loading',
            );
          }
        });
      }.toJS,
    );

    script.addEventListener(
      'error',
      (Event event) {
        completer.completeError('Failed to load WebGazer.js');
      }.toJS,
    );

    document.head!.appendChild(script);
    await completer.future;
  }

  bool _hasWebGazerProperty() {
    return (window as JSObject).has('webgazer');
  }

  @override
  Future<bool> requestCameraPermission() async {
    try {
      final constraints = {
        'video': {'width': 640, 'height': 480},
      }.jsify() as MediaStreamConstraints;

      await window.navigator.mediaDevices
          .getUserMedia(constraints)
          .toDart;

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
      _emitNewState(EyeTrackingState.warmingUp);
      await _initializeWebGazer();
      return true;
    } catch (e) {
      _emitNewState(EyeTrackingState.error);
      return false;
    }
  }

  Future<void> _initializeWebGazer() async {
    if (_webGazerStarted) {
      // Just resume if already started
      try {
        _callWebGazerMethod('resume');
      } catch (e) {
        // Silently handle resume errors
      }
      return;
    }

    try {
      // Set up global callback for gaze data
      (window as JSObject).setProperty(
        '_gazeCallback'.toJS,
        ((JSAny? data, JSNumber timestamp) {
          if (data != null &&
              (_currentState == EyeTrackingState.warmingUp ||
                  _currentState == EyeTrackingState.tracking ||
                  _currentState == EyeTrackingState.calibrating)) {
            _handleGazeData(data, timestamp.toDartDouble);
          }
        }).toJS,
      );

      // Set up the gaze listener
      try {
        _evalJS(
          'webgazer.setGazeListener(function(data, timestamp) {   if (window._gazeCallback) {     window._gazeCallback(data, timestamp);   } });',
        );
      } catch (e) {
        // Silently handle gaze listener setup errors
      }

      // Configure WebGazer settings
      try {
        _evalJS(
          'webgazer.setRegression("ridge").setTracker("TFFacemesh").showPredictionPoints(false);',
        );
      } catch (e) {
        // Silently handle configuration errors
      }

      // Start WebGazer and wait for it to be ready
      try {
        _evalJS('webgazer.begin();');

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

  void _evalJS(String code) {
    (window as JSObject).callMethodVarArgs('eval'.toJS, [code.toJS]);
  }

  void _callWebGazerMethod(String method, [List<JSAny>? args]) {
    final webgazer =
        (window as JSObject).getProperty('webgazer'.toJS) as JSObject;
    if (args != null) {
      webgazer.callMethodVarArgs(method.toJS, args);
    } else {
      webgazer.callMethodVarArgs(method.toJS, []);
    }
  }

  void _handleGazeData(JSAny? data, num timestamp) {
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
      bool coordinatesFound = false;

      // Try to extract coordinates from JSObject
      try {
        final jsObj = data as JSObject;
        final jsX = jsObj.getProperty('x'.toJS);
        final jsY = jsObj.getProperty('y'.toJS);

        if (jsX != null && jsY != null) {
          x = (jsX as JSNumber).toDartDouble;
          y = (jsY as JSNumber).toDartDouble;
          coordinatesFound = true;
        }
      } catch (e) {
        // Fallback: try accessing through JavaScript evaluation
        try {
          (window as JSObject).setProperty(
            '_tempGazeData'.toJS,
            data,
          );
          final jsX = _evalJSAndGetResult('window._tempGazeData.x');
          final jsY = _evalJSAndGetResult('window._tempGazeData.y');

          if (jsX != null && jsY != null) {
            x = (jsX as JSNumber).toDartDouble;
            y = (jsY as JSNumber).toDartDouble;
            if (x > 0 && y > 0) {
              coordinatesFound = true;
            }
          }
        } catch (e) {
          // Silently handle JS eval errors
        }
      }

      if (_currentState == EyeTrackingState.warmingUp &&
          coordinatesFound) {
        _emitNewState(EyeTrackingState.tracking);
      }

      // If still no coordinates, skip this update
      if (!coordinatesFound || (x == 0.0 && y == 0.0)) {
        return;
      }

      // Validate coordinates
      if (!x.isFinite || !y.isFinite) {
        return;
      }

      final sampleEpochMs = _toEpochMs(timestamp);

      // conf computation here
      final conf = updateGazeConfidence(
        x: x,
        y: y,
        timestamp: DateTime.fromMillisecondsSinceEpoch(sampleEpochMs),
      );

      final gazeData = GazeData(
        x: x,
        y: y,
        confidence: conf,
        timestamp: DateTime.fromMillisecondsSinceEpoch(
          sampleEpochMs, //timestamp.toInt(),
        ),
      );

      // Create and emit gaze data
      /* final gazeData = GazeData(
        x: x,
        y: y,
        confidence: coordinatesFound ? 0.8 : 0.3,
        timestamp: DateTime.fromMillisecondsSinceEpoch(
          timestamp.toInt(),
        ),
      ); */

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

  @override
  Future<bool> stopTracking() async {
    try {
      _emitNewState(EyeTrackingState.ready);

      if (_webGazerStarted && _hasWebGazerProperty()) {
        try {
          _callWebGazerMethod('pause');
        } catch (e) {
          _evalJS('webgazer.pause()');
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
      _emitNewState(EyeTrackingState.paused);

      if (_webGazerStarted && _hasWebGazerProperty()) {
        try {
          _callWebGazerMethod('pause');
        } catch (e) {
          _evalJS('webgazer.pause()');
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
      _emitNewState(EyeTrackingState.tracking);
      if (_webGazerStarted && _hasWebGazerProperty()) {
        try {
          _callWebGazerMethod('resume');
        } catch (e) {
          _evalJS('webgazer.resume()');
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
        _currentState != EyeTrackingState.warmingUp &&
        _currentState != EyeTrackingState.tracking) {
      return false;
    }

    // await _ensureTrackerOn();
    // await _awaitLiveFrames(timeout: const Duration(seconds: 3));

    _calibTrainSamples = 0;
    _calibEvalSamples = 0;
    _sumErrPx = 0.0;
    _lastAccuracy01 = 0.0;

    try {
      _calibrationPoints = List.from(points);
      _isCalibrating = true;
      _emitNewState(EyeTrackingState.calibrating);

      // Clear existing calibration if WebGazer is loaded
      if (_webGazerStarted && _hasWebGazerProperty()) {
        try {
          _callWebGazerMethod('clearData');
        } catch (e) {
          _evalJS('webgazer.clearData()');
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
      if (_webGazerStarted && _hasWebGazerProperty()) {
        // Add calibration point to WebGazer multiple times for better accuracy
        // ---- 1) TRAIN PHASE ----
        const trainDuration = Duration(milliseconds: 1200);
        const trainTick = Duration(milliseconds: 100);
        final trainEnd = DateTime.now().add(trainDuration);

        while (DateTime.now().isBefore(trainEnd)) {
          try {
            _callWebGazerMethod('recordScreenPosition', [
              point.x.toJS,
              point.y.toJS,
            ]);
          } catch (_) {
            _evalJS(
              'webgazer.recordScreenPosition(${point.x}, ${point.y})',
            );
          }
          _calibTrainSamples++;
          await Future.delayed(trainTick);
        }

        // ---- 2) EVAL PHASE (no recording, just measure error) ----
        const evalDuration = Duration(milliseconds: 800);
        final evalEnd = DateTime.now().add(evalDuration);

        // listen temporarily to our gaze stream
        final sub = _gazeController.stream.listen((g) {
          if (!g.x.isFinite || !g.y.isFinite) return;
          final dx = g.x - point.x;
          final dy = g.y - point.y;
          _sumErrPx += math.sqrt(dx * dx + dy * dy);
          _calibEvalSamples++;
        });

        while (DateTime.now().isBefore(evalEnd)) {
          await Future.delayed(
            const Duration(milliseconds: 16),
          ); // ~60 Hz
        }
        await sub.cancel();
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
      _emitNewState(EyeTrackingState.ready);
      // force a final accuracy computation so callers can read the cached value fast
      await getCalibrationAccuracy();
      return true;
    } catch (e) {
      return false;
    }
  }

  @override
  Future<bool> clearCalibration() async {
    try {
      if (_webGazerStarted && _hasWebGazerProperty()) {
        try {
          _callWebGazerMethod('clearData');
        } catch (e) {
          _evalJS('webgazer.clearData()');
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
    if (_calibEvalSamples == 0 || _calibTrainSamples == 0) {
      return _lastAccuracy01;
    }
    // Require some data before trusting accuracy
    const int kMinTrain = 12; // tune
    const int kMinEval = 10; // tune
    if (_calibTrainSamples < kMinTrain ||
        _calibEvalSamples < kMinEval) {
      return _lastAccuracy01;
    }

    final meanErrPx = _sumErrPx / _calibEvalSamples;

    // Use current viewport diagonal for normalization
    final w = window.innerWidth
        .toDouble(); // ??window.screen.width.toDouble()
    final h = window.innerHeight
        .toDouble(); // ??window.screen.height.toDouble()
    final diag = math.sqrt(w * w + h * h);

    final acc01 = (1.0 - (meanErrPx / diag)).clamp(0.0, 1.0);

    // Soft reliability penalty that saturates as samples grow
    double saturate(int n, int k) => 1 - math.exp(-n / k);
    final rTrain = saturate(
        _calibTrainSamples, 15); // reaches ~0.86 at 30 samples
    final rEval = saturate(_calibEvalSamples, 12);

    _lastAccuracy01 =
        (acc01 * math.min(rTrain, rEval)).clamp(0.0, 1.0);
    return _lastAccuracy01;
  }

  @override
  Stream<GazeData> getGazeStream() {
    return _gazeController.stream;
  }

  @override
  Stream<EyeTrackingState> getStateStream() {
    return _stateController.stream;
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
    if (!_webGazerLoaded || !_hasWebGazerProperty()) {
      return false;
    }

    try {
      final regressionMode = switch (mode) {
        'high' => 'ridge',
        'medium' => 'weightedRidge',
        'fast' => 'threadedRidge', //'linear',
        _ => 'ridge',
      };

      try {
        _callWebGazerMethod('setRegression', [regressionMode.toJS]);
      } catch (e) {
        _evalJS('webgazer.setRegression("$regressionMode")');
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

  //You can use WebGazerTracker enum options here
  @override
  Future<bool> setTracker(String tracker) async {
    if (!_webGazerLoaded || !_hasWebGazerProperty()) return false;
    try {
      _callWebGazerMethod('setTracker', [tracker.toJS]);
      return true;
    } catch (_) {
      _evalJS('webgazer.setTracker("$tracker")');
      return true;
    }
  }

  //You can use WebGazerRegression enum options here
  @override
  Future<bool> setRegression(String regression) async {
    if (!_webGazerLoaded || !_hasWebGazerProperty()) return false;
    try {
      _callWebGazerMethod('setRegression', [regression.toJS]);
      return true;
    } catch (_) {
      _evalJS('webgazer.setRegression("$regression")');
      return true;
    }
  }

  @override
  Future<bool> addTrackerModule(
    String name,
    String constructorJsGlobal,
  ) async {
    if (!_webGazerLoaded || !_hasWebGazerProperty()) return false;
    // constructorJsGlobal: a global function/class name exposed in JS, e.g. "MyTracker"
    try {
      _evalJS(
        'webgazer.addTrackerModule("$name", $constructorJsGlobal)',
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> addRegressionModule(
    String name,
    String constructorJsGlobal,
  ) async {
    if (!_webGazerLoaded || !_hasWebGazerProperty()) return false;
    try {
      _evalJS(
        'webgazer.addRegressionModule("$name", $constructorJsGlobal)',
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<Map<String, dynamic>> getCapabilities() async {
    return {
      'platform': 'web',
      'gaze_tracking': _webGazerLoaded,
      'eye_state_detection':
          false, // To be implemented with MediaPipe
      'head_pose_estimation':
          false, // To be implemented with MediaPipe
      'multiple_faces': false, // To be implemented with MediaPipe
      'calibration': _webGazerLoaded,
      'background_tracking': false,
      'max_faces': 1,
      'accuracy_modes': ['high', 'medium', 'fast'],
      'webgazer_loaded': _webGazerLoaded,
      'webgazer_started': _webGazerStarted,
    };
  }

  /// ----------------- helpers -----------------

  final int _pageStartEpochMs = DateTime.now().millisecondsSinceEpoch;
  double? _firstJsTimestamp;

  Future<void> _ensureTrackerOn() async {
    if (!_webGazerStarted) {
      await _initializeWebGazer();
    } else {
      try {
        _callWebGazerMethod('resume');
      } catch (_) {
        _evalJS('webgazer.resume()');
      }
    }
  }

  /// Wait until we see a short streak of valid gaze frames (not a fixed delay).
  Future<void> _awaitLiveFrames({
    int minFrames = 8, // ~250ms at 30fps
    int maxDtMs = 180, // each sample spacing ≤ 180ms
    double minConf = 0.25, // allow low but nonzero conf early
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final completer = Completer<void>();
    int streak = 0;
    int lastTs = 0;

    final sub = _gazeController.stream.listen((g) {
      if (!g.x.isFinite || !g.y.isFinite) {
        streak = 0;
        return;
      }

      final t = g.timestamp.millisecondsSinceEpoch;
      final dt = (lastTs == 0) ? 0 : (t - lastTs);
      lastTs = t;

      final dtOk = (dt == 0) || (dt <= maxDtMs);
      final confOk = g.confidence.isFinite && g.confidence >= minConf;

      if (dtOk && confOk) {
        if (++streak >= minFrames && !completer.isCompleted) {
          completer.complete();
        }
      } else {
        streak = 0;
      }
    });

    try {
      await completer.future.timeout(timeout, onTimeout: () => null);
    } finally {
      await sub.cancel();
    }
  }

  double updateGazeConfidence({
    required double x,
    required double y,
    required DateTime timestamp,
  }) {
    final sampleMs = timestamp.millisecondsSinceEpoch;
    // 0) attention gate (tab active + visible)
    final attention = (_docHasFocus && _docVisible);
    if (!attention) {
      _emaConf = 0.3;
      _lastEpochMs = sampleMs;
      return _emaConf;
    }
    // 1) Frame-to-frame dt
    final dtMs = (_lastEpochMs == 0)
        ? 16
        : (sampleMs - _lastEpochMs).clamp(1, 2000);
    _lastEpochMs = sampleMs;

    // 2) Freshness: full score if dt ≤ 150 ms, then smooth decay.
    //    Map: 0..150ms → 1.0, 150..600ms → 1→0
    double fTime;
    if (dtMs <= 150) {
      fTime = 1.0;
    } else if (dtMs >= 600) {
      fTime = 0.0;
    } else {
      fTime = 1.0 - ((dtMs - 150) / (600 - 150));
    }

    // 3) In-bounds (soft margin). No heavy math.
    final vw = (window.innerWidth
        .toDouble()); //?? window.screen.width.toDouble()
    final vh = (window.innerHeight
        .toDouble()); //??window.screen.height.toDouble()

    // Soft margin: fully good if ≥m px inside; smoothly drops to 0 by going m px outside.
    const m = 32.0; // margin in px
    double insideX = 0, insideY = 0;

    if (x >= 0 && x <= vw) {
      // how far from nearest edge, clamped at m
      final dx = math.min(x, vw - x);
      insideX = (dx >= m) ? 1.0 : (dx / m).clamp(0.0, 1.0);
    } else {
      final dxOut = (x < 0) ? -x : (x - vw);
      insideX = (1.0 - (dxOut / m)).clamp(0.0, 1.0);
    }

    if (y >= 0 && y <= vh) {
      final dy = math.min(y, vh - y);
      insideY = (dy >= m) ? 1.0 : (dy / m).clamp(0.0, 1.0);
    } else {
      final dyOut = (y < 0) ? -y : (y - vh);
      insideY = (1.0 - (dyOut / m)).clamp(0.0, 1.0);
    }

    // Combine X/Y with simple mean (or min if you want stricter).
    final fBounds = 0.5 * (insideX + insideY);

    // 4) Target = simple weighted combo. (Time is a bit more important.)
    //    You can set both to 0.5 for equal weight.
    const wTime = 0.45;
    const wBounds = 0.55;
    final target = (wTime * fTime + wBounds * fBounds).clamp(
      0.0,
      1.0,
    );

    // 5) Two-rate EMA + small anti-cliff cap.
    //    If target >= EMA → rise quickly; else decay slowly.
    const alphaUp = 0.35; // fast recovery
    const alphaDn = 0.10; // slow decay
    final alpha = (target >= _emaConf) ? alphaUp : alphaDn;

    double next = _emaConf + alpha * (target - _emaConf);

    // Prevent sudden drops per frame (e.g. due to a single bad sample).
    const maxDropPerFrame = 0.05; // 5%
    if (next < _emaConf - maxDropPerFrame) {
      next = _emaConf - maxDropPerFrame;
    }

    // Clamp and store
    _emaConf = next.clamp(0.0, 0.90);
    return _emaConf;
  }

  int _toEpochMs(num jsTimestamp) {
    // jsTimestamp is likely DOMHighResTimeStamp (ms since page start)
    _firstJsTimestamp ??= jsTimestamp.toDouble();
    final deltaMs = (jsTimestamp.toDouble() - _firstJsTimestamp!)
        .clamp(-1e9, 1e9);
    return _pageStartEpochMs + deltaMs.toInt();
  }

  JSAny? _evalJSAndGetResult(String code) {
    return (window as JSObject).callMethodVarArgs('eval'.toJS, [
      code.toJS,
    ]);
  }

  Future<void> _performAutoCalibration() async {
    // Add some basic calibration points to help WebGazer learn
    final screenWidth = window.screen.width.toDouble();
    final screenHeight = window.screen.height.toDouble();

    // Use center and corner points for quick calibration
    final autoCalibrationPoints = [
      CalibrationPoint(
        x: screenWidth * 0.5,
        y: screenHeight * 0.5,
        order: 0,
      ), // Center
      /*  CalibrationPoint(
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
          order: 4), // Bottom-right area */
    ];

    try {
      for (int i = 0; i < autoCalibrationPoints.length; i++) {
        final point = autoCalibrationPoints[i];

        // Add multiple samples for each point
        for (int sample = 0; sample < 3; sample++) {
          try {
            _evalJS(
              'webgazer.recordScreenPosition(${point.x}, ${point.y});',
            );
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

  _emitNewState(EyeTrackingState state) {
    _currentState = state;
    // Emit state to stream
    if (!_stateController.isClosed) {
      try {
        _stateController.add(_currentState);
      } catch (e) {
        // Silently handle stream errors
      }
    }
  }

  @override
  Future<bool> dispose() async {
    try {
      _trackingTimer?.cancel();

      await _gazeController.close();
      await _stateController.close();
      await _eyeStateController.close();
      await _headPoseController.close();
      await _faceDetectionController.close();

      // Stop WebGazer
      if (_webGazerStarted && _hasWebGazerProperty()) {
        try {
          _callWebGazerMethod('end');
        } catch (e) {
          _evalJS('webgazer.end()');
        }
      }

      return true;
    } catch (e) {
      return false;
    }
  }
}

/// WebGazer built-in trackers
enum WebGazerTracker {
  tfFaceMesh('TFFacemesh'),
  clmTrackr('clmtrackr'),
  jsObjectDetect('js_objectdetect'),
  trackingJS('trackingjs');

  final String value;
  const WebGazerTracker(this.value);

  @override
  String toString() => value;
}

/// WebGazer built-in regressions
enum WebGazerRegression {
  ridge('ridge'),
  weightedRidge('weightedRidge'),
  threadedRidge('threadedRidge');

  final String value;
  const WebGazerRegression(this.value);

  @override
  String toString() => value;
}

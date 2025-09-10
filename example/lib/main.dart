import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';

import 'package:eye_tracking/eye_tracking.dart';
import 'package:eye_tracking/eye_tracking_platform_interface.dart';

/// Entry point for the Eye Tracking example application
void main() {
  runApp(const MyApp());
}

/// Main application widget
class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Eye Tracking Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const EyeTrackingDemo(),
    );
  }
}

/// Demo widget showcasing eye tracking functionality
class EyeTrackingDemo extends StatefulWidget {
  const EyeTrackingDemo({super.key});

  @override
  State<EyeTrackingDemo> createState() => _EyeTrackingDemoState();
}

class _EyeTrackingDemoState extends State<EyeTrackingDemo> {
  final _eyeTrackingPlugin = EyeTracking();

  // State variables
  String _platformVersion = 'Unknown';
  EyeTrackingState _currentState = EyeTrackingState.uninitialized;
  bool _hasPermission = false;
  bool _isInitialized = false;
  Map<String, dynamic> _capabilities = {};

  // Gaze tracking data
  GazeData? _latestGaze;
  EyeState? _latestEyeState;
  HeadPose? _latestHeadPose;
  List<FaceDetection> _detectedFaces = [];

  // Calibration
  bool _isCalibrating = false;
  List<CalibrationPoint> _calibrationPoints = [];
  double _calibrationAccuracy = 0.0;

  // Stream subscriptions
  StreamSubscription<GazeData>? _gazeSubscription;
  StreamSubscription<EyeState>? _eyeStateSubscription;
  StreamSubscription<HeadPose>? _headPoseSubscription;
  StreamSubscription<List<FaceDetection>>? _faceSubscription;

  // Gaze visualization
  final List<Offset> _gazeHistory = [];
  final int _maxGazeHistory = 50;

  @override
  void initState() {
    super.initState();
    initPlatformState();
  }

  @override
  void dispose() {
    _stopAllStreams();
    _eyeTrackingPlugin.dispose();
    super.dispose();
  }

  Future<void> initPlatformState() async {
    String platformVersion;
    try {
      platformVersion =
          await _eyeTrackingPlugin.getPlatformVersion() ??
          'Unknown platform version';
    } on PlatformException {
      platformVersion = 'Failed to get platform version.';
    }

    if (!mounted) return;

    setState(() {
      _platformVersion = platformVersion;
    });
  }

  Future<void> _initialize() async {
    try {
      final success = await _eyeTrackingPlugin.initialize();
      final capabilities = await _eyeTrackingPlugin.getCapabilities();
      final state = await _eyeTrackingPlugin.getState();

      setState(() {
        _isInitialized = success;
        _capabilities = capabilities;
        _currentState = state;
      });

      if (success) {
        _showSnackBar('Eye tracking initialized successfully!', Colors.green);
      } else {
        _showSnackBar('Failed to initialize eye tracking', Colors.red);
      }
    } catch (e) {
      _showSnackBar('Error: $e', Colors.red);
    }
  }

  Future<void> _requestPermission() async {
    try {
      final hasPermission = await _eyeTrackingPlugin.requestCameraPermission();
      setState(() {
        _hasPermission = hasPermission;
      });

      if (hasPermission) {
        _showSnackBar('Camera permission granted!', Colors.green);
      } else {
        _showSnackBar('Camera permission denied', Colors.orange);
      }
    } catch (e) {
      _showSnackBar('Error requesting permission: $e', Colors.red);
    }
  }

  Future<void> _startTracking() async {
    try {
      final success = await _eyeTrackingPlugin.startTracking();
      final state = await _eyeTrackingPlugin.getState();

      setState(() {
        _currentState = state;
      });

      if (success) {
        _startDataStreams();
        _showSnackBar('Eye tracking started!', Colors.green);
      } else {
        _showSnackBar('Failed to start tracking', Colors.red);
      }
    } catch (e) {
      _showSnackBar('Error starting tracking: $e', Colors.red);
    }
  }

  Future<void> _stopTracking() async {
    try {
      await _eyeTrackingPlugin.stopTracking();
      final state = await _eyeTrackingPlugin.getState();

      setState(() {
        _currentState = state;
      });

      _stopAllStreams();
      _showSnackBar('Eye tracking stopped', Colors.blue);
    } catch (e) {
      _showSnackBar('Error stopping tracking: $e', Colors.red);
    }
  }

  Future<void> _testGazeStatus() async {
    try {
      // Show current gaze status to user
      if (_latestGaze != null) {
        _showSnackBar(
          'Gaze detected: (${_latestGaze!.x.toInt()}, ${_latestGaze!.y.toInt()}) - Confidence: ${(_latestGaze!.confidence * 100).toInt()}%',
          Colors.green,
        );
      } else {
        _showSnackBar('No gaze data available yet', Colors.orange);
      }
    } catch (e) {
      _showSnackBar('Error checking gaze status: $e', Colors.red);
    }
  }

  void _startDataStreams() {
    // Gaze data stream with optimized UI updates
    _gazeSubscription = _eyeTrackingPlugin.getGazeStream().listen((gazeData) {
      // Only update UI if coordinates have actually changed significantly
      // to avoid excessive rebuilds
      final hasSignificantChange =
          _latestGaze == null ||
          (gazeData.x - _latestGaze!.x).abs() > 5.0 ||
          (gazeData.y - _latestGaze!.y).abs() > 5.0;

      if (hasSignificantChange) {
        setState(() {
          _latestGaze = gazeData;

          // Add to gaze history for visualization (but limit frequency)
          _gazeHistory.add(Offset(gazeData.x, gazeData.y));
          if (_gazeHistory.length > _maxGazeHistory) {
            _gazeHistory.removeAt(0);
          }
        });
      } else {
        // Update the latest gaze without triggering UI rebuild
        _latestGaze = gazeData;
      }
    });

    // Eye state stream
    _eyeStateSubscription = _eyeTrackingPlugin.getEyeStateStream().listen((
      eyeState,
    ) {
      setState(() {
        _latestEyeState = eyeState;
      });
    });

    // Head pose stream
    _headPoseSubscription = _eyeTrackingPlugin.getHeadPoseStream().listen((
      headPose,
    ) {
      setState(() {
        _latestHeadPose = headPose;
      });
    });

    // Face detection stream
    _faceSubscription = _eyeTrackingPlugin.getFaceDetectionStream().listen((
      faces,
    ) {
      setState(() {
        _detectedFaces = faces;
      });
    });
  }

  void _stopAllStreams() {
    _gazeSubscription?.cancel();
    _eyeStateSubscription?.cancel();
    _headPoseSubscription?.cancel();
    _faceSubscription?.cancel();

    setState(() {
      _latestGaze = null;
      _latestEyeState = null;
      _latestHeadPose = null;
      _detectedFaces = [];
      _gazeHistory.clear();
    });
  }

  Future<void> _startCalibration() async {
    final screenSize = MediaQuery.of(context).size;
    _calibrationPoints = EyeTracking.createStandardCalibration(
      screenWidth: screenSize.width,
      screenHeight: screenSize.height,
    );

    try {
      final success = await _eyeTrackingPlugin.startCalibration(
        _calibrationPoints,
      );
      if (success) {
        setState(() {
          _isCalibrating = true;
        });
        _showCalibrationDialog();
      }
    } catch (e) {
      _showSnackBar('Error starting calibration: $e', Colors.red);
    }
  }

  void _showCalibrationDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => CalibrationDialog(
            calibrationPoints: _calibrationPoints,
            onPointCompleted: _onCalibrationPointCompleted,
            onCalibrationFinished: _onCalibrationFinished,
            eyeTrackingPlugin: _eyeTrackingPlugin,
          ),
    );
  }

  Future<void> _onCalibrationPointCompleted() async {
    // Point completed - this can be used for UI feedback if needed
  }

  Future<void> _onCalibrationFinished() async {
    try {
      await _eyeTrackingPlugin.finishCalibration();
      final accuracy = await _eyeTrackingPlugin.getCalibrationAccuracy();

      setState(() {
        _isCalibrating = false;
        _calibrationAccuracy = accuracy;
      });

      _showSnackBar(
        'Calibration completed! Accuracy: ${(accuracy * 100).toStringAsFixed(1)}%',
        Colors.green,
      );
    } catch (e) {
      _showSnackBar('Error finishing calibration: $e', Colors.red);
    }
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Eye Tracking Demo'),
      ),
      body: Stack(
        children: [
          // Main content
          SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildInfoCard(),
                const SizedBox(height: 16),
                _buildControlsCard(),
                const SizedBox(height: 16),
                _buildDataCard(),
                const SizedBox(height: 16),
                _buildCapabilitiesCard(),
              ],
            ),
          ),

          // Gaze visualization overlay
          if (_latestGaze != null) _buildGazeVisualization(),
        ],
      ),
    );
  }

  Widget _buildInfoCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Platform Info',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text('Platform: $_platformVersion'),
            Text('State: ${_currentState.name}'),
            Text('Initialized: $_isInitialized'),
            Text('Has Permission: $_hasPermission'),
            if (_calibrationAccuracy > 0)
              Text(
                'Calibration Accuracy: ${(_calibrationAccuracy * 100).toStringAsFixed(1)}%',
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Controls', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton(
                  onPressed: _isInitialized ? null : _initialize,
                  child: const Text('Initialize'),
                ),
                ElevatedButton(
                  onPressed: _hasPermission ? null : _requestPermission,
                  child: const Text('Request Permission'),
                ),
                ElevatedButton(
                  onPressed:
                      (_isInitialized &&
                              _hasPermission &&
                              _currentState != EyeTrackingState.tracking)
                          ? _startTracking
                          : null,
                  child: const Text('Start Tracking'),
                ),
                ElevatedButton(
                  onPressed:
                      _currentState == EyeTrackingState.tracking
                          ? _stopTracking
                          : null,
                  child: const Text('Stop Tracking'),
                ),
                ElevatedButton(
                  onPressed:
                      (_isInitialized && _hasPermission && !_isCalibrating)
                          ? _startCalibration
                          : null,
                  child: const Text('Calibrate'),
                ),
                ElevatedButton(
                  onPressed: _isInitialized ? _testGazeStatus : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                  ),
                  child: const Text('Test Gaze'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDataCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Real-time Data',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            if (_latestGaze != null) ...[
              Text(
                'Gaze Position:',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(
                'X: ${_latestGaze!.x.toStringAsFixed(1)}, Y: ${_latestGaze!.y.toStringAsFixed(1)}',
              ),
              Text(
                'Confidence: ${(_latestGaze!.confidence * 100).toStringAsFixed(1)}%',
              ),
              const SizedBox(height: 8),
            ],
            if (_latestEyeState != null) ...[
              Text(
                'Eye State:',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(
                'Left Eye: ${_latestEyeState!.leftEyeOpen ? "Open" : "Closed"}',
              ),
              Text(
                'Right Eye: ${_latestEyeState!.rightEyeOpen ? "Open" : "Closed"}',
              ),
              if (_latestEyeState!.leftEyeBlink ||
                  _latestEyeState!.rightEyeBlink)
                const Text(
                  'Blink detected!',
                  style: TextStyle(color: Colors.orange),
                ),
              const SizedBox(height: 8),
            ],
            if (_latestHeadPose != null) ...[
              Text(
                'Head Pose:',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text('Pitch: ${_latestHeadPose!.pitch.toStringAsFixed(1)}°'),
              Text('Yaw: ${_latestHeadPose!.yaw.toStringAsFixed(1)}°'),
              Text('Roll: ${_latestHeadPose!.roll.toStringAsFixed(1)}°'),
              const SizedBox(height: 8),
            ],
            if (_detectedFaces.isNotEmpty) ...[
              Text(
                'Detected Faces: ${_detectedFaces.length}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              for (final face in _detectedFaces)
                Text(
                  'Face ${face.faceId}: ${(face.confidence * 100).toStringAsFixed(1)}% confidence',
                ),
            ],
            if (_latestGaze == null &&
                _currentState == EyeTrackingState.tracking)
              const Text(
                'Waiting for data...',
                style: TextStyle(fontStyle: FontStyle.italic),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCapabilitiesCard() {
    if (_capabilities.isEmpty) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Platform Capabilities',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            for (final entry in _capabilities.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(entry.key.replaceAll('_', ' ').toUpperCase()),
                    Text(
                      entry.value.toString(),
                      style: TextStyle(
                        color:
                            entry.value == true
                                ? Colors.green
                                : entry.value == false
                                ? Colors.red
                                : null,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildGazeVisualization() {
    return CustomPaint(
      size: Size.infinite,
      painter: GazePainter(
        currentGaze: _latestGaze!,
        gazeHistory: _gazeHistory,
      ),
    );
  }
}

class CalibrationDialog extends StatefulWidget {
  final List<CalibrationPoint> calibrationPoints;
  final VoidCallback onPointCompleted;
  final VoidCallback onCalibrationFinished;
  final EyeTracking eyeTrackingPlugin;

  const CalibrationDialog({
    super.key,
    required this.calibrationPoints,
    required this.onPointCompleted,
    required this.onCalibrationFinished,
    required this.eyeTrackingPlugin,
  });

  @override
  State<CalibrationDialog> createState() => _CalibrationDialogState();
}

class _CalibrationDialogState extends State<CalibrationDialog> {
  int _currentPointIndex = 0;
  bool _isCollectingData = false;
  Timer? _calibrationTimer;

  @override
  void initState() {
    super.initState();
    _startCalibrationPoint();
  }

  @override
  void dispose() {
    _calibrationTimer?.cancel();
    super.dispose();
  }

  void _startCalibrationPoint() {
    if (_currentPointIndex >= widget.calibrationPoints.length) {
      _finishCalibration();
      return;
    }

    setState(() {
      _isCollectingData = false;
    });

    // Wait 1 second, then start collecting data for 3 seconds
    Future.delayed(const Duration(seconds: 1), () {
      if (!mounted) return;

      setState(() {
        _isCollectingData = true;
      });

      _calibrationTimer = Timer.periodic(const Duration(milliseconds: 100), (
        timer,
      ) async {
        if (_currentPointIndex < widget.calibrationPoints.length) {
          await widget.eyeTrackingPlugin.addCalibrationPoint(
            widget.calibrationPoints[_currentPointIndex],
          );
        }
      });

      // Stop after 3 seconds and move to next point
      Future.delayed(const Duration(seconds: 3), () {
        _calibrationTimer?.cancel();
        _currentPointIndex++;
        widget.onPointCompleted();
        _startCalibrationPoint();
      });
    });
  }

  void _finishCalibration() {
    widget.onCalibrationFinished();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    if (_currentPointIndex >= widget.calibrationPoints.length) {
      return const SizedBox.shrink();
    }

    final currentPoint = widget.calibrationPoints[_currentPointIndex];

    return Material(
      color: Colors.black54,
      child: Stack(
        children: [
          // Instructions at top
          Positioned(
            top: 50,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Calibration ${_currentPointIndex + 1}/${widget.calibrationPoints.length}',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isCollectingData
                          ? 'Keep looking at the circle!'
                          : 'Look at the circle and wait...',
                      style: const TextStyle(fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Calibration point
          Positioned(
            left: currentPoint.x - 25,
            top: currentPoint.y - 25,
            child: Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: _isCollectingData ? Colors.red : Colors.blue,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3),
              ),
              child: Center(
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class GazePainter extends CustomPainter {
  final GazeData currentGaze;
  final List<Offset> gazeHistory;

  GazePainter({required this.currentGaze, required this.gazeHistory});

  @override
  void paint(Canvas canvas, Size size) {
    // Draw gaze history trail
    if (gazeHistory.length > 1) {
      final paint =
          Paint()
            ..color = Colors.blue.withOpacity(0.3)
            ..strokeWidth = 2
            ..style = PaintingStyle.stroke;

      final path = Path();
      path.moveTo(gazeHistory.first.dx, gazeHistory.first.dy);

      for (int i = 1; i < gazeHistory.length; i++) {
        path.lineTo(gazeHistory[i].dx, gazeHistory[i].dy);
      }

      canvas.drawPath(path, paint);
    }

    // Draw current gaze point
    final gazePaint =
        Paint()
          ..color = Colors.red.withOpacity(0.8)
          ..style = PaintingStyle.fill;

    canvas.drawCircle(Offset(currentGaze.x, currentGaze.y), 8, gazePaint);

    // Draw confidence indicator
    final confidencePaint =
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2;

    canvas.drawCircle(
      Offset(currentGaze.x, currentGaze.y),
      8 + (currentGaze.confidence * 10),
      confidencePaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

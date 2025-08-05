import Flutter
import UIKit
import AVFoundation
import Vision
import ARKit

// MARK: - Camera Preview Platform View Factory
class CameraPreviewViewFactory: NSObject, FlutterPlatformViewFactory {
    private weak var plugin: EyeTrackingPlugin?
    
    init(plugin: EyeTrackingPlugin?) {
        self.plugin = plugin
        super.init()
    }
    
    func create(
        withFrame frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?
    ) -> FlutterPlatformView {
        let cameraManager = plugin?.accessibleCameraManager
        return CameraPreviewView(frame: frame, cameraManager: cameraManager)
    }
    
    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        return FlutterStandardMessageCodec.sharedInstance()
    }
}

// MARK: - Camera Preview Container View
class CameraPreviewContainerView: UIView {
    private var previewLayer: AVCaptureVideoPreviewLayer?
    
    override func layoutSubviews() {
        super.layoutSubviews()
        // Update preview layer frame when view bounds change
        previewLayer?.frame = bounds
    }
    
    func setPreviewLayer(_ layer: AVCaptureVideoPreviewLayer?) {
        // Remove existing layer if any
        previewLayer?.removeFromSuperlayer()
        
        self.previewLayer = layer
        
        if let layer = layer {
            layer.frame = bounds
            layer.videoGravity = .resizeAspectFill
            self.layer.addSublayer(layer)
        }
    }
}

// MARK: - Camera Preview Platform View
class CameraPreviewView: NSObject, FlutterPlatformView {
    private let containerView: CameraPreviewContainerView
    
    init(frame: CGRect, cameraManager: CameraManager?) {
        containerView = CameraPreviewContainerView(frame: frame)
        containerView.backgroundColor = UIColor.black
        
        super.init()
        
        setupPreviewLayer(cameraManager: cameraManager)
    }
    
    private func setupPreviewLayer(cameraManager: CameraManager?) {
        guard let previewLayer = cameraManager?.previewLayer else {
            print("❌ CameraPreviewView: No preview layer available")
            
            // Add a placeholder label when no camera is available
            let label = UILabel(frame: containerView.bounds)
            label.text = "Camera Preview\nNot Available"
            label.textAlignment = .center
            label.numberOfLines = 0
            label.textColor = UIColor.white
            label.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            containerView.addSubview(label)
            return
        }
        
        print("✅ CameraPreviewView: Setting up preview layer")
        containerView.setPreviewLayer(previewLayer)
    }
    
    func view() -> UIView {
        return containerView
    }
}

public class EyeTrackingPlugin: NSObject, FlutterPlugin {
    
    // MARK: - Properties
    private let methodChannel: FlutterMethodChannel
    private let gazeEventChannel: FlutterEventChannel
    private let eyeStateEventChannel: FlutterEventChannel
    private let headPoseEventChannel: FlutterEventChannel
    private let faceDetectionEventChannel: FlutterEventChannel
    
    private var eyeTracker: EyeTracker?
    private var cameraManager: CameraManager?
    
    // MARK: - Event Sinks
    private var gazeEventSink: FlutterEventSink?
    private var eyeStateEventSink: FlutterEventSink?
    private var headPoseEventSink: FlutterEventSink?
    private var faceDetectionEventSink: FlutterEventSink?
    
    // MARK: - Internal accessors for platform views
    var accessibleCameraManager: CameraManager? {
        return cameraManager
    }
    
    // MARK: - Plugin Registration
    public static func register(with registrar: FlutterPluginRegistrar) {
        print("🔔 iOS Plugin: Registering eye tracking plugin")
        
        let methodChannel = FlutterMethodChannel(name: "eye_tracking", binaryMessenger: registrar.messenger())
        let gazeEventChannel = FlutterEventChannel(name: "eye_tracking/gaze", binaryMessenger: registrar.messenger())
        let eyeStateEventChannel = FlutterEventChannel(name: "eye_tracking/eye_state", binaryMessenger: registrar.messenger())
        let headPoseEventChannel = FlutterEventChannel(name: "eye_tracking/head_pose", binaryMessenger: registrar.messenger())
        let faceDetectionEventChannel = FlutterEventChannel(name: "eye_tracking/face_detection", binaryMessenger: registrar.messenger())
        
        let instance = EyeTrackingPlugin(
            methodChannel: methodChannel,
            gazeEventChannel: gazeEventChannel,
            eyeStateEventChannel: eyeStateEventChannel,
            headPoseEventChannel: headPoseEventChannel,
            faceDetectionEventChannel: faceDetectionEventChannel
        )
        
        registrar.addMethodCallDelegate(instance, channel: methodChannel)
        
        // Register camera preview platform view
        let cameraPreviewFactory = CameraPreviewViewFactory(plugin: instance)
        registrar.register(cameraPreviewFactory, withId: "eye_tracking_camera_preview")
        
        // Set up event channel stream handlers
        gazeEventChannel.setStreamHandler(GazeStreamHandler(plugin: instance))
        eyeStateEventChannel.setStreamHandler(EyeStateStreamHandler(plugin: instance))
        headPoseEventChannel.setStreamHandler(HeadPoseStreamHandler(plugin: instance))
        faceDetectionEventChannel.setStreamHandler(FaceDetectionStreamHandler(plugin: instance))
        
        print("✅ iOS Plugin: Registration completed successfully")
    }
    
    // MARK: - Initialization
    private init(methodChannel: FlutterMethodChannel,
                gazeEventChannel: FlutterEventChannel,
                eyeStateEventChannel: FlutterEventChannel,
                headPoseEventChannel: FlutterEventChannel,
                faceDetectionEventChannel: FlutterEventChannel) {
        self.methodChannel = methodChannel
        self.gazeEventChannel = gazeEventChannel
        self.eyeStateEventChannel = eyeStateEventChannel
        self.headPoseEventChannel = headPoseEventChannel
        self.faceDetectionEventChannel = faceDetectionEventChannel
        super.init()
    }
    
    // MARK: - Flutter Method Channel Handler
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        print("🔔 iOS Plugin: handle() called with method: \(call.method)")
        
        switch call.method {
        case "getPlatformVersion":
            print("🔔 iOS Plugin: handling getPlatformVersion")
            result("iOS " + UIDevice.current.systemVersion)
            
        case "initialize":
            print("🔔 iOS Plugin: handling initialize")
            handleInitialize(result)
            
        case "requestCameraPermission":
            handleRequestCameraPermission(result)
            
        case "hasCameraPermission":
            handleHasCameraPermission(result)
            
        case "getState":
            handleGetState(result)
            
        case "startTracking":
            handleStartTracking(result)
            
        case "stopTracking":
            handleStopTracking(result)
            
        case "pauseTracking":
            handlePauseTracking(result)
            
        case "resumeTracking":
            handleResumeTracking(result)
            
        case "startCalibration":
            handleStartCalibration(call, result)
            
        case "addCalibrationPoint":
            handleAddCalibrationPoint(call, result)
            
        case "finishCalibration":
            handleFinishCalibration(result)
            
        case "clearCalibration":
            handleClearCalibration(result)
            
        case "getCalibrationAccuracy":
            handleGetCalibrationAccuracy(result)
            
        case "setTrackingFrequency":
            handleSetTrackingFrequency(call, result)
            
        case "setAccuracyMode":
            handleSetAccuracyMode(call, result)
            
        case "enableBackgroundTracking":
            handleEnableBackgroundTracking(call, result)
            
        case "getCapabilities":
            handleGetCapabilities(result)
            
        case "dispose":
            handleDispose(result)
            
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    // MARK: - Event Sink Setters
    func setGazeEventSink(_ eventSink: FlutterEventSink?) {
        print("🔔 EyeTrackingPlugin: setGazeEventSink called")
        self.gazeEventSink = eventSink
        
        eyeTracker?.setGazeDataCallback { [weak self] gazeData in
            self?.gazeEventSink?(gazeData.toDictionary())
        }
        print("✅ EyeTrackingPlugin: Gaze callback configured")
    }
    
    func setEyeStateEventSink(_ eventSink: FlutterEventSink?) {
        print("🔔 EyeTrackingPlugin: setEyeStateEventSink called with eventSink: \(eventSink != nil ? "non-nil" : "nil")")
        self.eyeStateEventSink = eventSink
        eyeTracker?.setEyeStateCallback { [weak self] eyeState in
            print("📊 EyeTrackingPlugin: Eye state callback fired - sending to Flutter: \(eyeState)")
            self?.eyeStateEventSink?(eyeState.toDictionary())
        }
        print("✅ EyeTrackingPlugin: Eye state callback configured")
    }
    
    func setHeadPoseEventSink(_ eventSink: FlutterEventSink?) {
        print("🔔 EyeTrackingPlugin: setHeadPoseEventSink called with eventSink: \(eventSink != nil ? "non-nil" : "nil")")
        self.headPoseEventSink = eventSink
        eyeTracker?.setHeadPoseCallback { [weak self] headPose in
            print("📊 EyeTrackingPlugin: Head pose callback fired - sending to Flutter: \(headPose)")
            self?.headPoseEventSink?(headPose.toDictionary())
        }
        print("✅ EyeTrackingPlugin: Head pose callback configured")
    }
    
    func setFaceDetectionEventSink(_ eventSink: FlutterEventSink?) {
        print("🔔 EyeTrackingPlugin: setFaceDetectionEventSink called with eventSink: \(eventSink != nil ? "non-nil" : "nil")")
        self.faceDetectionEventSink = eventSink
        eyeTracker?.setFaceDetectionCallback { [weak self] faces in
            print("📊 EyeTrackingPlugin: Face detection callback fired - sending \(faces.count) faces to Flutter")
            let faceDictionaries = faces.map { $0.toDictionary() }
            self?.faceDetectionEventSink?(faceDictionaries)
        }
        print("✅ EyeTrackingPlugin: Face detection callback configured")
    }
}

// MARK: - Method Implementations
extension EyeTrackingPlugin {
    
    private func handleInitialize(_ result: @escaping FlutterResult) {
        print("🔄 iOS: Initializing eye tracking...")
        
        cameraManager = CameraManager()
        eyeTracker = EyeTracker(cameraManager: cameraManager!)
        
        let success = eyeTracker?.initialize() ?? false
        
        if success {
            print("✅ iOS: Eye tracking initialized successfully")
        } else {
            print("❌ iOS: Eye tracking initialization failed")
        }
        
        result(success)
    }
    
    private func handleRequestCameraPermission(_ result: @escaping FlutterResult) {
        CameraManager.requestCameraPermission { granted in
            DispatchQueue.main.async {
                result(granted)
            }
        }
    }
    
    private func handleHasCameraPermission(_ result: @escaping FlutterResult) {
        result(CameraManager.hasCameraPermission())
    }
    
    private func handleGetState(_ result: @escaping FlutterResult) {
        let state = eyeTracker?.getCurrentState() ?? .uninitialized
        result(state.rawValue)
    }
    
    private func handleStartTracking(_ result: @escaping FlutterResult) {
        print("🔄 iOS: Starting eye tracking...")
        
        let success = eyeTracker?.startTracking() ?? false
        
        if success {
            print("✅ iOS: Eye tracking started successfully")
        } else {
            print("❌ iOS: Failed to start eye tracking")
        }
        
        result(success)
    }
    
    private func handleStopTracking(_ result: @escaping FlutterResult) {
        let success = eyeTracker?.stopTracking() ?? false
        result(success)
    }
    
    private func handlePauseTracking(_ result: @escaping FlutterResult) {
        let success = eyeTracker?.pauseTracking() ?? false
        result(success)
    }
    
    private func handleResumeTracking(_ result: @escaping FlutterResult) {
        let success = eyeTracker?.resumeTracking() ?? false
        result(success)
    }
    
    private func handleStartCalibration(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        guard let arguments = call.arguments as? [String: Any],
              let pointsData = arguments["points"] as? [[String: Any]] else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "Invalid calibration points", details: nil))
            return
        }
        
        let calibrationPoints = pointsData.compactMap { CalibrationPoint.fromDictionary($0) }
        let success = eyeTracker?.startCalibration(with: calibrationPoints) ?? false
        result(success)
    }
    
    private func handleAddCalibrationPoint(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        guard let arguments = call.arguments as? [String: Any],
              let pointData = arguments["point"] as? [String: Any],
              let point = CalibrationPoint.fromDictionary(pointData) else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "Invalid calibration point", details: nil))
            return
        }
        
        let success = eyeTracker?.addCalibrationPoint(point) ?? false
        result(success)
    }
    
    private func handleFinishCalibration(_ result: @escaping FlutterResult) {
        let success = eyeTracker?.finishCalibration() ?? false
        result(success)
    }
    
    private func handleClearCalibration(_ result: @escaping FlutterResult) {
        let success = eyeTracker?.clearCalibration() ?? false
        result(success)
    }
    
    private func handleGetCalibrationAccuracy(_ result: @escaping FlutterResult) {
        let accuracy = eyeTracker?.getCalibrationAccuracy() ?? 0.0
        result(accuracy)
    }
    
    private func handleSetTrackingFrequency(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        guard let fps = call.arguments as? Int else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "Invalid FPS value", details: nil))
            return
        }
        
        let success = eyeTracker?.setTrackingFrequency(fps) ?? false
        result(success)
    }
    
    private func handleSetAccuracyMode(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        guard let mode = call.arguments as? String else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "Invalid accuracy mode", details: nil))
            return
        }
        
        let success = eyeTracker?.setAccuracyMode(mode) ?? false
        result(success)
    }
    
    private func handleEnableBackgroundTracking(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        guard let enable = call.arguments as? Bool else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "Invalid boolean value", details: nil))
            return
        }
        
        let success = eyeTracker?.enableBackgroundTracking(enable) ?? false
        result(success)
    }
    
    private func handleGetCapabilities(_ result: @escaping FlutterResult) {
        let capabilities: [String: Any] = [
            "platform": "ios",
            "gaze_tracking": true,
            "eye_state_detection": true,
            "head_pose_estimation": true,
            "face_detection": true,
            "multiple_faces": true,
            "max_faces": 4,
            "calibration": true,
            "background_tracking": true,
            "accuracy_modes": ["fast", "medium", "high"],
            "max_fps": 60,
            "arkit_available": ARWorldTrackingConfiguration.isSupported,
            "vision_available": true
        ]
        result(capabilities)
    }
    
    private func handleDispose(_ result: @escaping FlutterResult) {
        eyeTracker?.dispose()
        eyeTracker = nil
        cameraManager = nil
        
        gazeEventSink = nil
        eyeStateEventSink = nil
        headPoseEventSink = nil
        faceDetectionEventSink = nil
        
        result(true)
    }
}
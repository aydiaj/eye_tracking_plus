import Flutter
import UIKit
import AVFoundation
import Vision
import ARKit

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
    
    // MARK: - Plugin Registration
    public static func register(with registrar: FlutterPluginRegistrar) {
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
        
        // Set up event channel stream handlers
        gazeEventChannel.setStreamHandler(GazeStreamHandler(plugin: instance))
        eyeStateEventChannel.setStreamHandler(EyeStateStreamHandler(plugin: instance))
        headPoseEventChannel.setStreamHandler(HeadPoseStreamHandler(plugin: instance))
        faceDetectionEventChannel.setStreamHandler(FaceDetectionStreamHandler(plugin: instance))
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
        switch call.method {
        case "getPlatformVersion":
            result("iOS " + UIDevice.current.systemVersion)
            
        case "initialize":
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
        self.gazeEventSink = eventSink
        eyeTracker?.setGazeDataCallback { [weak self] gazeData in
            self?.gazeEventSink?(gazeData.toDictionary())
        }
    }
    
    func setEyeStateEventSink(_ eventSink: FlutterEventSink?) {
        self.eyeStateEventSink = eventSink
        eyeTracker?.setEyeStateCallback { [weak self] eyeState in
            self?.eyeStateEventSink?(eyeState.toDictionary())
        }
    }
    
    func setHeadPoseEventSink(_ eventSink: FlutterEventSink?) {
        self.headPoseEventSink = eventSink
        eyeTracker?.setHeadPoseCallback { [weak self] headPose in
            self?.headPoseEventSink?(headPose.toDictionary())
        }
    }
    
    func setFaceDetectionEventSink(_ eventSink: FlutterEventSink?) {
        self.faceDetectionEventSink = eventSink
        eyeTracker?.setFaceDetectionCallback { [weak self] faces in
            let faceDictionaries = faces.map { $0.toDictionary() }
            self?.faceDetectionEventSink?(faceDictionaries)
        }
    }
}

// MARK: - Method Implementations
extension EyeTrackingPlugin {
    
    private func handleInitialize(_ result: @escaping FlutterResult) {
        cameraManager = CameraManager()
        eyeTracker = EyeTracker(cameraManager: cameraManager!)
        
        let success = eyeTracker?.initialize() ?? false
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
        let success = eyeTracker?.startTracking() ?? false
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
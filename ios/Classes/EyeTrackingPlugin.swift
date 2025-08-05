import Flutter
import UIKit
import AVFoundation

public class EyeTrackingPlugin: NSObject, FlutterPlugin {
    
    private var methodChannel: FlutterMethodChannel?
    private var eventChannel: FlutterEventChannel?
    private var eventSink: FlutterEventSink?
    
    // Plugin state
    private var isInitialized = false
    private var isTracking = false
    private var hasPermission = false
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "eye_tracking", binaryMessenger: registrar.messenger())
        let instance = EyeTrackingPlugin()
        
        instance.methodChannel = channel
        registrar.addMethodCallDelegate(instance, channel: channel)
        
        // Setup event channel for streaming data
        let eventChannel = FlutterEventChannel(name: "eye_tracking/gaze", binaryMessenger: registrar.messenger())
        instance.eventChannel = eventChannel
        eventChannel.setStreamHandler(instance)
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getPlatformVersion":
            result("iOS " + UIDevice.current.systemVersion)
            
        case "initialize":
            initialize(result: result)
            
        case "requestCameraPermission":
            requestCameraPermission(result: result)
            
        case "hasCameraPermission":
            result(hasCameraPermission())
            
        case "getState":
            result(getCurrentState())
            
        case "startTracking":
            startTracking(result: result)
            
        case "stopTracking":
            stopTracking(result: result)
            
        case "pauseTracking":
            pauseTracking(result: result)
            
        case "resumeTracking":
            resumeTracking(result: result)
            
        case "startCalibration":
            startCalibration(call: call, result: result)
            
        case "addCalibrationPoint":
            addCalibrationPoint(call: call, result: result)
            
        case "finishCalibration":
            finishCalibration(result: result)
            
        case "clearCalibration":
            clearCalibration(result: result)
            
        case "getCalibrationAccuracy":
            getCalibrationAccuracy(result: result)
            
        case "setTrackingFrequency":
            setTrackingFrequency(call: call, result: result)
            
        case "setAccuracyMode":
            setAccuracyMode(call: call, result: result)
            
        case "enableBackgroundTracking":
            enableBackgroundTracking(call: call, result: result)
            
        case "getCapabilities":
            getCapabilities(result: result)
            
        case "dispose":
            dispose(result: result)
            
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    // MARK: - Implementation Methods
    
    private func initialize(result: @escaping FlutterResult) {
        // Initialize eye tracking framework
        isInitialized = true
        result(true)
    }
    
    private func requestCameraPermission(result: @escaping FlutterResult) {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                self.hasPermission = granted
                result(granted)
            }
        }
    }
    
    private func hasCameraPermission() -> Bool {
        return AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    }
    
    private func getCurrentState() -> String {
        if !isInitialized {
            return "uninitialized"
        } else if isTracking {
            return "tracking"
        } else {
            return "ready"
        }
    }
    
    private func startTracking(result: @escaping FlutterResult) {
        guard isInitialized && hasCameraPermission() else {
            result(false)
            return
        }
        
        // Start eye tracking
        isTracking = true
        result(true)
    }
    
    private func stopTracking(result: @escaping FlutterResult) {
        isTracking = false
        result(true)
    }
    
    private func pauseTracking(result: @escaping FlutterResult) {
        guard isTracking else {
            result(false)
            return
        }
        
        // Pause tracking logic
        result(true)
    }
    
    private func resumeTracking(result: @escaping FlutterResult) {
        // Resume tracking logic
        result(true)
    }
    
    private func startCalibration(call: FlutterMethodCall, result: @escaping FlutterResult) {
        // Start calibration process
        result(true)
    }
    
    private func addCalibrationPoint(call: FlutterMethodCall, result: @escaping FlutterResult) {
        // Add calibration point
        result(true)
    }
    
    private func finishCalibration(result: @escaping FlutterResult) {
        // Finish calibration
        result(true)
    }
    
    private func clearCalibration(result: @escaping FlutterResult) {
        // Clear calibration
        result(true)
    }
    
    private func getCalibrationAccuracy(result: @escaping FlutterResult) {
        // Return calibration accuracy
        result(0.85)
    }
    
    private func setTrackingFrequency(call: FlutterMethodCall, result: @escaping FlutterResult) {
        // Set tracking frequency
        result(true)
    }
    
    private func setAccuracyMode(call: FlutterMethodCall, result: @escaping FlutterResult) {
        // Set accuracy mode
        result(true)
    }
    
    private func enableBackgroundTracking(call: FlutterMethodCall, result: @escaping FlutterResult) {
        // Enable/disable background tracking
        result(true)
    }
    
    private func getCapabilities(result: @escaping FlutterResult) {
        let capabilities: [String: Any] = [
            "platform": "ios",
            "hasCamera": true,
            "hasFrontCamera": UIImagePickerController.isCameraDeviceAvailable(.front),
            "supportsEyeTracking": true,
            "supportsHeadPose": true,
            "supportsFaceDetection": true,
            "supportsCalibration": true,
            "maxTrackingFrequency": 60,
        ]
        result(capabilities)
    }
    
    private func dispose(result: @escaping FlutterResult) {
        isTracking = false
        isInitialized = false
        eventSink = nil
        result(true)
    }
}

// MARK: - FlutterStreamHandler

extension EyeTrackingPlugin: FlutterStreamHandler {
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        return nil
    }
    
    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        return nil
    }
}
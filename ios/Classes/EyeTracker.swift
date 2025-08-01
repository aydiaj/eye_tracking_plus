import Foundation
import AVFoundation
import Vision
import ARKit
import CoreML
import Darwin.Mach

class EyeTracker: NSObject {
    
    // MARK: - Properties
    private let cameraManager: CameraManager
    private let faceDetector: FaceDetector
    private let gazeProcessor: GazeProcessor
    private let calibrationManager: CalibrationManager
    
    // State management
    private var currentState: EyeTrackingState = .uninitialized
    private var configuration: TrackingConfiguration
    
    // Threading
    private let processingQueue: DispatchQueue
    private let callbackQueue: DispatchQueue
    
    // Performance tracking
    private var lastFrameTime: CFTimeInterval = 0
    private var frameCount: Int = 0
    private var droppedFrames: Int = 0
    
    // Data callbacks
    private var gazeDataCallback: ((GazeData) -> Void)?
    private var eyeStateCallback: ((EyeState) -> Void)?
    private var headPoseCallback: ((HeadPose) -> Void)?
    private var faceDetectionCallback: (([FaceDetection]) -> Void)?
    
    // MARK: - Initialization
    init(cameraManager: CameraManager) {
        self.cameraManager = cameraManager
        self.faceDetector = FaceDetector()
        self.gazeProcessor = GazeProcessor()
        self.calibrationManager = CalibrationManager()
        
        self.configuration = TrackingConfiguration(
            targetFPS: 30,
            accuracyMode: .medium,
            enableBackgroundTracking: false
        )
        
        self.processingQueue = DispatchQueue(label: "eyetracker.processing", qos: .userInitiated)
        self.callbackQueue = DispatchQueue.main
        
        super.init()
        
        // Set camera delegate
        cameraManager.delegate = self
        
        // Configure face detector delegate
        faceDetector.delegate = self
    }
    
    // MARK: - Public Interface
    func initialize() -> Bool {
        guard currentState == .uninitialized else { return true }
        
        // Setup camera
        guard cameraManager.setupCaptureSession() else {
            currentState = .error
            return false
        }
        
        // Initialize face detector
        guard faceDetector.initialize() else {
            currentState = .error
            return false
        }
        
        // Initialize gaze processor
        guard gazeProcessor.initialize() else {
            currentState = .error
            return false
        }
        
        currentState = .ready
        print("✅ EyeTracker initialized successfully")
        return true
    }
    
    func startTracking() -> Bool {
        guard currentState == .ready || currentState == .paused else {
            print("❌ Cannot start tracking from state: \(currentState)")
            return false
        }
        
        // Configure camera frame rate
        cameraManager.setFrameRate(configuration.targetFPS)
        
        // Start camera session
        cameraManager.startSession()
        
        // Reset performance counters
        lastFrameTime = CACurrentMediaTime()
        frameCount = 0
        droppedFrames = 0
        
        currentState = .tracking
        print("✅ Eye tracking started")
        return true
    }
    
    func stopTracking() -> Bool {
        guard currentState == .tracking || currentState == .paused else { return false }
        
        cameraManager.stopSession()
        currentState = .ready
        print("🛑 Eye tracking stopped")
        return true
    }
    
    func pauseTracking() -> Bool {
        guard currentState == .tracking else { return false }
        
        cameraManager.stopSession()
        currentState = .paused
        print("⏸ Eye tracking paused")
        return true
    }
    
    func resumeTracking() -> Bool {
        guard currentState == .paused else { return false }
        
        cameraManager.startSession()
        currentState = .tracking
        print("▶️ Eye tracking resumed")
        return true
    }
    
    // MARK: - Calibration
    func startCalibration(with points: [CalibrationPoint]) -> Bool {
        return calibrationManager.startCalibration(with: points)
    }
    
    func addCalibrationPoint(_ point: CalibrationPoint) -> Bool {
        // Collect current gaze data for calibration
        return calibrationManager.addCalibrationPoint(point)
    }
    
    func finishCalibration() -> Bool {
        let success = calibrationManager.finishCalibration()
        if success {
            // Apply calibration to gaze processor
            if let transform = calibrationManager.getCalibrationTransform() {
                gazeProcessor.setCalibrationTransform(transform)
            }
        }
        return success
    }
    
    func clearCalibration() -> Bool {
        let success = calibrationManager.clearCalibration()
        if success {
            gazeProcessor.clearCalibrationTransform()
        }
        return success
    }
    
    func getCalibrationAccuracy() -> Double {
        return calibrationManager.getAccuracy()
    }
    
    // MARK: - Configuration
    func setTrackingFrequency(_ fps: Int) -> Bool {
        guard fps > 0 && fps <= 60 else { return false }
        
        configuration = TrackingConfiguration(
            targetFPS: fps,
            accuracyMode: configuration.accuracyMode,
            enableBackgroundTracking: configuration.enableBackgroundTracking
        )
        
        return cameraManager.setFrameRate(fps)
    }
    
    func setAccuracyMode(_ mode: String) -> Bool {
        guard let accuracyMode = TrackingConfiguration.AccuracyMode(rawValue: mode) else { return false }
        
        configuration = TrackingConfiguration(
            targetFPS: configuration.targetFPS,
            accuracyMode: accuracyMode,
            enableBackgroundTracking: configuration.enableBackgroundTracking
        )
        
        // Configure processing quality
        faceDetector.setProcessingQuality(accuracyMode.processingQuality)
        gazeProcessor.setAccuracyMode(accuracyMode)
        
        return true
    }
    
    func enableBackgroundTracking(_ enable: Bool) -> Bool {
        configuration = TrackingConfiguration(
            targetFPS: configuration.targetFPS,
            accuracyMode: configuration.accuracyMode,
            enableBackgroundTracking: enable
        )
        
        // Background tracking implementation would go here
        // For now, just store the preference
        return true
    }
    
    // MARK: - State and Data
    func getCurrentState() -> EyeTrackingState {
        return currentState
    }
    
    func getTrackingStatistics() -> TrackingStatistics {
        let currentTime = CACurrentMediaTime()
        let totalTime = currentTime - lastFrameTime
        let averageFPS = totalTime > 0 ? Double(frameCount) / totalTime : 0
        
        return TrackingStatistics(
            averageFPS: averageFPS,
            droppedFrames: droppedFrames,
            processingTime: totalTime,
            memoryUsage: getCurrentMemoryUsage()
        )
    }
    
    private func getCurrentMemoryUsage() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            return Double(info.resident_size) / 1024.0 / 1024.0 // MB
        }
        
        return 0.0
    }
    
    // MARK: - Callbacks
    func setGazeDataCallback(_ callback: @escaping (GazeData) -> Void) {
        gazeDataCallback = callback
    }
    
    func setEyeStateCallback(_ callback: @escaping (EyeState) -> Void) {
        eyeStateCallback = callback
    }
    
    func setHeadPoseCallback(_ callback: @escaping (HeadPose) -> Void) {
        headPoseCallback = callback
    }
    
    func setFaceDetectionCallback(_ callback: @escaping ([FaceDetection]) -> Void) {
        faceDetectionCallback = callback
    }
    
    // MARK: - Cleanup
    func dispose() {
        stopTracking()
        
        gazeDataCallback = nil
        eyeStateCallback = nil
        headPoseCallback = nil
        faceDetectionCallback = nil
        
        faceDetector.cleanup()
        gazeProcessor.cleanup()
        
        print("🗑 EyeTracker disposed")
    }
}

// MARK: - CameraManagerDelegate
extension EyeTracker: CameraManagerDelegate {
    
    func cameraManager(_ manager: CameraManager, didOutput sampleBuffer: CMSampleBuffer) {
        guard currentState == .tracking else { return }
        
        processingQueue.async { [weak self] in
            self?.processVideoFrame(sampleBuffer)
        }
    }
    
    func cameraManager(_ manager: CameraManager, didFailWithError error: Error) {
        print("❌ Camera error: \(error)")
        currentState = .error
    }
    
    private func processVideoFrame(_ sampleBuffer: CMSampleBuffer) {
        let startTime = CACurrentMediaTime()
        
        // Extract pixel buffer
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            droppedFrames += 1
            return
        }
        
        // Process frame through face detector
        faceDetector.processFrame(pixelBuffer)
        
        // Update performance counters
        frameCount += 1
        let processingTime = CACurrentMediaTime() - startTime
        
        // Log performance occasionally
        if frameCount % 300 == 0 { // Every 10 seconds at 30 FPS
            let stats = getTrackingStatistics()
            print("📊 FPS: \(String(format: "%.1f", stats.averageFPS)), Processing: \(String(format: "%.1f", processingTime * 1000))ms, Memory: \(String(format: "%.1f", stats.memoryUsage))MB")
        }
    }
}

// MARK: - FaceDetectorDelegate
extension EyeTracker: FaceDetectorDelegate {
    
    func faceDetector(_ detector: FaceDetector, didDetectFaces faces: [FaceDetection]) {
        callbackQueue.async { [weak self] in
            self?.faceDetectionCallback?(faces)
        }
    }
    
    func faceDetector(_ detector: FaceDetector, didUpdateHeadPose headPose: HeadPose) {
        callbackQueue.async { [weak self] in
            self?.headPoseCallback?(headPose)
        }
    }
    
    func faceDetector(_ detector: FaceDetector, didUpdateEyeState eyeState: EyeState) {
        callbackQueue.async { [weak self] in
            self?.eyeStateCallback?(eyeState)
        }
    }
    
    func faceDetector(_ detector: FaceDetector, didDetectEyeLandmarks landmarks: EyeLandmarks, headPose: HeadPose) {
        // Process gaze estimation
        if let gazeData = gazeProcessor.estimateGaze(from: landmarks, headPose: headPose) {
            // Add to calibration if currently calibrating
            if calibrationManager.isCalibrating {
                calibrationManager.addGazeSample(gazeData)
            }
            
            callbackQueue.async { [weak self] in
                self?.gazeDataCallback?(gazeData)
            }
        }
    }
}
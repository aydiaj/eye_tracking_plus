import AVFoundation
import UIKit
import VideoToolbox

protocol CameraManagerDelegate: AnyObject {
    func cameraManager(_ manager: CameraManager, didOutput sampleBuffer: CMSampleBuffer)
    func cameraManager(_ manager: CameraManager, didFailWithError error: Error)
}

class CameraManager: NSObject {
    
    // MARK: - Properties
    weak var delegate: CameraManagerDelegate?
    
    private var captureSession: AVCaptureSession?
    private var frontCamera: AVCaptureDevice?
    private var videoDataOutput: AVCaptureVideoDataOutput?
    private var sessionQueue: DispatchQueue
    
    private var isConfigured = false
    private var isSessionRunning = false
    
    // Configuration
    private var targetFrameRate: Int = 30
    private var sessionPreset: AVCaptureSession.Preset = .vga640x480
    
    // MARK: - Initialization
    override init() {
        self.sessionQueue = DispatchQueue(label: "camera.session.queue", qos: .userInitiated)
        super.init()
    }
    
    deinit {
        stopSession()
    }
    
    // MARK: - Permission Management
    static func requestCameraPermission(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                completion(granted)
            }
        case .denied, .restricted:
            completion(false)
        @unknown default:
            completion(false)
        }
    }
    
    static func hasCameraPermission() -> Bool {
        return AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    }
    
    // MARK: - Session Management
    func setupCaptureSession() -> Bool {
        guard !isConfigured else { return true }
        
        var success = false
        
        sessionQueue.sync {
            success = self.configureCaptureSession()
        }
        
        return success
    }
    
    private func configureCaptureSession() -> Bool {
        guard CameraManager.hasCameraPermission() else {
            print("❌ Camera permission not granted")
            return false
        }
        
        // Create capture session
        let captureSession = AVCaptureSession()
        captureSession.sessionPreset = sessionPreset
        
        // Configure front camera
        guard let frontCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            print("❌ Front camera not available")
            return false
        }
        
        // Create camera input
        do {
            let cameraInput = try AVCaptureDeviceInput(device: frontCamera)
            
            if captureSession.canAddInput(cameraInput) {
                captureSession.addInput(cameraInput)
            } else {
                print("❌ Cannot add camera input to session")
                return false
            }
        } catch {
            print("❌ Error creating camera input: \(error)")
            return false
        }
        
        // Configure video data output
        let videoDataOutput = AVCaptureVideoDataOutput()
        videoDataOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoDataOutput.setSampleBufferDelegate(self, queue: sessionQueue)
        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        
        if captureSession.canAddOutput(videoDataOutput) {
            captureSession.addOutput(videoDataOutput)
        } else {
            print("❌ Cannot add video output to session")
            return false
        }
        
        // Configure video connection
        if let connection = videoDataOutput.connection(with: .video) {
            if connection.isVideoStabilizationSupported {
                connection.preferredVideoStabilizationMode = .auto
            }
            if connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
            }
            if connection.isVideoMirroringSupported {
                connection.isVideoMirrored = true
            }
        }
        
        // Configure camera settings
        configureCameraSettings(frontCamera)
        
        // Store references
        self.captureSession = captureSession
        self.frontCamera = frontCamera
        self.videoDataOutput = videoDataOutput
        self.isConfigured = true
        
        print("✅ Camera session configured successfully")
        return true
    }
    
    private func configureCameraSettings(_ camera: AVCaptureDevice) {
        do {
            try camera.lockForConfiguration()
            
            // Set frame rate
            if let format = findOptimalFormat(for: camera) {
                camera.activeFormat = format
                
                let frameDuration = CMTime(value: 1, timescale: CMTimeScale(targetFrameRate))
                camera.activeVideoMinFrameDuration = frameDuration
                camera.activeVideoMaxFrameDuration = frameDuration
            }
            
            // Configure focus for close-up eye tracking
            if camera.isFocusModeSupported(.continuousAutoFocus) {
                camera.focusMode = .continuousAutoFocus
            }
            
            // Configure exposure
            if camera.isExposureModeSupported(.continuousAutoExposure) {
                camera.exposureMode = .continuousAutoExposure
            }
            
            // Disable low light boost for consistent lighting
            if camera.isLowLightBoostSupported {
                camera.automaticallyEnablesLowLightBoostWhenAvailable = false
            }
            
            camera.unlockForConfiguration()
            
        } catch {
            print("❌ Error configuring camera: \(error)")
        }
    }
    
    private func findOptimalFormat(for device: AVCaptureDevice) -> AVCaptureDevice.Format? {
        var bestFormat: AVCaptureDevice.Format?
        var bestFrameRate: Double = 0
        
        for format in device.formats {
            let description = format.formatDescription
            let dimensions = CMVideoFormatDescriptionGetDimensions(description)
            
            // Prefer 640x480 resolution for eye tracking performance
            guard dimensions.width == 640 && dimensions.height == 480 else { continue }
            
            for range in format.videoSupportedFrameRateRanges {
                if range.maxFrameRate >= Double(targetFrameRate) && range.maxFrameRate > bestFrameRate {
                    bestFormat = format
                    bestFrameRate = range.maxFrameRate
                }
            }
        }
        
        return bestFormat
    }
    
    func startSession() {
        guard isConfigured, let captureSession = captureSession else {
            print("❌ Camera session not configured")
            return
        }
        
        sessionQueue.async {
            if !self.isSessionRunning {
                captureSession.startRunning()
                self.isSessionRunning = captureSession.isRunning
                print("✅ Camera session started")
            }
        }
    }
    
    func stopSession() {
        guard let captureSession = captureSession else { return }
        
        sessionQueue.async {
            if self.isSessionRunning {
                captureSession.stopRunning()
                self.isSessionRunning = false
                print("🛑 Camera session stopped")
            }
        }
    }
    
    // MARK: - Configuration
    func setFrameRate(_ fps: Int) -> Bool {
        guard let camera = frontCamera, fps > 0 && fps <= 60 else { return false }
        
        targetFrameRate = fps
        
        do {
            try camera.lockForConfiguration()
            
            let frameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))
            camera.activeVideoMinFrameDuration = frameDuration
            camera.activeVideoMaxFrameDuration = frameDuration
            
            camera.unlockForConfiguration()
            print("✅ Frame rate set to \(fps) FPS")
            return true
        } catch {
            print("❌ Error setting frame rate: \(error)")
            return false
        }
    }
    
    func setSessionPreset(_ preset: AVCaptureSession.Preset) -> Bool {
        guard let captureSession = captureSession else { return false }
        
        sessionQueue.sync {
            if captureSession.canSetSessionPreset(preset) {
                captureSession.sessionPreset = preset
                self.sessionPreset = preset
                print("✅ Session preset set to \(preset.rawValue)")
            }
        }
        
        return true
    }
    
    // MARK: - Status
    var isRunning: Bool {
        return isSessionRunning
    }
    
    var currentFrameRate: Double {
        guard let camera = frontCamera else { return 0 }
        let frameDuration = camera.activeVideoMinFrameDuration
        return frameDuration.isValid ? Double(frameDuration.timescale) / Double(frameDuration.value) : 0
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Forward the sample buffer to the delegate
        delegate?.cameraManager(self, didOutput: sampleBuffer)
    }
    
    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Handle dropped frames if needed
        print("⚠️ Frame dropped")
    }
}
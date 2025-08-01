import Foundation
import Vision
import ARKit
import CoreML
import AVFoundation

protocol FaceDetectorDelegate: AnyObject {
    func faceDetector(_ detector: FaceDetector, didDetectFaces faces: [FaceDetection])
    func faceDetector(_ detector: FaceDetector, didUpdateHeadPose headPose: HeadPose)
    func faceDetector(_ detector: FaceDetector, didUpdateEyeState eyeState: EyeState)
    func faceDetector(_ detector: FaceDetector, didDetectEyeLandmarks landmarks: EyeLandmarks, headPose: HeadPose)
}

class FaceDetector: NSObject {
    
    // MARK: - Properties
    weak var delegate: FaceDetectorDelegate?
    
    // Vision requests
    private var faceDetectionRequest: VNDetectFaceLandmarksRequest?
    private var faceTrackingRequest: VNTrackObjectRequest?
    
    // ARKit session (optional, for enhanced head pose)
    private var arSession: ARSession?
    private var useARKit: Bool = false
    
    // Processing configuration
    private var processingQuality: Float = 0.6
    private var isInitialized = false
    
    // Face tracking state
    private var trackedFaces: [String: TrackedFace] = [:]
    private var lastDetectionTime: CFTimeInterval = 0
    
    // Eye state detection
    private var eyeStateTracker: EyeStateTracker
    
    // MARK: - Initialization
    override init() {
        self.eyeStateTracker = EyeStateTracker()
        super.init()
    }
    
    func initialize() -> Bool {
        guard !isInitialized else { return true }
        
        setupVisionRequests()
        setupARKitIfAvailable()
        
        isInitialized = true
        print("✅ FaceDetector initialized")
        return true
    }
    
    private func setupVisionRequests() {
        // Create face landmarks detection request
        faceDetectionRequest = VNDetectFaceLandmarksRequest { [weak self] request, error in
            self?.handleFaceDetectionResults(request: request, error: error)
        }
        
        // Configure for high-quality detection
        faceDetectionRequest?.revision = VNDetectFaceLandmarksRequestRevision3
        faceDetectionRequest?.preferBackgroundProcessing = false
    }
    
    private func setupARKitIfAvailable() {
        // Check if ARKit face tracking is supported
        guard ARFaceTrackingConfiguration.isSupported else {
            print("ℹ️ ARKit face tracking not supported, using Vision only")
            return
        }
        
        // Setup ARKit session
        let arSession = ARSession()
        let configuration = ARFaceTrackingConfiguration()
        configuration.maximumNumberOfTrackedFaces = 1
        configuration.isLightEstimationEnabled = false
        
        self.arSession = arSession
        self.useARKit = true
        
        print("✅ ARKit face tracking enabled")
    }
    
    // MARK: - Processing
    func processFrame(_ pixelBuffer: CVPixelBuffer) {
        let currentTime = CACurrentMediaTime()
        
        // Throttle processing based on quality setting
        let minInterval = 1.0 / (30.0 * Double(processingQuality))
        guard currentTime - lastDetectionTime >= minInterval else { return }
        
        lastDetectionTime = currentTime
        
        if useARKit {
            processFrameWithARKit(pixelBuffer)
        } else {
            processFrameWithVision(pixelBuffer)
        }
    }
    
    private func processFrameWithVision(_ pixelBuffer: CVPixelBuffer) {
        guard let request = faceDetectionRequest else { return }
        
        let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        
        do {
            try imageRequestHandler.perform([request])
        } catch {
            print("❌ Vision face detection error: \(error)")
        }
    }
    
    private func processFrameWithARKit(_ pixelBuffer: CVPixelBuffer) {
        // ARKit processing would be implemented here
        // For now, fall back to Vision
        processFrameWithVision(pixelBuffer)
    }
    
    // MARK: - Vision Results Handling
    private func handleFaceDetectionResults(request: VNRequest, error: Error?) {
        guard let observations = request.results as? [VNFaceObservation] else {
            if let error = error {
                print("❌ Face detection error: \(error)")
            }
            return
        }
        
        let currentTime = Date().timeIntervalSince1970 * 1000
        var detectedFaces: [FaceDetection] = []
        
        for (index, observation) in observations.enumerated() {
            let faceId = "face_\(index)"
            
            // Create face detection result
            let boundingBox = observation.boundingBox
            let faceDetection = FaceDetection(
                faceId: faceId,
                boundingBox: boundingBox,
                confidence: Double(observation.confidence),
                landmarks: [],
                timestamp: currentTime
            )
            
            detectedFaces.append(faceDetection)
            
            // Process landmarks if available
            if let landmarks = observation.landmarks {
                processLandmarks(landmarks, for: faceId, in: observation)
            }
        }
        
        // Notify delegate
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.faceDetector(self, didDetectFaces: detectedFaces)
        }
    }
    
    private func processLandmarks(_ landmarks: VNFaceLandmarks2D, for faceId: String, in observation: VNFaceObservation) {
        // Extract eye landmarks
        guard let leftEye = landmarks.leftEye,
              let rightEye = landmarks.rightEye else { return }
        
        let leftEyePoints = leftEye.normalizedPoints.map { CGPoint(x: $0.x, y: $0.y) }
        let rightEyePoints = rightEye.normalizedPoints.map { CGPoint(x: $0.x, y: $0.y) }
        
        // Estimate pupil positions (center of eye regions)
        let leftPupil = calculateEyeCenter(leftEyePoints)
        let rightPupil = calculateEyeCenter(rightEyePoints)
        
        let eyeLandmarks = EyeLandmarks(
            leftEye: leftEyePoints,
            rightEye: rightEyePoints,
            leftPupil: leftPupil,
            rightPupil: rightPupil
        )
        
        // Estimate head pose from face landmarks
        let headPose = estimateHeadPose(from: landmarks, observation: observation)
        
        // Detect eye state
        let eyeState = eyeStateTracker.detectEyeState(from: eyeLandmarks)
        
        // Notify delegate
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.faceDetector(self, didUpdateHeadPose: headPose)
            self.delegate?.faceDetector(self, didUpdateEyeState: eyeState)
            self.delegate?.faceDetector(self, didDetectEyeLandmarks: eyeLandmarks, headPose: headPose)
        }
    }
    
    // MARK: - Landmark Processing Utilities
    private func calculateEyeCenter(_ eyePoints: [CGPoint]) -> CGPoint {
        guard !eyePoints.isEmpty else { return CGPoint.zero }
        
        let sumX = eyePoints.reduce(0) { $0 + $1.x }
        let sumY = eyePoints.reduce(0) { $0 + $1.y }
        
        return CGPoint(x: sumX / CGFloat(eyePoints.count), y: sumY / CGFloat(eyePoints.count))
    }
    
    private func estimateHeadPose(from landmarks: VNFaceLandmarks2D, observation: VNFaceObservation) -> HeadPose {
        // Simple head pose estimation from face landmarks
        // This could be enhanced with more sophisticated 3D pose estimation
        
        var pitch: Double = 0
        var yaw: Double = 0
        var roll: Double = 0
        
        // Estimate yaw from face asymmetry
        if let leftEye = landmarks.leftEye, let rightEye = landmarks.rightEye {
            let leftEyeCenter = calculateEyeCenter(leftEye.normalizedPoints.map { CGPoint(x: $0.x, y: $0.y) })
            let rightEyeCenter = calculateEyeCenter(rightEye.normalizedPoints.map { CGPoint(x: $0.x, y: $0.y) })
            
            // Calculate roll from eye alignment
            let eyeAngle = atan2(rightEyeCenter.y - leftEyeCenter.y, rightEyeCenter.x - leftEyeCenter.x)
            roll = Double(eyeAngle) * 180.0 / .pi
            
            // Estimate yaw from eye distance ratio
            let faceCenter = CGPoint(x: observation.boundingBox.midX, y: observation.boundingBox.midY)
            let leftDistance = distance(leftEyeCenter, faceCenter)
            let rightDistance = distance(rightEyeCenter, faceCenter)
            let asymmetry = (leftDistance - rightDistance) / (leftDistance + rightDistance)
            yaw = Double(asymmetry) * 45.0 // Scale to reasonable range
        }
        
        // Estimate pitch from vertical face features
        if let nose = landmarks.nose, let mouth = landmarks.outerLips {
            let nosePoints = nose.normalizedPoints.map { CGPoint(x: $0.x, y: $0.y) }
            let mouthPoints = mouth.normalizedPoints.map { CGPoint(x: $0.x, y: $0.y) }
            
            if let noseCenter = nosePoints.first, let mouthCenter = mouthPoints.first {
                let verticalDistance = abs(noseCenter.y - mouthCenter.y)
                pitch = Double(verticalDistance - 0.1) * 90.0 // Approximate pitch
            }
        }
        
        return HeadPose(
            pitch: pitch,
            yaw: yaw,
            roll: roll,
            confidence: Double(observation.confidence),
            timestamp: Date().timeIntervalSince1970 * 1000
        )
    }
    
    private func distance(_ point1: CGPoint, _ point2: CGPoint) -> CGFloat {
        let dx = point1.x - point2.x
        let dy = point1.y - point2.y
        return sqrt(dx * dx + dy * dy)
    }
    
    // MARK: - Configuration
    func setProcessingQuality(_ quality: Float) {
        processingQuality = max(0.1, min(1.0, quality))
        print("🎛 Face detection quality set to \(processingQuality)")
    }
    
    // MARK: - Cleanup
    func cleanup() {
        arSession?.pause()
        arSession = nil
        trackedFaces.removeAll()
        isInitialized = false
        print("🗑 FaceDetector cleaned up")
    }
}

// MARK: - Tracked Face Data Structure
private struct TrackedFace {
    let id: String
    let observation: VNFaceObservation
    let lastSeen: CFTimeInterval
}

// MARK: - Eye State Tracker
private class EyeStateTracker {
    
    // Eye state detection parameters
    private let blinkThreshold: CGFloat = 0.3
    private let openThreshold: CGFloat = 0.7
    
    // Blink detection state
    private var leftEyeHistory: [Bool] = []
    private var rightEyeHistory: [Bool] = []
    private let historySize = 5
    
    func detectEyeState(from landmarks: EyeLandmarks) -> EyeState {
        let leftEyeOpenness = calculateEyeOpenness(landmarks.leftEye)
        let rightEyeOpenness = calculateEyeOpenness(landmarks.rightEye)
        
        let leftEyeOpen = leftEyeOpenness > openThreshold
        let rightEyeOpen = rightEyeOpenness > openThreshold
        
        // Update blink history
        leftEyeHistory.append(leftEyeOpen)
        rightEyeHistory.append(rightEyeOpen)
        
        if leftEyeHistory.count > historySize {
            leftEyeHistory.removeFirst()
        }
        if rightEyeHistory.count > historySize {
            rightEyeHistory.removeFirst()
        }
        
        // Detect blinks (closed -> open transition)
        let leftEyeBlink = detectBlink(in: leftEyeHistory)
        let rightEyeBlink = detectBlink(in: rightEyeHistory)
        
        return EyeState(
            leftEyeOpen: leftEyeOpen,
            rightEyeOpen: rightEyeOpen,
            leftEyeBlink: leftEyeBlink,
            rightEyeBlink: rightEyeBlink,
            timestamp: Date().timeIntervalSince1970 * 1000
        )
    }
    
    private func calculateEyeOpenness(_ eyePoints: [CGPoint]) -> CGFloat {
        guard eyePoints.count >= 6 else { return 1.0 }
        
        // Calculate eye aspect ratio (height/width)
        let p1 = eyePoints[1] // Top of eye
        let p2 = eyePoints[5] // Bottom of eye
        let p3 = eyePoints[0] // Left corner
        let p4 = eyePoints[3] // Right corner
        
        let height = abs(p1.y - p2.y)
        let width = abs(p3.x - p4.x)
        
        return width > 0 ? height / width : 1.0
    }
    
    private func detectBlink(in history: [Bool]) -> Bool {
        guard history.count >= 3 else { return false }
        
        // Look for pattern: open -> closed -> open
        let recent = Array(history.suffix(3))
        return recent[0] && !recent[1] && recent[2]
    }
}
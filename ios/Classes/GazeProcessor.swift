import Foundation
import CoreGraphics
import simd
import Accelerate

class GazeProcessor: NSObject {
    
    // MARK: - Properties
    private var isInitialized = false
    private var calibrationTransform: CalibrationTransform?
    private var accuracyMode: TrackingConfiguration.AccuracyMode = .medium
    
    // Screen configuration
    private var screenSize: CGSize = CGSize(width: 1920, height: 1080)
    
    // Gaze estimation parameters
    private var gazeModel: GazeEstimationModel
    
    // Smoothing and filtering
    private var gazeHistory: [CGPoint] = []
    private let historySize = 5
    private var smoothingEnabled = true
    
    // Performance optimization
    private var lastProcessingTime: CFTimeInterval = 0
    
    // MARK: - Initialization
    override init() {
        self.gazeModel = GazeEstimationModel()
        super.init()
    }
    
    func initialize() -> Bool {
        guard !isInitialized else { return true }
        
        // Initialize gaze estimation model
        guard gazeModel.initialize() else {
            print("❌ Failed to initialize gaze estimation model")
            return false
        }
        
        // Update screen size from main screen
        DispatchQueue.main.sync {
            if let screen = UIScreen.main {
                screenSize = CGSize(width: screen.bounds.width * screen.scale, 
                                  height: screen.bounds.height * screen.scale)
            }
        }
        
        isInitialized = true
        print("✅ GazeProcessor initialized with screen size: \(screenSize)")
        return true
    }
    
    // MARK: - Gaze Estimation
    func estimateGaze(from eyeLandmarks: EyeLandmarks, headPose: HeadPose) -> GazeData? {
        let startTime = CACurrentMediaTime()
        
        // Extract features for gaze estimation
        let features = extractGazeFeatures(from: eyeLandmarks, headPose: headPose)
        
        // Estimate raw gaze point
        guard let rawGaze = gazeModel.estimateGaze(from: features) else {
            return nil
        }
        
        // Apply calibration transform if available
        let calibratedGaze = applyCalibration(to: rawGaze)
        
        // Convert to screen coordinates
        let screenGaze = convertToScreenCoordinates(calibratedGaze)
        
        // Apply smoothing
        let smoothedGaze = applySmoothingIfEnabled(to: screenGaze)
        
        // Calculate confidence
        let confidence = calculateGazeConfidence(features: features, rawGaze: rawGaze)
        
        let processingTime = CACurrentMediaTime() - startTime
        lastProcessingTime = processingTime
        
        return GazeData(
            x: Double(smoothedGaze.x),
            y: Double(smoothedGaze.y),
            confidence: confidence,
            timestamp: Date().timeIntervalSince1970 * 1000
        )
    }
    
    // MARK: - Feature Extraction
    private func extractGazeFeatures(from landmarks: EyeLandmarks, headPose: HeadPose) -> GazeFeatures {
        // Extract relevant features for gaze estimation
        let leftEyeFeatures = extractEyeFeatures(landmarks.leftEye, pupil: landmarks.leftPupil)
        let rightEyeFeatures = extractEyeFeatures(landmarks.rightEye, pupil: landmarks.rightPupil)
        
        return GazeFeatures(
            leftEyeFeatures: leftEyeFeatures,
            rightEyeFeatures: rightEyeFeatures,
            headPose: headPose,
            eyeDistance: distance(landmarks.leftEyeCenter, landmarks.rightEyeCenter)
        )
    }
    
    private func extractEyeFeatures(_ eyePoints: [CGPoint], pupil: CGPoint) -> EyeFeatures {
        guard eyePoints.count >= 6 else {
            return EyeFeatures(center: pupil, pupilOffset: CGPoint.zero, aspectRatio: 1.0, landmarks: eyePoints)
        }
        
        // Calculate eye center
        let eyeCenter = calculateCenter(of: eyePoints)
        
        // Calculate pupil offset from eye center
        let pupilOffset = CGPoint(x: pupil.x - eyeCenter.x, y: pupil.y - eyeCenter.y)
        
        // Calculate eye aspect ratio
        let aspectRatio = calculateEyeAspectRatio(eyePoints)
        
        return EyeFeatures(
            center: eyeCenter,
            pupilOffset: pupilOffset,
            aspectRatio: aspectRatio,
            landmarks: eyePoints
        )
    }
    
    // MARK: - Gaze Calculation Utilities
    private func calculateCenter(of points: [CGPoint]) -> CGPoint {
        guard !points.isEmpty else { return CGPoint.zero }
        
        let sumX = points.reduce(0) { $0 + $1.x }
        let sumY = points.reduce(0) { $0 + $1.y }
        
        return CGPoint(x: sumX / CGFloat(points.count), y: sumY / CGFloat(points.count))
    }
    
    private func calculateEyeAspectRatio(_ eyePoints: [CGPoint]) -> CGFloat {
        guard eyePoints.count >= 6 else { return 1.0 }
        
        // Calculate width (horizontal distance)
        let leftPoint = eyePoints[0]
        let rightPoint = eyePoints[3]
        let width = abs(rightPoint.x - leftPoint.x)
        
        // Calculate height (vertical distance)
        let topPoint = eyePoints[1]
        let bottomPoint = eyePoints[5]
        let height = abs(topPoint.y - bottomPoint.y)
        
        return width > 0 ? height / width : 1.0
    }
    
    private func distance(_ point1: CGPoint, _ point2: CGPoint) -> CGFloat {
        let dx = point1.x - point2.x
        let dy = point1.y - point2.y
        return sqrt(dx * dx + dy * dy)
    }
    
    // MARK: - Calibration
    func setCalibrationTransform(_ transform: CalibrationTransform) {
        self.calibrationTransform = transform
        print("✅ Calibration transform applied with accuracy: \(transform.accuracy)")
    }
    
    func clearCalibrationTransform() {
        self.calibrationTransform = nil
        print("🗑 Calibration transform cleared")
    }
    
    private func applyCalibration(to point: CGPoint) -> CGPoint {
        guard let transform = calibrationTransform else { return point }
        return transform.apply(to: point)
    }
    
    // MARK: - Coordinate Transformation
    private func convertToScreenCoordinates(_ point: CGPoint) -> CGPoint {
        // Convert normalized coordinates [0,1] to screen pixel coordinates
        return CGPoint(
            x: point.x * screenSize.width,
            y: point.y * screenSize.height
        )
    }
    
    // MARK: - Smoothing and Filtering
    private func applySmoothingIfEnabled(to point: CGPoint) -> CGPoint {
        guard smoothingEnabled else { return point }
        
        // Add to history
        gazeHistory.append(point)
        if gazeHistory.count > historySize {
            gazeHistory.removeFirst()
        }
        
        // Apply weighted moving average
        return calculateWeightedAverage(gazeHistory)
    }
    
    private func calculateWeightedAverage(_ points: [CGPoint]) -> CGPoint {
        guard !points.isEmpty else { return CGPoint.zero }
        
        var totalWeight: CGFloat = 0
        var weightedSumX: CGFloat = 0
        var weightedSumY: CGFloat = 0
        
        // Apply higher weights to more recent points
        for (index, point) in points.enumerated() {
            let weight = CGFloat(index + 1) / CGFloat(points.count)
            totalWeight += weight
            weightedSumX += point.x * weight
            weightedSumY += point.y * weight
        }
        
        return CGPoint(
            x: weightedSumX / totalWeight,
            y: weightedSumY / totalWeight
        )
    }
    
    // MARK: - Confidence Calculation
    private func calculateGazeConfidence(features: GazeFeatures, rawGaze: CGPoint) -> Double {
        var confidence: Double = 1.0
        
        // Reduce confidence based on head pose deviation
        let headPose = features.headPose
        let maxAngle = 30.0 // degrees
        let headPoseConfidence = 1.0 - (abs(headPose.pitch) + abs(headPose.yaw) + abs(headPose.roll)) / (3.0 * maxAngle)
        confidence *= max(0.0, headPoseConfidence)
        
        // Reduce confidence based on eye quality
        let leftEyeQuality = calculateEyeQuality(features.leftEyeFeatures)
        let rightEyeQuality = calculateEyeQuality(features.rightEyeFeatures)
        let averageEyeQuality = (leftEyeQuality + rightEyeQuality) / 2.0
        confidence *= averageEyeQuality
        
        // Apply base confidence from head pose estimation
        confidence *= headPose.confidence
        
        return max(0.0, min(1.0, confidence))
    }
    
    private func calculateEyeQuality(_ eyeFeatures: EyeFeatures) -> Double {
        // Quality based on eye aspect ratio (open eyes have higher ratio)
        let aspectRatio = Double(eyeFeatures.aspectRatio)
        let normalizedRatio = min(1.0, aspectRatio / 0.3) // 0.3 is typical open eye ratio
        
        return normalizedRatio
    }
    
    // MARK: - Configuration
    func setAccuracyMode(_ mode: TrackingConfiguration.AccuracyMode) {
        self.accuracyMode = mode
        
        // Adjust processing parameters based on accuracy mode
        switch mode {
        case .fast:
            smoothingEnabled = false
            gazeModel.setProcessingMode(.fast)
        case .medium:
            smoothingEnabled = true
            gazeModel.setProcessingMode(.medium)
        case .high:
            smoothingEnabled = true
            gazeModel.setProcessingMode(.high)
        }
        
        print("🎛 Gaze processor accuracy mode set to: \(mode.rawValue)")
    }
    
    func setSmoothingEnabled(_ enabled: Bool) {
        smoothingEnabled = enabled
        if !enabled {
            gazeHistory.removeAll()
        }
    }
    
    // MARK: - Cleanup
    func cleanup() {
        gazeHistory.removeAll()
        calibrationTransform = nil
        gazeModel.cleanup()
        isInitialized = false
        print("🗑 GazeProcessor cleaned up")
    }
}

// MARK: - Supporting Data Structures
struct GazeFeatures {
    let leftEyeFeatures: EyeFeatures
    let rightEyeFeatures: EyeFeatures
    let headPose: HeadPose
    let eyeDistance: CGFloat
}

struct EyeFeatures {
    let center: CGPoint
    let pupilOffset: CGPoint
    let aspectRatio: CGFloat
    let landmarks: [CGPoint]
}

// MARK: - Gaze Estimation Model
private class GazeEstimationModel {
    
    enum ProcessingMode {
        case fast, medium, high
    }
    
    private var processingMode: ProcessingMode = .medium
    
    func initialize() -> Bool {
        // Initialize the gaze estimation algorithm
        // This could load a CoreML model or initialize mathematical models
        print("✅ Gaze estimation model initialized")
        return true
    }
    
    func estimateGaze(from features: GazeFeatures) -> CGPoint? {
        // Implement gaze estimation algorithm
        // This is a simplified implementation - a real implementation would use
        // sophisticated machine learning models or geometric calculations
        
        let leftPupilOffset = features.leftEyeFeatures.pupilOffset
        let rightPupilOffset = features.rightEyeFeatures.pupilOffset
        
        // Average the pupil offsets and apply head pose compensation
        let averageOffsetX = (leftPupilOffset.x + rightPupilOffset.x) / 2.0
        let averageOffsetY = (leftPupilOffset.y + rightPupilOffset.y) / 2.0
        
        // Simple mapping from pupil offset to gaze coordinates
        // In a real implementation, this would be much more sophisticated
        let gazeX = 0.5 + (averageOffsetX * 2.0) // Scale and center
        let gazeY = 0.5 + (averageOffsetY * 2.0) // Scale and center
        
        // Apply head pose compensation
        let headPose = features.headPose
        let compensatedGazeX = gazeX - (headPose.yaw / 60.0) // Compensate for head yaw
        let compensatedGazeY = gazeY - (headPose.pitch / 60.0) // Compensate for head pitch
        
        return CGPoint(
            x: max(0.0, min(1.0, compensatedGazeX)),
            y: max(0.0, min(1.0, compensatedGazeY))
        )
    }
    
    func setProcessingMode(_ mode: ProcessingMode) {
        self.processingMode = mode
    }
    
    func cleanup() {
        // Cleanup model resources
    }
}
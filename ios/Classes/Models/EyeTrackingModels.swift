import Foundation
import CoreGraphics
import simd

// MARK: - Eye Tracking State
enum EyeTrackingState: String, CaseIterable {
    case uninitialized = "uninitialized"
    case ready = "ready"
    case tracking = "tracking"
    case paused = "paused"
    case error = "error"
}

// MARK: - Gaze Data
struct GazeData {
    let x: Double
    let y: Double
    let confidence: Double
    let timestamp: TimeInterval
    
    init(x: Double, y: Double, confidence: Double = 1.0, timestamp: TimeInterval = Date().timeIntervalSince1970 * 1000) {
        self.x = x
        self.y = y
        self.confidence = confidence
        self.timestamp = timestamp
    }
    
    func toDictionary() -> [String: Any] {
        return [
            "x": x,
            "y": y,
            "confidence": confidence,
            "timestamp": timestamp
        ]
    }
    
    static func fromDictionary(_ dict: [String: Any]) -> GazeData? {
        guard let x = dict["x"] as? Double,
              let y = dict["y"] as? Double else {
            return nil
        }
        
        let confidence = dict["confidence"] as? Double ?? 1.0
        let timestamp = dict["timestamp"] as? TimeInterval ?? Date().timeIntervalSince1970 * 1000
        
        return GazeData(x: x, y: y, confidence: confidence, timestamp: timestamp)
    }
}

// MARK: - Eye State
struct EyeState {
    let leftEyeOpen: Bool
    let rightEyeOpen: Bool
    let leftEyeBlink: Bool
    let rightEyeBlink: Bool
    let timestamp: TimeInterval
    
    init(leftEyeOpen: Bool, rightEyeOpen: Bool, leftEyeBlink: Bool = false, rightEyeBlink: Bool = false, timestamp: TimeInterval = Date().timeIntervalSince1970 * 1000) {
        self.leftEyeOpen = leftEyeOpen
        self.rightEyeOpen = rightEyeOpen
        self.leftEyeBlink = leftEyeBlink
        self.rightEyeBlink = rightEyeBlink
        self.timestamp = timestamp
    }
    
    func toDictionary() -> [String: Any] {
        return [
            "leftEyeOpen": leftEyeOpen,
            "rightEyeOpen": rightEyeOpen,
            "leftEyeBlink": leftEyeBlink,
            "rightEyeBlink": rightEyeBlink,
            "timestamp": timestamp
        ]
    }
    
    static func fromDictionary(_ dict: [String: Any]) -> EyeState? {
        guard let leftEyeOpen = dict["leftEyeOpen"] as? Bool,
              let rightEyeOpen = dict["rightEyeOpen"] as? Bool else {
            return nil
        }
        
        let leftEyeBlink = dict["leftEyeBlink"] as? Bool ?? false
        let rightEyeBlink = dict["rightEyeBlink"] as? Bool ?? false
        let timestamp = dict["timestamp"] as? TimeInterval ?? Date().timeIntervalSince1970 * 1000
        
        return EyeState(leftEyeOpen: leftEyeOpen, rightEyeOpen: rightEyeOpen, leftEyeBlink: leftEyeBlink, rightEyeBlink: rightEyeBlink, timestamp: timestamp)
    }
}

// MARK: - Head Pose
struct HeadPose {
    let pitch: Double  // Rotation around X-axis (degrees)
    let yaw: Double    // Rotation around Y-axis (degrees)
    let roll: Double   // Rotation around Z-axis (degrees)
    let confidence: Double
    let timestamp: TimeInterval
    
    init(pitch: Double, yaw: Double, roll: Double, confidence: Double = 1.0, timestamp: TimeInterval = Date().timeIntervalSince1970 * 1000) {
        self.pitch = pitch
        self.yaw = yaw
        self.roll = roll
        self.confidence = confidence
        self.timestamp = timestamp
    }
    
    func toDictionary() -> [String: Any] {
        return [
            "pitch": pitch,
            "yaw": yaw,
            "roll": roll,
            "confidence": confidence,
            "timestamp": timestamp
        ]
    }
    
    static func fromDictionary(_ dict: [String: Any]) -> HeadPose? {
        guard let pitch = dict["pitch"] as? Double,
              let yaw = dict["yaw"] as? Double,
              let roll = dict["roll"] as? Double else {
            return nil
        }
        
        let confidence = dict["confidence"] as? Double ?? 1.0
        let timestamp = dict["timestamp"] as? TimeInterval ?? Date().timeIntervalSince1970 * 1000
        
        return HeadPose(pitch: pitch, yaw: yaw, roll: roll, confidence: confidence, timestamp: timestamp)
    }
}

// MARK: - Face Detection
struct FaceDetection {
    let faceId: String
    let boundingBox: CGRect
    let confidence: Double
    let landmarks: [CGPoint]
    let timestamp: TimeInterval
    
    init(faceId: String, boundingBox: CGRect, confidence: Double, landmarks: [CGPoint] = [], timestamp: TimeInterval = Date().timeIntervalSince1970 * 1000) {
        self.faceId = faceId
        self.boundingBox = boundingBox
        self.confidence = confidence
        self.landmarks = landmarks
        self.timestamp = timestamp
    }
    
    func toDictionary() -> [String: Any] {
        let landmarkDictionaries = landmarks.map { point in
            return ["x": point.x, "y": point.y]
        }
        
        return [
            "faceId": faceId,
            "boundingBox": [
                "x": boundingBox.origin.x,
                "y": boundingBox.origin.y,
                "width": boundingBox.size.width,
                "height": boundingBox.size.height
            ],
            "confidence": confidence,
            "landmarks": landmarkDictionaries,
            "timestamp": timestamp
        ]
    }
    
    static func fromDictionary(_ dict: [String: Any]) -> FaceDetection? {
        guard let faceId = dict["faceId"] as? String,
              let boundingBoxDict = dict["boundingBox"] as? [String: Any],
              let x = boundingBoxDict["x"] as? Double,
              let y = boundingBoxDict["y"] as? Double,
              let width = boundingBoxDict["width"] as? Double,
              let height = boundingBoxDict["height"] as? Double else {
            return nil
        }
        
        let boundingBox = CGRect(x: x, y: y, width: width, height: height)
        let confidence = dict["confidence"] as? Double ?? 1.0
        let timestamp = dict["timestamp"] as? TimeInterval ?? Date().timeIntervalSince1970 * 1000
        
        var landmarks: [CGPoint] = []
        if let landmarkDictionaries = dict["landmarks"] as? [[String: Any]] {
            landmarks = landmarkDictionaries.compactMap { landmarkDict in
                guard let x = landmarkDict["x"] as? Double,
                      let y = landmarkDict["y"] as? Double else {
                    return nil
                }
                return CGPoint(x: x, y: y)
            }
        }
        
        return FaceDetection(faceId: faceId, boundingBox: boundingBox, confidence: confidence, landmarks: landmarks, timestamp: timestamp)
    }
}

// MARK: - Calibration Point
struct CalibrationPoint {
    let x: Double
    let y: Double
    let order: Int
    
    init(x: Double, y: Double, order: Int) {
        self.x = x
        self.y = y
        self.order = order
    }
    
    func toDictionary() -> [String: Any] {
        return [
            "x": x,
            "y": y,
            "order": order
        ]
    }
    
    static func fromDictionary(_ dict: [String: Any]) -> CalibrationPoint? {
        guard let x = dict["x"] as? Double,
              let y = dict["y"] as? Double,
              let order = dict["order"] as? Int else {
            return nil
        }
        
        return CalibrationPoint(x: x, y: y, order: order)
    }
}

// MARK: - Eye Landmarks
struct EyeLandmarks {
    let leftEye: [CGPoint]
    let rightEye: [CGPoint]
    let leftPupil: CGPoint
    let rightPupil: CGPoint
    let leftEyeCenter: CGPoint
    let rightEyeCenter: CGPoint
    
    init(leftEye: [CGPoint], rightEye: [CGPoint], leftPupil: CGPoint, rightPupil: CGPoint) {
        self.leftEye = leftEye
        self.rightEye = rightEye
        self.leftPupil = leftPupil
        self.rightPupil = rightPupil
        
        // Calculate eye centers
        self.leftEyeCenter = EyeLandmarks.calculateCenter(of: leftEye)
        self.rightEyeCenter = EyeLandmarks.calculateCenter(of: rightEye)
    }
    
    private static func calculateCenter(of points: [CGPoint]) -> CGPoint {
        guard !points.isEmpty else { return CGPoint.zero }
        
        let sumX = points.reduce(0) { $0 + $1.x }
        let sumY = points.reduce(0) { $0 + $1.y }
        
        return CGPoint(x: sumX / CGFloat(points.count), y: sumY / CGFloat(points.count))
    }
}

// MARK: - Calibration Sample
struct CalibrationSample {
    let targetPoint: CGPoint
    let gazePoints: [CGPoint]
    let timestamp: TimeInterval
    
    init(targetPoint: CGPoint, gazePoints: [CGPoint], timestamp: TimeInterval = Date().timeIntervalSince1970) {
        self.targetPoint = targetPoint
        self.gazePoints = gazePoints
        self.timestamp = timestamp
    }
}

// MARK: - Calibration Transform
struct CalibrationTransform {
    let transformMatrix: simd_float3x3
    let accuracy: Double
    
    init(transformMatrix: simd_float3x3, accuracy: Double) {
        self.transformMatrix = transformMatrix
        self.accuracy = accuracy
    }
    
    func apply(to point: CGPoint) -> CGPoint {
        let inputVector = simd_float3(Float(point.x), Float(point.y), 1.0)
        let transformedVector = transformMatrix * inputVector
        
        return CGPoint(x: CGFloat(transformedVector.x), y: CGFloat(transformedVector.y))
    }
}

// MARK: - Tracking Configuration
struct TrackingConfiguration {
    let targetFPS: Int
    let accuracyMode: AccuracyMode
    let enableBackgroundTracking: Bool
    
    enum AccuracyMode: String, CaseIterable {
        case fast = "fast"
        case medium = "medium"
        case high = "high"
        
        var processingQuality: Float {
            switch self {
            case .fast: return 0.3
            case .medium: return 0.6
            case .high: return 1.0
            }
        }
    }
}

// MARK: - Tracking Statistics
struct TrackingStatistics {
    let averageFPS: Double
    let droppedFrames: Int
    let processingTime: TimeInterval
    let memoryUsage: Double
    
    init(averageFPS: Double = 0, droppedFrames: Int = 0, processingTime: TimeInterval = 0, memoryUsage: Double = 0) {
        self.averageFPS = averageFPS
        self.droppedFrames = droppedFrames
        self.processingTime = processingTime
        self.memoryUsage = memoryUsage
    }
}
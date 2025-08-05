import Foundation
import CoreGraphics
import UIKit
import Darwin.Mach

// MARK: - CGPoint Extensions
extension CGPoint {
    /// Calculate distance to another point
    func distance(to point: CGPoint) -> CGFloat {
        let dx = self.x - point.x
        let dy = self.y - point.y
        return sqrt(dx * dx + dy * dy)
    }
    
    /// Normalize point to [0,1] range based on given size
    func normalized(in size: CGSize) -> CGPoint {
        return CGPoint(
            x: self.x / size.width,
            y: self.y / size.height
        )
    }
    
    /// Convert normalized point [0,1] to pixel coordinates
    func denormalized(in size: CGSize) -> CGPoint {
        return CGPoint(
            x: self.x * size.width,
            y: self.y * size.height
        )
    }
    
    /// Clamp point to given bounds
    func clamped(to rect: CGRect) -> CGPoint {
        return CGPoint(
            x: max(rect.minX, min(rect.maxX, self.x)),
            y: max(rect.minY, min(rect.maxY, self.y))
        )
    }
}

// MARK: - CGRect Extensions
extension CGRect {
    /// Convert Vision normalized coordinates to UIKit coordinates
    var visionToUIKit: CGRect {
        return CGRect(
            x: self.origin.x,
            y: 1.0 - self.origin.y - self.height,
            width: self.width,
            height: self.height
        )
    }
    
    /// Convert UIKit coordinates to Vision normalized coordinates
    var uiKitToVision: CGRect {
        return CGRect(
            x: self.origin.x,
            y: 1.0 - self.origin.y - self.height,
            width: self.width,
            height: self.height
        )
    }
}

// MARK: - Array Extensions
extension Array where Element == CGPoint {
    /// Calculate the centroid of points
    var centroid: CGPoint {
        guard !isEmpty else { return CGPoint.zero }
        
        let sumX = reduce(0) { $0 + $1.x }
        let sumY = reduce(0) { $0 + $1.y }
        
        return CGPoint(
            x: sumX / CGFloat(count),
            y: sumY / CGFloat(count)
        )
    }
    
    /// Calculate bounding box of points
    var boundingBox: CGRect {
        guard !isEmpty else { return CGRect.zero }
        
        let minX = map { $0.x }.min() ?? 0
        let maxX = map { $0.x }.max() ?? 0
        let minY = map { $0.y }.min() ?? 0
        let maxY = map { $0.y }.max() ?? 0
        
        return CGRect(
            x: minX,
            y: minY,
            width: maxX - minX,
            height: maxY - minY
        )
    }
}

// MARK: - Performance Monitoring
// Note: Memory usage functions are implemented in EyeTracker.swift

// MARK: - Logging Utilities
struct EyeTrackingLogger {
    static func log(_ message: String, level: LogLevel = .info, file: String = #file, function: String = #function, line: Int = #line) {
        let fileName = (file as NSString).lastPathComponent
        let timestamp = DateFormatter.logFormatter.string(from: Date())
        
        let logMessage = "\(timestamp) [\(level.emoji)] \(fileName):\(line) \(function) - \(message)"
        
        #if DEBUG
        print(logMessage)
        #endif
        
        // In production, you could send logs to a service or write to file
    }
    
    enum LogLevel {
        case debug, info, warning, error
        
        var emoji: String {
            switch self {
            case .debug: return "🔍"
            case .info: return "ℹ️"
            case .warning: return "⚠️"
            case .error: return "❌"
            }
        }
    }
}

private extension DateFormatter {
    static let logFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
}

// MARK: - Threading Utilities
extension DispatchQueue {
    /// Execute block on main queue if not already on main queue
    static func safeMain(_ block: @escaping () -> Void) {
        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.async(execute: block)
        }
    }
}

// MARK: - Math Utilities
struct MathUtils {
    /// Convert degrees to radians
    static func degreesToRadians(_ degrees: Double) -> Double {
        return degrees * .pi / 180.0
    }
    
    /// Convert radians to degrees
    static func radiansToDegrees(_ radians: Double) -> Double {
        return radians * 180.0 / .pi
    }
    
    /// Linear interpolation
    static func lerp(from: Double, to: Double, progress: Double) -> Double {
        return from + (to - from) * progress
    }
    
    /// Clamp value to range
    static func clamp<T: Comparable>(_ value: T, min: T, max: T) -> T {
        return Swift.min(Swift.max(value, min), max)
    }
    
    /// Calculate moving average
    static func movingAverage(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0.0 }
        return values.reduce(0.0, +) / Double(values.count)
    }
}

// MARK: - Device Information
struct DeviceInfo {
    static var modelName: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(Character(UnicodeScalar(UInt8(value))))
        }
        return identifier
    }
    
    static var systemVersion: String {
        return UIDevice.current.systemVersion
    }
    
    static var screenSize: CGSize {
        return UIScreen.main.bounds.size
    }
    
    static var screenScale: CGFloat {
        return UIScreen.main.scale
    }
    
    static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }
}

// MARK: - Configuration Validation
struct ConfigurationValidator {
    static func validateFrameRate(_ fps: Int) -> Bool {
        return fps > 0 && fps <= 60
    }
    
    static func validateAccuracyMode(_ mode: String) -> Bool {
        return ["fast", "medium", "high"].contains(mode)
    }
    
    static func validateCalibrationPoints(_ points: [CalibrationPoint]) -> Bool {
        guard points.count >= 3 else { return false }
        
        // Check for duplicate orders
        let orders = points.map { $0.order }
        let uniqueOrders = Set(orders)
        return orders.count == uniqueOrders.count
    }
    
    static func validateScreenCoordinates(_ point: CGPoint, screenSize: CGSize) -> Bool {
        return point.x >= 0 && point.x <= screenSize.width &&
               point.y >= 0 && point.y <= screenSize.height
    }
}
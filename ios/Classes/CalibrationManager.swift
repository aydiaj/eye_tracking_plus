import Foundation
import CoreGraphics
import simd
import Accelerate

class CalibrationManager: NSObject {
    
    // MARK: - Properties
    private var calibrationPoints: [CalibrationPoint] = []
    private var collectedSamples: [CalibrationSample] = []
    private var currentCalibrationTransform: CalibrationTransform?
    
    // Calibration state
    private(set) var isCalibrating = false
    private var currentPointIndex = 0
    private var samplesPerPoint = 30  // Number of gaze samples to collect per calibration point
    private var currentPointSamples: [CGPoint] = []
    
    // Data collection timing
    private var pointStartTime: CFTimeInterval = 0
    private let pointDuration: CFTimeInterval = 2.0  // Seconds to collect data per point
    private let stabilizationTime: CFTimeInterval = 0.5  // Initial stabilization period
    
    // Quality thresholds
    private let minSamplesPerPoint = 15
    private let maxGazeDeviation: CGFloat = 50.0  // pixels
    private let minAccuracyThreshold = 0.3
    
    // MARK: - Calibration Process
    func startCalibration(with points: [CalibrationPoint]) -> Bool {
        guard !isCalibrating && !points.isEmpty else {
            print("❌ Cannot start calibration: already calibrating or no points provided")
            return false
        }
        
        // Sort points by order
        calibrationPoints = points.sorted { $0.order < $1.order }
        collectedSamples.removeAll()
        currentPointIndex = 0
        isCalibrating = true
        
        print("✅ Started calibration with \(points.count) points")
        return true
    }
    
    func addCalibrationPoint(_ point: CalibrationPoint) -> Bool {
        guard isCalibrating else {
            print("❌ Not currently calibrating")
            return false
        }
        
        // Find the matching calibration point
        guard let targetPoint = calibrationPoints.first(where: { $0.order == point.order }) else {
            print("❌ Calibration point not found in sequence")
            return false
        }
        
        // Start data collection for this point
        currentPointSamples.removeAll()
        pointStartTime = CACurrentMediaTime()
        
        print("📍 Starting data collection for calibration point \(point.order + 1)/\(calibrationPoints.count)")
        return true
    }
    
    func addGazeSample(_ gazeData: GazeData) {
        guard isCalibrating else { return }
        
        let currentTime = CACurrentMediaTime()
        let elapsedTime = currentTime - pointStartTime
        
        // Skip samples during stabilization period
        guard elapsedTime >= stabilizationTime else { return }
        
        // Only collect samples if we haven't exceeded the duration
        guard elapsedTime <= pointDuration else { return }
        
        // Add gaze sample
        currentPointSamples.append(CGPoint(x: gazeData.x, y: gazeData.y))
        
        // Check if we have enough samples for this point
        if currentPointSamples.count >= samplesPerPoint || elapsedTime >= pointDuration {
            finalizeCurrentPoint()
        }
    }
    
    private func finalizeCurrentPoint() {
        guard currentPointIndex < calibrationPoints.count else { return }
        
        let targetPoint = calibrationPoints[currentPointIndex]
        let targetCGPoint = CGPoint(x: targetPoint.x, y: targetPoint.y)
        
        // Validate sample quality
        let filteredSamples = filterSamples(currentPointSamples, around: targetCGPoint)
        
        if filteredSamples.count >= minSamplesPerPoint {
            let sample = CalibrationSample(
                targetPoint: targetCGPoint,
                gazePoints: filteredSamples,
                timestamp: CACurrentMediaTime()
            )
            
            collectedSamples.append(sample)
            print("✅ Collected \(filteredSamples.count) samples for point \(targetPoint.order + 1)")
        } else {
            print("⚠️ Insufficient quality samples for point \(targetPoint.order + 1) (got \(filteredSamples.count), need \(minSamplesPerPoint))")
        }
        
        currentPointIndex += 1
        currentPointSamples.removeAll()
    }
    
    private func filterSamples(_ samples: [CGPoint], around target: CGPoint) -> [CGPoint] {
        // Remove outlier samples that are too far from the target
        return samples.filter { sample in
            let distance = sqrt(pow(sample.x - target.x, 2) + pow(sample.y - target.y, 2))
            return distance <= maxGazeDeviation
        }
    }
    
    func finishCalibration() -> Bool {
        guard isCalibrating else {
            print("❌ Not currently calibrating")
            return false
        }
        
        isCalibrating = false
        
        // Ensure we have samples for at least 3 points (minimum for transformation)
        guard collectedSamples.count >= 3 else {
            print("❌ Insufficient calibration data: need at least 3 points, got \(collectedSamples.count)")
            return false
        }
        
        // Calculate calibration transformation
        guard let transform = calculateCalibrationTransform() else {
            print("❌ Failed to calculate calibration transformation")
            return false
        }
        
        currentCalibrationTransform = transform
        
        print("✅ Calibration completed with accuracy: \(String(format: "%.2f", transform.accuracy))")
        return true
    }
    
    func clearCalibration() -> Bool {
        isCalibrating = false
        calibrationPoints.removeAll()
        collectedSamples.removeAll()
        currentCalibrationTransform = nil
        currentPointIndex = 0
        currentPointSamples.removeAll()
        
        print("🗑 Calibration data cleared")
        return true
    }
    
    // MARK: - Transformation Calculation
    private func calculateCalibrationTransform() -> CalibrationTransform? {
        guard collectedSamples.count >= 3 else { return nil }
        
        // Prepare data for transformation calculation
        var targetPoints: [CGPoint] = []
        var gazePoints: [CGPoint] = []
        
        for sample in collectedSamples {
            targetPoints.append(sample.targetPoint)
            
            // Calculate average gaze point for this target
            let averageGaze = calculateAveragePoint(sample.gazePoints)
            gazePoints.append(averageGaze)
        }
        
        // Calculate transformation matrix using least squares
        guard let transformMatrix = calculateAffineTransform(from: gazePoints, to: targetPoints) else {
            return nil
        }
        
        // Calculate accuracy
        let accuracy = calculateTransformAccuracy(transformMatrix, gazePoints: gazePoints, targetPoints: targetPoints)
        
        return CalibrationTransform(transformMatrix: transformMatrix, accuracy: accuracy)
    }
    
    private func calculateAveragePoint(_ points: [CGPoint]) -> CGPoint {
        guard !points.isEmpty else { return CGPoint.zero }
        
        let sumX = points.reduce(0) { $0 + $1.x }
        let sumY = points.reduce(0) { $0 + $1.y }
        
        return CGPoint(
            x: sumX / CGFloat(points.count),
            y: sumY / CGFloat(points.count)
        )
    }
    
    private func calculateAffineTransform(from sourcePoints: [CGPoint], to targetPoints: [CGPoint]) -> simd_float3x3? {
        guard sourcePoints.count == targetPoints.count && sourcePoints.count >= 3 else { return nil }
        
        // For simplicity, we'll use a 6-parameter affine transformation
        // [x'] = [a b tx] [x]
        // [y'] = [c d ty] [y]
        // [1 ] = [0 0 1 ] [1]
        
        let n = sourcePoints.count
        
        // Setup system of equations Ax = b
        var matrixA = Array(repeating: Array(repeating: 0.0, count: 6), count: n * 2)
        var vectorB = Array(repeating: 0.0, count: n * 2)
        
        for i in 0..<n {
            let src = sourcePoints[i]
            let dst = targetPoints[i]
            
            // Equation for x coordinate
            matrixA[i * 2][0] = Double(src.x)     // a
            matrixA[i * 2][1] = Double(src.y)     // b
            matrixA[i * 2][2] = 1.0               // tx
            matrixA[i * 2][3] = 0.0               // c
            matrixA[i * 2][4] = 0.0               // d
            matrixA[i * 2][5] = 0.0               // ty
            vectorB[i * 2] = Double(dst.x)
            
            // Equation for y coordinate
            matrixA[i * 2 + 1][0] = 0.0           // a
            matrixA[i * 2 + 1][1] = 0.0           // b
            matrixA[i * 2 + 1][2] = 0.0           // tx
            matrixA[i * 2 + 1][3] = Double(src.x) // c
            matrixA[i * 2 + 1][4] = Double(src.y) // d
            matrixA[i * 2 + 1][5] = 1.0           // ty
            vectorB[i * 2 + 1] = Double(dst.y)
        }
        
        // Solve using least squares (pseudo-inverse)
        guard let solution = solveLeastSquares(matrixA: matrixA, vectorB: vectorB) else {
            return nil
        }
        
        // Build transformation matrix
        let transform = simd_float3x3(
            simd_float3(Float(solution[0]), Float(solution[1]), Float(solution[2])),  // [a, b, tx]
            simd_float3(Float(solution[3]), Float(solution[4]), Float(solution[5])),  // [c, d, ty]
            simd_float3(0, 0, 1)                                                      // [0, 0, 1]
        )
        
        return transform
    }
    
    private func solveLeastSquares(matrixA: [[Double]], vectorB: [Double]) -> [Double]? {
        // This is a simplified least squares solver
        // In a production implementation, you would use Accelerate framework or LAPACK
        
        let rows = matrixA.count
        let cols = matrixA.first?.count ?? 0
        
        guard rows >= cols else { return nil }
        
        // For simplicity, use normal equations: x = (A^T * A)^(-1) * A^T * b
        // This is not the most numerically stable method, but works for calibration
        
        // Calculate A^T * A
        var ata = Array(repeating: Array(repeating: 0.0, count: cols), count: cols)
        for i in 0..<cols {
            for j in 0..<cols {
                var sum = 0.0
                for k in 0..<rows {
                    sum += matrixA[k][i] * matrixA[k][j]
                }
                ata[i][j] = sum
            }
        }
        
        // Calculate A^T * b
        var atb = Array(repeating: 0.0, count: cols)
        for i in 0..<cols {
            var sum = 0.0
            for k in 0..<rows {
                sum += matrixA[k][i] * vectorB[k]
            }
            atb[i] = sum
        }
        
        // Solve using simple Gaussian elimination (for demonstration)
        return solveLinearSystem(matrix: ata, vector: atb)
    }
    
    private func solveLinearSystem(matrix: [[Double]], vector: [Double]) -> [Double]? {
        let n = matrix.count
        var augmented = matrix
        var b = vector
        
        // Forward elimination
        for i in 0..<n {
            // Find pivot
            var maxRow = i
            for k in (i + 1)..<n {
                if abs(augmented[k][i]) > abs(augmented[maxRow][i]) {
                    maxRow = k
                }
            }
            
            // Swap rows
            if maxRow != i {
                augmented.swapAt(i, maxRow)
                b.swapAt(i, maxRow)
            }
            
            // Check for zero pivot
            guard abs(augmented[i][i]) > 1e-10 else { return nil }
            
            // Eliminate
            for k in (i + 1)..<n {
                let factor = augmented[k][i] / augmented[i][i]
                for j in i..<n {
                    augmented[k][j] -= factor * augmented[i][j]
                }
                b[k] -= factor * b[i]
            }
        }
        
        // Back substitution
        var solution = Array(repeating: 0.0, count: n)
        for i in stride(from: n - 1, through: 0, by: -1) {
            solution[i] = b[i]
            for j in (i + 1)..<n {
                solution[i] -= augmented[i][j] * solution[j]
            }
            solution[i] /= augmented[i][i]
        }
        
        return solution
    }
    
    private func calculateTransformAccuracy(_ transform: simd_float3x3, gazePoints: [CGPoint], targetPoints: [CGPoint]) -> Double {
        guard gazePoints.count == targetPoints.count else { return 0.0 }
        
        var totalError: Double = 0.0
        let maxError: Double = 200.0  // Maximum reasonable error in pixels
        
        for i in 0..<gazePoints.count {
            let gaze = gazePoints[i]
            let target = targetPoints[i]
            
            // Apply transformation
            let inputVector = simd_float3(Float(gaze.x), Float(gaze.y), 1.0)
            let transformedVector = transform * inputVector
            let transformed = CGPoint(x: CGFloat(transformedVector.x), y: CGFloat(transformedVector.y))
            
            // Calculate error
            let error = sqrt(pow(transformed.x - target.x, 2) + pow(transformed.y - target.y, 2))
            totalError += Double(error)
        }
        
        let averageError = totalError / Double(gazePoints.count)
        let accuracy = max(0.0, 1.0 - (averageError / maxError))
        
        return accuracy
    }
    
    // MARK: - Public Accessors
    func getAccuracy() -> Double {
        return currentCalibrationTransform?.accuracy ?? 0.0
    }
    
    func getCalibrationTransform() -> CalibrationTransform? {
        return currentCalibrationTransform
    }
    
    func getProgress() -> Double {
        guard isCalibrating && !calibrationPoints.isEmpty else { return 0.0 }
        return Double(collectedSamples.count) / Double(calibrationPoints.count)
    }
    
    func getCurrentPointIndex() -> Int {
        return currentPointIndex
    }
    
    func getTotalPoints() -> Int {
        return calibrationPoints.count
    }
}
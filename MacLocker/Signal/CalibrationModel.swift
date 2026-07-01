import Foundation

struct CalibrationResult: Codable, Equatable {
    var nearMedian: Double
    var awayMedian: Double
    var threshold: Int
}

enum CalibrationError: LocalizedError, Equatable {
    case insufficientSamples
    case noisySamples
    case overlappingSamples(nearMedian: Double, awayMedian: Double)

    var errorDescription: String? {
        switch self {
        case .insufficientSamples:
            "Not enough Bluetooth samples were recorded."
        case .noisySamples:
            "The recorded signal was too noisy to calibrate safely."
        case let .overlappingSamples(nearMedian, awayMedian):
            "Near and away samples overlap too much (near \(Int(nearMedian.rounded())) dBm, away \(Int(awayMedian.rounded())) dBm)."
        }
    }
}

enum CalibrationModel {
    static let practicalThresholdRange = -90 ... -45
    static let minimumMedianSeparation = 8.0
    static let maximumInterquartileRange = 18.0

    static func calibrate(nearRSSI: [Int], awayRSSI: [Int]) throws -> CalibrationResult {
        guard nearRSSI.count >= 3, awayRSSI.count >= 3 else {
            throw CalibrationError.insufficientSamples
        }

        let nearValues = nearRSSI.map(Double.init)
        let awayValues = awayRSSI.map(Double.init)
        let nearMedian = median(nearValues)
        let awayMedian = median(awayValues)

        guard interquartileRange(nearValues) <= maximumInterquartileRange,
              interquartileRange(awayValues) <= maximumInterquartileRange
        else {
            throw CalibrationError.noisySamples
        }

        guard nearMedian - awayMedian >= minimumMedianSeparation else {
            throw CalibrationError.overlappingSamples(nearMedian: nearMedian, awayMedian: awayMedian)
        }

        let midpoint = Int(((nearMedian + awayMedian) / 2).rounded())
        let threshold = min(max(midpoint, practicalThresholdRange.lowerBound), practicalThresholdRange.upperBound)
        return CalibrationResult(nearMedian: nearMedian, awayMedian: awayMedian, threshold: threshold)
    }

    static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    private static func interquartileRange(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        guard sorted.count >= 4 else { return 0 }
        let lower = Array(sorted[..<(sorted.count / 2)])
        let upper = Array(sorted[((sorted.count + 1) / 2)...])
        return median(upper) - median(lower)
    }
}

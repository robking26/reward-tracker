import CoreGraphics
import Foundation
import ImageIO

/// A 64-bit average hash. Near-identical photos of the same plate produce hashes a few bits apart,
/// which lets the app refuse a second photo reward for the same meal.
enum ImageFingerprint {
    static let duplicateThreshold = 6

    static func averageHash(of data: Data) -> UInt64? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: 64,
              ] as CFDictionary)
        else { return nil }

        var pixels = [UInt8](repeating: 0, count: 64)
        let drew: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 8,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
            else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: 8, height: 8))
            return true
        }
        guard drew else { return nil }

        let mean = pixels.reduce(0) { $0 + Int($1) } / pixels.count
        var hash: UInt64 = 0
        for (index, value) in pixels.enumerated() where Int(value) > mean {
            hash |= 1 << UInt64(index)
        }
        return hash
    }

    static func distance(_ a: UInt64, _ b: UInt64) -> Int {
        (a ^ b).nonzeroBitCount
    }

    static func isDuplicate(_ hash: UInt64, of others: [UInt64]) -> Bool {
        others.contains { distance(hash, $0) <= duplicateThreshold }
    }
}

/// The first three distinct, confirmed meals each day earn a photo reward.
enum MealRewardPolicy {
    enum Outcome: Equatable {
        case eligible
        case dailyLimitReached
        case duplicate
    }

    static func outcome(hash: UInt64, earlierMealsToday: [(hash: UInt64, eligible: Bool)], limit: Int) -> Outcome {
        if ImageFingerprint.isDuplicate(hash, of: earlierMealsToday.map { $0.hash }) { return .duplicate }
        if earlierMealsToday.filter({ $0.eligible }).count >= limit { return .dailyLimitReached }
        return .eligible
    }
}

import CoreGraphics
import Foundation

/// One dominant color of an image and the share of pixels it represents.
struct ColorCluster: Hashable, Codable, Sendable {
    var lab: OKLab
    var weight: Double
}

/// Converts a small thumbnail into up to three OKLab centroids via k-means (k = 3).
enum ColorExtractor {
    /// Side of the square the image is redrawn into before sampling.
    static let sampleSide = 32

    static func dominantColors(of image: CGImage, k: Int = 3) -> [ColorCluster] {
        guard let pixels = samplePixels(image) else { return [] }
        return kMeans(pixels, k: k)
    }

    /// Redraws into a fixed RGBA8 buffer and converts every pixel to OKLab (SIMD-friendly floats).
    static func samplePixels(_ image: CGImage) -> [SIMD3<Float>]? {
        let side = sampleSide
        var buffer = [UInt8](repeating: 0, count: side * side * 4)
        let ok: Bool = buffer.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(
                data: raw.baseAddress, width: side, height: side, bitsPerComponent: 8,
                bytesPerRow: side * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            ctx.interpolationQuality = .low
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard ok else { return nil }
        let lut = SRGBLUT.table
        var out = [SIMD3<Float>]()
        out.reserveCapacity(side * side)
        for i in stride(from: 0, to: buffer.count, by: 4) {
            out.append(labFloat(r: lut[Int(buffer[i])], g: lut[Int(buffer[i + 1])], b: lut[Int(buffer[i + 2])]))
        }
        return out
    }

    @inline(__always)
    static func labFloat(r: Float, g: Float, b: Float) -> SIMD3<Float> {
        let l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b
        let m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b
        let s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b
        let l_ = cbrtf(l), m_ = cbrtf(m), s_ = cbrtf(s)
        return SIMD3(
            0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
            1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
            0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_
        )
    }

    /// Deterministic k-means with k-means++-style farthest-point seeding.
    /// Returns clusters sorted by weight, heaviest first; empty clusters are dropped.
    static func kMeans(_ points: [SIMD3<Float>], k: Int, iterations: Int = 8) -> [ColorCluster] {
        guard !points.isEmpty else { return [] }
        let k = min(k, points.count)

        // Seed: first = mean, then repeatedly the point farthest from existing centroids.
        var centroids: [SIMD3<Float>] = [points.reduce(.zero, +) / Float(points.count)]
        var nearest = [Float](repeating: .greatestFiniteMagnitude, count: points.count)
        while centroids.count < k {
            let c = centroids[centroids.count - 1]
            var bestIdx = 0
            var bestD: Float = -1
            for i in points.indices {
                let d = distSq(points[i], c)
                if d < nearest[i] { nearest[i] = d }
                if nearest[i] > bestD { bestD = nearest[i]; bestIdx = i }
            }
            if bestD <= 1e-6 { break }
            centroids.append(points[bestIdx])
        }

        var assignment = [Int](repeating: 0, count: points.count)
        for _ in 0..<iterations {
            var sums = [SIMD3<Float>](repeating: .zero, count: centroids.count)
            var counts = [Int](repeating: 0, count: centroids.count)
            var changed = false
            for i in points.indices {
                var best = 0
                var bestD = Float.greatestFiniteMagnitude
                for c in centroids.indices {
                    let d = distSq(points[i], centroids[c])
                    if d < bestD { bestD = d; best = c }
                }
                if assignment[i] != best { assignment[i] = best; changed = true }
                sums[best] += points[i]
                counts[best] += 1
            }
            for c in centroids.indices where counts[c] > 0 {
                centroids[c] = sums[c] / Float(counts[c])
            }
            if !changed { break }
        }

        var counts = [Int](repeating: 0, count: centroids.count)
        for a in assignment { counts[a] += 1 }
        let total = Double(points.count)
        return centroids.indices
            .filter { counts[$0] > 0 }
            .map { ColorCluster(lab: OKLab(L: Double(centroids[$0].x), a: Double(centroids[$0].y), b: Double(centroids[$0].z)),
                                weight: Double(counts[$0]) / total) }
            .sorted { $0.weight > $1.weight }
    }

    @inline(__always) private static func distSq(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
        let d = a - b
        return (d * d).sum()
    }
}

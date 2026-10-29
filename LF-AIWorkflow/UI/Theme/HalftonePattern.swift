//
//  HalftonePattern.swift
//  LF-AIWorkflow
//

import CoreGraphics
import SwiftUI

/// Everything that changes a rasterized dot grid. Size is rounded to whole points so resize animations hit the cache.
nonisolated struct HalftoneKey: Sendable, Hashable {
    /// The tile is this many dot spacings on a side: an even multiple, so the staggered grid repeats seamlessly.
    static let tileSpacings: CGFloat = 8

    let width: Int
    let height: Int
    let scale: Double
    let spacing: Double
    let radius: Double
    let dot: ThemeColor

    /// Complexity: O(1) time, O(1) space
    init(size: CGSize, scale: CGFloat, spacing: CGFloat, radius: CGFloat, dot: ThemeColor) {
        width = Int(size.width.rounded())
        height = Int(size.height.rounded())
        self.scale = Double(scale)
        self.spacing = Double(spacing)
        self.radius = Double(radius)
        self.dot = dot
    }

    /// The repeating tile for a halftone background. Using one tile size means the panel size (and its animation) never adds a key.
    /// Complexity: O(1) time, O(1) space
    static func tile(spacing: CGFloat, radius: CGFloat, dot: ThemeColor, scale: CGFloat) -> HalftoneKey {
        let side = spacing * tileSpacings
        return HalftoneKey(size: CGSize(width: side, height: side), scale: scale,
                           spacing: spacing, radius: radius, dot: dot)
    }
}

nonisolated enum HalftoneRasterizer {
    /// Draws a staggered dot grid in `key.dot` into a bitmap of `key.width * scale` by `key.height * scale` pixels.
    /// Complexity: O(w * h / s^2) time, O(w * h * scale^2) space (w, h = size, s = dot spacing)
    static func render(_ key: HalftoneKey) -> CGImage? {
        guard key.spacing > 0, key.width > 0, key.height > 0 else { return nil }
        let pixelWidth = max(1, Int((Double(key.width) * key.scale).rounded()))
        let pixelHeight = max(1, Int((Double(key.height) * key.scale).rounded()))
        guard let context = CGContext(
            data: nil, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.scaleBy(x: CGFloat(key.scale), y: CGFloat(key.scale))
        context.setFillColor(red: key.dot.r, green: key.dot.g, blue: key.dot.b, alpha: key.dot.a)
        drawDots(key, in: context)
        return context.makeImage()
    }

    /// Dot centers sit at half a spacing, and every odd row is shifted half a spacing (Ben-Day stagger).
    /// Complexity: O(w * h / s^2) time, O(1) space
    private static func drawDots(_ key: HalftoneKey, in context: CGContext) {
        let step = key.spacing
        let half = step / 2
        var row = 0
        for centerY in stride(from: half, to: Double(key.height), by: step) {
            let offset = row.isMultiple(of: 2) ? 0 : half
            for centerX in stride(from: half + offset, to: Double(key.width), by: step) {
                context.fillEllipse(in: CGRect(x: centerX - key.radius, y: centerY - key.radius,
                                               width: key.radius * 2, height: key.radius * 2))
            }
            row += 1
        }
    }
}

/// Renders each `HalftoneKey` once and reuses the image while it is among the `capacity` most recently used.
/// Older images are evicted (least recently used first), so memory stays bounded. Main-actor isolated, so no locks are needed.
@MainActor final class HalftoneImageCache {
    static let shared = HalftoneImageCache()
    /// Enough for every theme's dot colors at the scales in use, with room to spare.
    static let defaultCapacity = 32

    private(set) var renderCount = 0
    private var images: [HalftoneKey: CGImage] = [:]
    /// Cached keys ordered from least to most recently used.
    private var recency: [HalftoneKey] = []
    private let capacity: Int
    private let render: @MainActor (HalftoneKey) -> CGImage?

    var entryCount: Int { images.count }

    init(capacity: Int = HalftoneImageCache.defaultCapacity,
         render: @escaping @MainActor (HalftoneKey) -> CGImage? = HalftoneRasterizer.render) {
        self.capacity = max(1, capacity)
        self.render = render
    }

    /// Returns the cached image for `key`, rendering it on a miss and evicting the least recently used image when full.
    /// Complexity: O(c) time per call (c = capacity, for the recency update); O(r) extra on a miss (r = render cost); O(c) space
    func image(for key: HalftoneKey) -> CGImage? {
        if let cached = images[key] {
            markUsed(key)
            return cached
        }
        guard let image = render(key) else { return nil }
        renderCount += 1
        images[key] = image
        recency.append(key)
        evictOverflow()
        return image
    }

    /// Moves `key` to the most-recently-used end.
    /// Complexity: O(c) time, O(1) space (c = capacity)
    private func markUsed(_ key: HalftoneKey) {
        recency.removeAll { $0 == key }
        recency.append(key)
    }

    /// Drops the oldest images until the cache is back within `capacity`.
    /// Complexity: O(e * c) time, O(1) extra space (e = images evicted, at most one per insert)
    private func evictOverflow() {
        while images.count > capacity, !recency.isEmpty {
            let oldest = recency.removeFirst()
            images[oldest] = nil
        }
    }
}

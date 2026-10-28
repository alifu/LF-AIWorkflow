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

/// Renders each distinct `HalftoneKey` once and reuses the image. Main-actor isolated, so no locks are needed.
@MainActor final class HalftoneImageCache {
    static let shared = HalftoneImageCache()

    private(set) var renderCount = 0
    private var images: [HalftoneKey: CGImage] = [:]
    private let render: @MainActor (HalftoneKey) -> CGImage?

    var entryCount: Int { images.count }

    init(render: @escaping @MainActor (HalftoneKey) -> CGImage? = HalftoneRasterizer.render) {
        self.render = render
    }

    /// Returns the cached image for `key`, rendering it on the first request only.
    /// Complexity: O(1) expected time per hit; O(r) time on a miss (r = render cost); O(n) space (n = distinct keys)
    func image(for key: HalftoneKey) -> CGImage? {
        if let cached = images[key] { return cached }
        guard let image = render(key) else { return nil }
        renderCount += 1
        images[key] = image
        return image
    }
}

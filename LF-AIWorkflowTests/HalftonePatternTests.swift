//
//  HalftonePatternTests.swift
//  LF-AIWorkflowTests
//

import CoreGraphics
import Testing
@testable import LF_AIWorkflow

@MainActor
struct HalftonePatternTests {
    private let dot = ThemeColor(0, 0, 0, 0.1)

    private func key(_ width: CGFloat, _ height: CGFloat, scale: CGFloat = 2) -> HalftoneKey {
        HalftoneKey(size: CGSize(width: width, height: height), scale: scale, spacing: 6, radius: 1.2, dot: dot)
    }

    @Test func keyRoundsSizeToWholePoints() {
        #expect(key(100.4, 50.6) == key(100, 51))
        #expect(key(100, 50) != key(101, 50))
    }

    @Test func sameKeyIsRenderedOnlyOnce() {
        // Arrange
        let cache = HalftoneImageCache()
        // Act
        let first = cache.image(for: key(120, 80))
        let second = cache.image(for: key(120, 80))
        // Assert
        #expect(first != nil)
        #expect(first === second)
        #expect(cache.renderCount == 1)
        #expect(cache.entryCount == 1)
    }

    @Test func aDifferentSizeIsOneMoreRender() {
        let cache = HalftoneImageCache()
        _ = cache.image(for: key(120, 80))
        _ = cache.image(for: key(121, 80))
        #expect(cache.renderCount == 2)
        #expect(cache.entryCount == 2)
    }

    @Test func imageIsRasterizedAtTheRequestedPixelSize() {
        let image = HalftoneImageCache().image(for: key(40, 30, scale: 2))
        #expect(image?.width == 80)
        #expect(image?.height == 60)
    }

    @Test func cacheNeverHoldsMoreThanItsCapacity() {
        let cache = HalftoneImageCache(capacity: 3)
        for width in 100..<120 { _ = cache.image(for: key(CGFloat(width), 80)) }
        #expect(cache.entryCount == 3)
        #expect(cache.renderCount == 20)
    }

    @Test func cacheEvictsTheLeastRecentlyUsedImage() {
        // Arrange
        let cache = HalftoneImageCache(capacity: 2)
        _ = cache.image(for: key(120, 80))  // A
        _ = cache.image(for: key(121, 80))  // B
        _ = cache.image(for: key(120, 80))  // touch A, so B is now the oldest
        // Act
        _ = cache.image(for: key(122, 80))  // C evicts B
        _ = cache.image(for: key(120, 80))  // A is still cached
        #expect(cache.renderCount == 3)
        _ = cache.image(for: key(121, 80))  // B was evicted, so it renders again
        // Assert
        #expect(cache.renderCount == 4)
        #expect(cache.entryCount == 2)
    }
}

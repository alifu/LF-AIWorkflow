//
//  DisplayOverrideTests.swift
//  LF-AIWorkflowTests
//

import Testing
import CoreGraphics
@testable import LF_AIWorkflow

struct DisplayOverrideTests {
    @Test func autoLeavesMetricsUntouched() {
        #expect(DisplayOverride.auto.apply(to: FakeScreens.mbp14) == FakeScreens.mbp14)
        #expect(DisplayOverride.auto.apply(to: FakeScreens.external) == FakeScreens.external)
    }

    @Test func noNotchRemovesTheNotchButKeepsTheMenuBar() {
        let result = DisplayOverride.noNotch.apply(to: FakeScreens.mbp14)
        #expect(NotchGeometry.kind(for: result) == .none)
        #expect(result.frame == FakeScreens.mbp14.frame)
        #expect(result.auxiliaryTopLeft == nil && result.auxiliaryTopRight == nil)
        #expect(result.menuBarHeight == 32)
    }

    @Test func notchAddsASimulatedNotchToAScreenWithout() {
        let result = DisplayOverride.notch.apply(to: FakeScreens.external)
        #expect(NotchGeometry.kind(for: result)
                == .notch(width: DisplayOverride.simulatedNotchWidth, height: DisplayOverride.simulatedNotchHeight))
        #expect(NotchGeometry.collapsedFrame(for: result).midX == 960)
    }

    @Test func notchKeepsARealNotchUnchanged() {
        #expect(DisplayOverride.notch.apply(to: FakeScreens.mbp16) == FakeScreens.mbp16)
    }

    @Test func launchArgumentBeatsStoredValue() {
        #expect(DisplayOverride.resolve(arguments: ["app", "-LFSimulateNotch", "YES"], stored: "noNotch") == .notch)
        #expect(DisplayOverride.resolve(arguments: ["app", "-LFSimulateNotch", "NO"], stored: "notch") == .noNotch)
    }

    @Test func fallsBackToStoredThenAuto() {
        #expect(DisplayOverride.resolve(arguments: ["app"], stored: "notch") == .notch)
        #expect(DisplayOverride.resolve(arguments: ["app"], stored: "garbage") == .auto)
        #expect(DisplayOverride.resolve(arguments: ["app", "-LFSimulateNotch"], stored: nil) == .auto)
        #expect(DisplayOverride.resolve(arguments: ["app", "-LFSimulateNotch", "maybe"], stored: "noNotch") == .noNotch)
    }
}

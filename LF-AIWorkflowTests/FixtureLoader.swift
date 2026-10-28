//
//  FixtureLoader.swift
//  LF-AIWorkflowTests
//

import Foundation

private final class FixtureBundleToken {}

/// Loads a fixture by file name from the test bundle. Xcode copies `Fixtures/**` flat into
/// Resources, so names must be unique across suites. (Reading the source tree via `#filePath`
/// triggers a macOS TCC prompt for ~/Documents and hangs the hosted test run.)
func loadFixture(_ name: String) throws -> Data {
    let bundle = Bundle(for: FixtureBundleToken.self)
    guard let url = bundle.url(forResource: name, withExtension: nil) else {
        throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: name])
    }
    return try Data(contentsOf: url)
}

//
//  TechDebtH2Tests.swift
//  LF-AIWorkflowTests
//

import Testing
import Foundation
import os
@testable import LF_AIWorkflow

@Suite(.timeLimit(.minutes(1)))
struct TechDebtH2Tests {

    private func scanned(_ path: String) -> ScannedFile {
        ScannedFile(path: path, size: 1, hash: nil)
    }

    // MARK: TD-127 (must hold in Release: the check is not an assert)

    @Test func walkCountMismatchThrowsInEveryBuildConfiguration() {
        var thrown: LFCoreError?
        do {
            _ = try FolderScanner.checkedFiles(reported: 2, collected: [scanned("/a")])
        } catch {
            thrown = error
        }
        #expect(thrown == .scanCountMismatch(reported: 2, collected: 1))
    }

    @Test func matchingWalkCountReturnsTheFiles() throws {
        let files = [scanned("/a"), scanned("/b")]
        #expect(try FolderScanner.checkedFiles(reported: 2, collected: files) == files)
    }

    // MARK: TD-130 (provider reads the paths without a MainActor hop)

    @MainActor @Test func liveLocatorAnswersWhileTheMainActorIsBlocked() {
        let store = ToolPathStore([.git: "/bin/sh"])
        let provider = AppComposition.liveLocators(searchPath: [], paths: store)
        let result = OSAllocatedUnfairLock<URL?>(initialState: nil)
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            let url = try? await provider.current().locate(.git)
            result.withLock { $0 = url }
            done.signal()
        }
        // The main thread blocks here. A provider that hops to MainActor cannot finish, so the wait times out.
        let finished = done.wait(timeout: .now() + .seconds(5))
        #expect(finished == .success)
        #expect(result.withLock { $0 } == URL(fileURLWithPath: "/bin/sh"))
    }
}

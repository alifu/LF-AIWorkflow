//
//  LFCoreTests.swift
//  LF-AIWorkflowTests
//

import Testing
import LFCore

struct LFCoreTests {

    @Test func versionReturnsStubTag() {
        #expect(String(cString: lf_core_version()) == "0.1.0-stub")
    }

}

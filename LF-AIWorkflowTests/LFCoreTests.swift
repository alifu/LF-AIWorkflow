//
//  LFCoreTests.swift
//  LF-AIWorkflowTests
//

import Testing
import LFCore

struct LFCoreTests {

    @Test func versionReturnsPhase2Tag() {
        #expect(String(cString: lf_core_version()) == "0.2.0")
    }

}

//
//  TestTags.swift
//  LF-AIWorkflowTests
//

import Testing

extension Tag {
    /// Tests that call the real `claude` CLI (spend tokens); opt in with `LF_RUN_CLAUDE_TESTS=1`.
    @Tag static var requiresClaude: Tag
}

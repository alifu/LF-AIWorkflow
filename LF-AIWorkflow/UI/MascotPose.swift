//
//  MascotPose.swift
//  LF-AIWorkflow
//

/// Poses the Phase 6 mascot will draw. Defined now so T6.1 only replaces the drawing.
enum MascotPose: Sendable, Hashable {
    case idle, typing, done, error, attention

    /// Pose that matches the overall state of the board.
    static func pose(for summary: CollapsedSummary) -> MascotPose {
        if summary.attentionCount > 0 { return .attention }
        return summary.activeCount > 0 ? .typing : .idle
    }
}

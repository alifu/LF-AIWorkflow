//
//  NotchLayoutModel.swift
//  LF-AIWorkflow
//

import CoreGraphics
import Observation

/// Display facts the root view needs (notch or not); the window controller keeps it current.
@MainActor @Observable
final class NotchLayoutModel {
    var kind: NotchKind

    init(kind: NotchKind = .none) { self.kind = kind }

    /// Height of the area the notch (or menu bar) occupies at the top of the expanded panel.
    var topInset: CGFloat {
        switch kind {
        case .notch(_, let height): height
        case .none: 0
        }
    }
}

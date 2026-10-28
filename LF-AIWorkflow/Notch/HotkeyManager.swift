//
//  HotkeyManager.swift
//  LF-AIWorkflow
//

/// Owns the one live global hotkey and swaps it when the setting changes.
@MainActor
final class HotkeyManager {
    typealias Factory = (HotkeySpec, @escaping () -> Void) -> any HotkeyRegistering

    private let factory: Factory
    private let action: () -> Void
    private var current: (any HotkeyRegistering)?
    private(set) var activeSpec: HotkeySpec?

    init(factory: @escaping Factory, action: @escaping () -> Void) {
        self.factory = factory
        self.action = action
    }

    /// Registers `spec` first and only then releases the previous hotkey, so a refused or invalid
    /// spec leaves the working one in place. Returns false when invalid or refused by the system.
    /// Complexity: O(1) time, O(1) space
    @discardableResult
    func apply(_ spec: HotkeySpec) -> Bool {
        if spec == activeSpec, current != nil { return true }
        guard spec.validate() == .valid else { return false }
        let hotkey = factory(spec, action)
        guard hotkey.register() else { return false }
        current?.unregister()
        current = hotkey
        activeSpec = spec
        return true
    }

    /// Complexity: O(1) time, O(1) space
    func stop() {
        current?.unregister()
        current = nil
        activeSpec = nil
    }
}

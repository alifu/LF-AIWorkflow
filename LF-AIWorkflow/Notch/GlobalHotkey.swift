//
//  GlobalHotkey.swift
//  LF-AIWorkflow
//

import Carbon.HIToolbox

/// Seam so the app wiring can be tested without Carbon.
protocol HotkeyRegistering: AnyObject {
    @discardableResult func register() -> Bool
    func unregister()
}

/// System-wide hotkey through Carbon `RegisterEventHotKey` (no Accessibility permission needed).
/// Hard-coded to option-command-space until the configurable hotkey in Phase 6 (T6.3).
final class GlobalHotkey: HotkeyRegistering {
    private static let signature: OSType = 0x4C46_484B   // 'LFHK'

    private let keyCode: UInt32
    private let modifiers: UInt32
    private let action: () -> Void
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    init(keyCode: UInt32 = UInt32(kVK_Space), modifiers: UInt32 = UInt32(optionKey | cmdKey),
         action: @escaping () -> Void) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.action = action
    }

    isolated deinit { unregister() }

    /// Returns false when the system refuses (for example the combination is taken).
    /// Complexity: O(1) time, O(1) space
    @discardableResult
    func register() -> Bool {
        guard hotKeyRef == nil else { return true }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installed = InstallEventHandler(
            GetApplicationEventTarget(), globalHotkeyCallback, 1, &spec,
            Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
        guard installed == noErr else { return false }
        let id = EventHotKeyID(signature: Self.signature, id: 1)
        let registered = RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
        if registered != noErr { unregister() }
        return registered == noErr
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
        hotKeyRef = nil
        handlerRef = nil
    }

    fileprivate func fire() { action() }
}

/// Carbon delivers hotkey events on the main thread.
private nonisolated func globalHotkeyCallback(_ next: EventHandlerCallRef?, _ event: EventRef?, _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let userData else { return OSStatus(eventNotHandledErr) }
    let hotkey = Unmanaged<GlobalHotkey>.fromOpaque(userData).takeUnretainedValue()
    MainActor.assumeIsolated { hotkey.fire() }
    return noErr
}

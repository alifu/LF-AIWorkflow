//
//  HotkeySpec.swift
//  LF-AIWorkflow
//

import Carbon.HIToolbox

nonisolated enum HotkeyValidation: Sendable, Equatable {
    case valid
    /// Needs at least one of command, control or option (shift alone would swallow normal typing).
    case missingModifier
    /// The key itself is a modifier or Fn key.
    case modifierOnlyKey
}

extension HotkeySpec {
    static let optionCommandSpace = HotkeySpec.default
    static let controlOptionSpace = HotkeySpec(keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey | optionKey))
    static let optionCommandN = HotkeySpec(keyCode: UInt32(kVK_ANSI_N), modifiers: UInt32(optionKey | cmdKey))
    /// Default for the research inbox (save the current Safari tab): Control, Option, Command and C.
    static let controlOptionCommandC = HotkeySpec(keyCode: UInt32(kVK_ANSI_C), modifiers: UInt32(controlKey | optionKey | cmdKey))

    /// The combinations the Settings picker offers; the first is the default.
    static let presets: [HotkeySpec] = [.optionCommandSpace, .controlOptionSpace, .optionCommandN]

    /// Shortcuts offered for the inbox capture: the presets plus its default, without the main shortcut.
    /// Complexity: O(1) time, O(1) space
    static func inboxChoices(excluding main: HotkeySpec) -> [HotkeySpec] {
        ([.controlOptionCommandC] + presets).filter { $0 != main }
    }

    private static let requiredModifierMask = UInt32(cmdKey | controlKey | optionKey)
    /// Virtual key codes of Command, Shift, Caps Lock, Option, Control (left and right) and Fn (54...63).
    private static let modifierKeyCodes: ClosedRange<UInt32> = 54...63

    /// Complexity: O(1) time, O(1) space
    func validate() -> HotkeyValidation {
        if Self.modifierKeyCodes.contains(keyCode) { return .modifierOnlyKey }
        if modifiers & Self.requiredModifierMask == 0 { return .missingModifier }
        return .valid
    }

    /// Menu-style text such as "⌥⌘Space" (modifier order: control, option, shift, command).
    /// Complexity: O(1) time, O(1) space
    var displayString: String {
        let symbols: [(UInt32, String)] = [
            (UInt32(controlKey), "⌃"), (UInt32(optionKey), "⌥"), (UInt32(shiftKey), "⇧"), (UInt32(cmdKey), "⌘"),
        ]
        let prefix = symbols.filter { modifiers & $0.0 != 0 }.map(\.1).joined()
        return prefix + Self.keyName(keyCode)
    }

    private static func keyName(_ code: UInt32) -> String {
        switch Int(code) {
        case kVK_Space: "Space"
        case kVK_ANSI_N: "N"
        case kVK_ANSI_C: "C"
        case kVK_Return: "Return"
        default: "Key \(code)"
        }
    }
}

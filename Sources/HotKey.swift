import AppKit
import Carbon.HIToolbox

/// A key + modifiers pair, stored as strings like "cmd+space" or "ctrl+opt+k".
struct KeyCombo: Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    let key: String

    init?(_ spec: String) {
        var modifiers: UInt32 = 0
        var key: String?
        for part in spec.lowercased().split(separator: "+").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            switch part {
            case "cmd", "command": modifiers |= UInt32(cmdKey)
            case "opt", "option", "alt": modifiers |= UInt32(optionKey)
            case "ctrl", "control": modifiers |= UInt32(controlKey)
            case "shift": modifiers |= UInt32(shiftKey)
            default: key = part
            }
        }
        guard let key, let keyCode = Self.keyCodes[key] else { return nil }
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.key = key
    }

    /// From a key press in the shortcut recorder. Needs ⌘, ⌥ or ⌃ unless it's an F-key.
    init?(event: NSEvent) {
        guard let key = Self.keyCodes.first(where: { $0.value == UInt32(event.keyCode) })?.key else { return nil }
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let isFunctionKey = key.count > 1 && key.hasPrefix("f")
        guard isFunctionKey || !flags.subtracting(.shift).isEmpty else { return nil }
        let parts = [(NSEvent.ModifierFlags.control, "ctrl"), (.option, "opt"), (.shift, "shift"), (.command, "cmd")]
            .filter { flags.contains($0.0) }.map(\.1)
        self.init((parts + [key]).joined(separator: "+"))
    }

    var spec: String {
        let parts = [(controlKey, "ctrl"), (optionKey, "opt"), (shiftKey, "shift"), (cmdKey, "cmd")]
            .filter { modifiers & UInt32($0.0) != 0 }.map(\.1)
        return (parts + [key]).joined(separator: "+")
    }

    /// "⌃⌥⌘ K", in Apple's modifier order.
    var display: String {
        let symbols = [(controlKey, "⌃"), (optionKey, "⌥"), (shiftKey, "⇧"), (cmdKey, "⌘")]
            .filter { modifiers & UInt32($0.0) != 0 }.map(\.1).joined()
        let names = ["space": "Space", "return": "Return", "tab": "Tab", "escape": "Esc"]
        return symbols + " " + (names[key] ?? key.uppercased())
    }

    private static let keyCodes: [String: UInt32] = {
        let named: [String: Int] = [
            "space": kVK_Space, "return": kVK_Return, "tab": kVK_Tab, "escape": kVK_Escape,
            "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D, "e": kVK_ANSI_E,
            "f": kVK_ANSI_F, "g": kVK_ANSI_G, "h": kVK_ANSI_H, "i": kVK_ANSI_I, "j": kVK_ANSI_J,
            "k": kVK_ANSI_K, "l": kVK_ANSI_L, "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O,
            "p": kVK_ANSI_P, "q": kVK_ANSI_Q, "r": kVK_ANSI_R, "s": kVK_ANSI_S, "t": kVK_ANSI_T,
            "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X, "y": kVK_ANSI_Y,
            "z": kVK_ANSI_Z, "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3,
            "4": kVK_ANSI_4, "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8,
            "9": kVK_ANSI_9, "f1": kVK_F1, "f2": kVK_F2, "f3": kVK_F3, "f4": kVK_F4, "f5": kVK_F5,
            "f6": kVK_F6, "f7": kVK_F7, "f8": kVK_F8, "f9": kVK_F9, "f10": kVK_F10, "f11": kVK_F11,
            "f12": kVK_F12,
        ]
        return named.mapValues { UInt32($0) }
    }()
}

/// System-wide hotkey via Carbon. Needs no Accessibility permission.
final class HotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: () -> Void

    /// Fails when the combo is already taken by another app (e.g. Raycast still running).
    init?(combo: KeyCombo, action: @escaping () -> Void) {
        self.action = action
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue().action()
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
        guard installed == noErr else { return nil }

        let id = EventHotKeyID(signature: OSType(0x5450_415A), id: 1) // "TPAZ"
        let registered = RegisterEventHotKey(combo.keyCode, combo.modifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
        guard registered == noErr else { return nil }
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}

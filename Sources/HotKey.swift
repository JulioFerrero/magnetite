import AppKit
import Carbon.HIToolbox

struct KeyCombo: Equatable {
    let keyCode: UInt32, modifiers: UInt32, key: String

    private static let modifierKeys: [(name: String, carbon: Int, flag: NSEvent.ModifierFlags, symbol: String)] = [
        ("ctrl", controlKey, .control, "⌃"), ("opt", optionKey, .option, "⌥"), ("shift", shiftKey, .shift, "⇧"), ("cmd", cmdKey, .command, "⌘"),
    ]
    private static let aliases = ["control": "ctrl", "option": "opt", "alt": "opt", "command": "cmd"]
    private static let keyCodes: [String: UInt32] = {
        var codes = ["space": kVK_Space, "return": kVK_Return, "tab": kVK_Tab, "escape": kVK_Escape]
        for (code, key) in "asdfhgzxcv bqweryt123465 97 80 ou ip lj k    nm".enumerated() where key != " " { codes[String(key)] = code }
        for (i, code) in [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12].enumerated() {
            codes["f\(i + 1)"] = code
        }
        return codes.mapValues { UInt32($0) }
    }()

    init?(_ spec: String) {
        var modifiers: UInt32 = 0, key: String?
        for part in spec.lowercased().split(separator: "+").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            if let modifier = Self.modifierKeys.first(where: { $0.name == Self.aliases[part] ?? part }) {
                modifiers |= UInt32(modifier.carbon)
            } else {
                key = part
            }
        }
        guard let key, let keyCode = Self.keyCodes[key] else { return nil }
        (self.keyCode, self.modifiers, self.key) = (keyCode, modifiers, key)
    }

    init?(event: NSEvent) {
        guard let key = Self.keyCodes.first(where: { $0.value == UInt32(event.keyCode) })?.key else { return nil }
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard (key.count > 1 && key.hasPrefix("f")) || !flags.subtracting(.shift).isEmpty else { return nil }
        self.init((Self.modifierKeys.filter { flags.contains($0.flag) }.map(\.name) + [key]).joined(separator: "+"))
    }

    private var active: [(name: String, carbon: Int, flag: NSEvent.ModifierFlags, symbol: String)] {
        Self.modifierKeys.filter { modifiers & UInt32($0.carbon) != 0 }
    }
    var spec: String { (active.map(\.name) + [key]).joined(separator: "+") }
    var display: String {
        active.map(\.symbol).joined() + " " + (["space": "Space", "return": "Return", "tab": "Tab", "escape": "Esc"][key] ?? key.uppercased())
    }
}

final class HotKey {
    private var hotKeyRef: EventHotKeyRef?, handlerRef: EventHandlerRef?
    private let action: () -> Void

    init?(combo: KeyCombo, action: @escaping () -> Void) {
        self.action = action
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let handler: EventHandlerUPP = { _, _, me in
            if let me { Unmanaged<HotKey>.fromOpaque(me).takeUnretainedValue().action() }
            return noErr
        }
        guard InstallEventHandler(GetApplicationEventTarget(), handler, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handlerRef) == noErr,
              RegisterEventHotKey(combo.keyCode, combo.modifiers, EventHotKeyID(signature: 0x4D47_4E54, id: 1), GetApplicationEventTarget(), 0, &hotKeyRef) == noErr
        else { return nil }
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}

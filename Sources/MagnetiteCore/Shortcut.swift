import Carbon.HIToolbox

public struct KeyCombo: Equatable {
    public static let modifierNames = ["ctrl", "opt", "shift", "cmd"]
    private static let carbon = [controlKey, optionKey, shiftKey, cmdKey], symbols = ["⌃", "⌥", "⇧", "⌘"]
    private static let aliases = ["control": "ctrl", "option": "opt", "alt": "opt", "command": "cmd"]
    private static let keyNames = ["space": "Space", "return": "Return", "tab": "Tab", "escape": "Esc"]
    private static let keyCodes: [String: UInt32] = {
        var codes = ["space": kVK_Space, "return": kVK_Return, "tab": kVK_Tab, "escape": kVK_Escape]
        for (code, key) in "asdfhgzxcv bqweryt123465 97 80 ou ip lj k    nm".enumerated() where key != " " { codes[String(key)] = code }
        for (i, code) in [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12].enumerated() { codes["f\(i + 1)"] = code }
        return codes.mapValues { UInt32($0) }
    }()
    public let keyCode: UInt32, modifiers: UInt32, key: String
    private var active: [Int] { Self.carbon.indices.filter { modifiers & UInt32(Self.carbon[$0]) != 0 } }
    public var spec: String { (active.map { Self.modifierNames[$0] } + [key]).joined(separator: "+") }
    public var display: String { active.map { Self.symbols[$0] }.joined() + " " + (Self.keyNames[key] ?? key.uppercased()) }
    public init?(_ spec: String) {
        var modifiers: UInt32 = 0, key: String?
        for part in spec.lowercased().split(separator: "+").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            if let i = Self.modifierNames.firstIndex(of: Self.aliases[part] ?? part) { modifiers |= UInt32(Self.carbon[i]) } else { key = part }
        }
        guard let key, let keyCode = Self.keyCodes[key] else { return nil }
        (self.keyCode, self.modifiers, self.key) = (keyCode, modifiers, key)
    }
    public init?(keyCode: UInt16, modifiers: [String]) {
        guard let key = Self.keyCodes.first(where: { $0.value == UInt32(keyCode) })?.key,
              (key.count > 1 && key.hasPrefix("f")) || modifiers.contains(where: { $0 != "shift" }) else { return nil }
        self.init((Self.modifierNames.filter(modifiers.contains) + [key]).joined(separator: "+"))
    }
}

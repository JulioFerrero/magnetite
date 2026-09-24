import AppKit
import Carbon.HIToolbox
import MagnetiteCore

enum ShortcutPrompt {
    static func run(current: KeyCombo, register: @escaping (KeyCombo) -> Bool) {
        let alert = NSAlert(), previous = NSWorkspace.shared.frontmostApplication
        (alert.messageText, alert.informativeText) = ("Press a new shortcut", "Magnetite opens with \(current.display). Esc cancels.")
        alert.addButton(withTitle: "Cancel")
        let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let modifiers = zip([.control, .option, .shift, .command] as [NSEvent.ModifierFlags], KeyCombo.modifierNames).filter { event.modifierFlags.contains($0.0) }.map(\.1)
            if let combo = KeyCombo(keyCode: event.keyCode, modifiers: modifiers) {
                if register(combo) { NSApp.stopModal() } else { alert.informativeText = "macOS refused \(combo.display); another app is probably using it." }
            } else if Int(event.keyCode) == kVK_Escape, modifiers.isEmpty {
                NSApp.stopModal()
            } else {
                NSSound.beep()
                alert.informativeText = "Use ⌘, ⌥ or ⌃ with a key. F-keys work alone."
            }
            return nil
        }
        NSApp.activate()
        alert.runModal()
        if let monitor { NSEvent.removeMonitor(monitor) }
        if previous != NSRunningApplication.current { previous?.activate() }
    }
}

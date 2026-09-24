import AppKit
import Carbon.HIToolbox
import MagnetiteCore
import SwiftUI

final class SettingsWindow: NSWindowController, NSWindowDelegate, ObservableObject {
    @Published var shortcut: KeyCombo
    @Published var look: Look { didSet { applyLook(look) } }
    @Published var isRecording = false
    @Published var error: String?
    private let register: (KeyCombo?) -> Bool, applyLook: (Look) -> Void
    private var monitor: Any?, previousApp: NSRunningApplication?
    init(shortcut: KeyCombo, look: Look, register: @escaping (KeyCombo?) -> Bool, applyLook: @escaping (Look) -> Void) {
        (self.shortcut, self.look, self.register, self.applyLook) = (shortcut, look, register, applyLook)
        super.init(window: nil)
        let hosting = NSHostingController(rootView: SettingsView(model: self))
        hosting.sizingOptions = .preferredContentSize
        window = NSWindow(contentViewController: hosting)
        (window!.title, window!.styleMask, window!.isReleasedWhenClosed, window!.delegate) = ("Magnetite Settings", [.titled, .closable], false, self)
        window!.center()
    }
    required init?(coder: NSCoder) { fatalError() }
    func present() {
        if window?.isVisible != true { previousApp = NSWorkspace.shared.frontmostApplication }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
    func windowWillClose(_ notification: Notification) {
        stopRecording()
        if previousApp != NSRunningApplication.current { previousApp?.activate() }
        previousApp = nil
    }
    func startRecording() {
        (error, isRecording) = (nil, true)
        _ = register(nil)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] in self?.record($0) ?? nil }
    }
    func stopRecording() {
        guard isRecording, let monitor else { return }
        NSEvent.removeMonitor(monitor)
        (self.monitor, isRecording) = (nil, false)
        _ = register(shortcut)
    }
    private func record(_ event: NSEvent) -> NSEvent? {
        let flags: [NSEvent.ModifierFlags] = [.control, .option, .shift, .command]
        let modifiers = zip(flags, KeyCombo.modifierNames).filter { event.modifierFlags.contains($0.0) }.map(\.1)
        guard let combo = KeyCombo(keyCode: event.keyCode, modifiers: modifiers) else {
            if Int(event.keyCode) == kVK_Escape, modifiers.isEmpty { stopRecording() } else { NSSound.beep() }
            error = isRecording ? "Use ⌘, ⌥ or ⌃ with a letter, number, Space, Return or Tab (or an F-key alone)." : nil
            return nil
        }
        let registered = register(combo)
        if registered { UserDefaults.standard.set(combo.spec, forKey: "hotkey") }
        (shortcut, error) = registered ? (combo, nil) : (shortcut, "macOS refused \(combo.display); another app is probably using it.")
        stopRecording()
        return nil
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsWindow
    var body: some View {
        Form {
            Section {
                LabeledContent("Open Magnetite") {
                    if model.isRecording {
                        Button("Press a shortcut…", action: model.stopRecording).buttonStyle(.glassProminent)
                    } else {
                        Button(model.shortcut.display, action: model.startRecording).buttonStyle(.glass)
                    }
                }
                if let error = model.error { Text(error).font(.callout).foregroundStyle(.red) }
            } header: { Text("Shortcut") } footer: {
                Text("Click the shortcut, then press the new combination. Esc cancels.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Theme") {
                Picker("Theme", selection: $model.look) {
                    ForEach(Look.allCases) { look in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(look.title)
                            Text(look.summary).font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 2).tag(look)
                    }
                }.pickerStyle(.radioGroup).labelsHidden()
            }
        }.formStyle(.grouped).frame(width: 460).fixedSize(horizontal: false, vertical: true)
    }
}

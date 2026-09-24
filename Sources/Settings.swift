import AppKit
import Carbon.HIToolbox
import SwiftUI

final class SettingsModel: ObservableObject {
    @Published var shortcut: KeyCombo
    @Published var look: Look { didSet { applyLook(look) } }
    @Published var isRecording = false
    @Published var error: String?
    private let register: (KeyCombo?) -> Bool, applyLook: (Look) -> Void
    private var monitor: Any?

    init(shortcut: KeyCombo, look: Look, register: @escaping (KeyCombo?) -> Bool, applyLook: @escaping (Look) -> Void) {
        self.shortcut = shortcut
        self.look = look
        self.register = register
        self.applyLook = applyLook
    }

    func startRecording() {
        (error, isRecording) = (nil, true)
        _ = register(nil)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] in
            self?.record($0)
            return nil
        }
    }

    func stopRecording() {
        guard isRecording, let monitor else { return }
        NSEvent.removeMonitor(monitor)
        (self.monitor, isRecording) = (nil, false)
        _ = register(shortcut)
    }

    private func record(_ event: NSEvent) {
        if Int(event.keyCode) == kVK_Escape, event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty { return stopRecording() }
        guard let combo = KeyCombo(event: event) else {
            error = "Use ⌘, ⌥ or ⌃ with a letter, number, Space, Return or Tab (or an F-key alone)."
            return NSSound.beep()
        }
        if register(combo) {
            shortcut = combo
            UserDefaults.standard.set(combo.spec, forKey: "hotkey")
        } else {
            error = "macOS refused \(combo.display); another app is probably using it."
        }
        stopRecording()
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

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
            } header: {
                Text("Shortcut")
            } footer: {
                Text("Click the shortcut, then press the new combination. Esc cancels.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Theme") {
                Picker("Theme", selection: $model.look) {
                    ForEach(Look.allCases) { look in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(look.title)
                            Text(look.summary).font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                        .tag(look)
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}

final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private var model: SettingsModel?
    private var previousApp: NSRunningApplication?

    convenience init(model: SettingsModel) {
        let hosting = NSHostingController(rootView: SettingsView(model: model))
        hosting.sizingOptions = .preferredContentSize
        let window = NSWindow(contentViewController: hosting)
        window.title = "Magnetite Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        self.init(window: window)
        self.model = model
        window.delegate = self
        window.center()
    }

    func present() {
        if window?.isVisible != true { previousApp = NSWorkspace.shared.frontmostApplication }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        model?.stopRecording()
        if previousApp != NSRunningApplication.current { previousApp?.activate() }
        previousApp = nil
    }
}

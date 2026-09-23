import AppKit
import Carbon.HIToolbox
import SwiftUI

/// State behind the Settings window. Changes apply immediately.
final class SettingsModel: ObservableObject {
    @Published var shortcut: KeyCombo
    @Published var look: Look
    @Published var isRecording = false
    @Published var error: String?

    /// Registers a combo as the global hotkey (nil pauses it). False if macOS refuses it.
    private let registerShortcut: (KeyCombo?) -> Bool
    private let applyLook: (Look) -> Void
    private var monitor: Any?

    init(shortcut: KeyCombo, look: Look, registerShortcut: @escaping (KeyCombo?) -> Bool, applyLook: @escaping (Look) -> Void) {
        self.shortcut = shortcut
        self.look = look
        self.registerShortcut = registerShortcut
        self.applyLook = applyLook
    }

    func select(_ look: Look) {
        self.look = look
        applyLook(look)
    }

    /// The current hotkey is paused while recording, so pressing it again is
    /// captured here instead of toggling the launcher.
    func startRecording() {
        error = nil
        isRecording = true
        _ = registerShortcut(nil)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.record(event)
            return nil
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
        _ = registerShortcut(shortcut)
    }

    private func record(_ event: NSEvent) {
        let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if Int(event.keyCode) == kVK_Escape, mods.isEmpty {
            stopRecording()
            return
        }
        guard let combo = KeyCombo(event: event) else {
            error = "Use ⌘, ⌥ or ⌃ with a letter, number, Space, Return or Tab (or an F-key alone)."
            NSSound.beep()
            return
        }
        if registerShortcut(combo) {
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
                LabeledContent("Open Topaz") {
                    if model.isRecording {
                        Button("Press a shortcut…") { model.stopRecording() }
                            .buttonStyle(.glassProminent)
                    } else {
                        Button(model.shortcut.display) { model.startRecording() }
                            .buttonStyle(.glass)
                    }
                }
                if let error = model.error {
                    Text(error).font(.callout).foregroundStyle(.red)
                }
            } header: {
                Text("Shortcut")
            } footer: {
                Text("Click the shortcut, then press the new combination. Esc cancels.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Theme") {
                Picker("Theme", selection: Binding(get: { model.look }, set: { model.select($0) })) {
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
    private let model: SettingsModel
    private var previousApp: NSRunningApplication?

    init(model: SettingsModel) {
        self.model = model
        let hosting = NSHostingController(rootView: SettingsView(model: model))
        hosting.sizingOptions = .preferredContentSize
        let window = NSWindow(contentViewController: hosting)
        window.title = "Topaz Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        window.center()
    }

    required init?(coder: NSCoder) { fatalError() }

    func present() {
        if window?.isVisible != true {
            previousApp = NSWorkspace.shared.frontmostApplication
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    /// Hand focus back to whatever you were using before opening Settings.
    func windowWillClose(_ notification: Notification) {
        model.stopRecording()
        if let previousApp, previousApp != NSRunningApplication.current {
            previousApp.activate()
        }
        previousApp = nil
    }
}

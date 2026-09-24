import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: SearchController!
    private var settings: SettingsWindowController?
    private var hotKey: HotKey?, retryTimer: Timer?, activity: NSObjectProtocol?
    private var savedShortcut: KeyCombo { KeyCombo(UserDefaults.standard.string(forKey: "hotkey") ?? "") ?? KeyCombo("cmd+space")! }

    func applicationDidFinishLaunching(_ notification: Notification) {
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical], reason: "Show Magnetite the instant its hotkey is pressed")
        NSApp.mainMenu = mainMenu()
        controller = SearchController()
        controller.onOpenSettings = { [weak self] in self?.openSettings() }
        let shortcut = savedShortcut
        if !setHotKey(shortcut) {
            retryTimer = .scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] timer in
                guard let hotKey = self?.makeHotKey(shortcut) else { return }
                self?.hotKey = hotKey
                timer.invalidate()
            }
        }
        let defaults = UserDefaults.standard
        if Bundle.main.bundlePath.hasPrefix("/Applications/"), !defaults.bool(forKey: "didRegisterLoginItem"), (try? SMAppService.mainApp.register()) != nil {
            defaults.set(true, forKey: "didRegisterLoginItem")
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        controller.show()
        return false
    }

    @objc func openSettings() {
        settings = settings ?? SettingsWindowController(model: SettingsModel(
            shortcut: savedShortcut, look: .current,
            register: { [weak self] in self?.setHotKey($0) ?? false },
            applyLook: { [weak self] in
                Look.current = $0
                self?.controller.apply($0)
            }))
        settings?.present()
    }

    private func makeHotKey(_ combo: KeyCombo) -> HotKey? { HotKey(combo: combo) { [weak self] in self?.controller.toggle() } }

    private func setHotKey(_ combo: KeyCombo?) -> Bool {
        retryTimer?.invalidate()
        hotKey = nil
        hotKey = combo.flatMap(makeHotKey)
        return combo == nil || hotKey != nil
    }

    private func mainMenu() -> NSMenu {
        let bar = NSMenu()
        for items in [
            [("Settings…", #selector(openSettings), ","), ("Close Window", #selector(NSWindow.performClose(_:)), "w"), ("Quit Magnetite", #selector(NSApplication.terminate(_:)), "q")],
            [("Undo", Selector(("undo:")), "z"), ("Redo", Selector(("redo:")), "Z"), ("Cut", #selector(NSText.cut(_:)), "x"),
             ("Copy", #selector(NSText.copy(_:)), "c"), ("Paste", #selector(NSText.paste(_:)), "v"), ("Select All", #selector(NSText.selectAll(_:)), "a")],
        ] {
            let menu = NSMenu()
            for (title, action, key) in items {
                menu.addItem(withTitle: title, action: action, keyEquivalent: key).target = action == #selector(openSettings) ? self : nil
            }
            bar.addItem(withTitle: "", action: nil, keyEquivalent: "").submenu = menu
        }
        return bar
    }
}

let app = NSApplication.shared, delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

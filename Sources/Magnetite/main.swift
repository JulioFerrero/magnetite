import AppKit
import MagnetiteCore
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private lazy var controller = LauncherController()
    private var hotKey: HotKey?, retryTimer: Timer?, activity: NSObjectProtocol?
    private var shortcut: KeyCombo { KeyCombo(UserDefaults.standard.string(forKey: "hotkey") ?? "") ?? KeyCombo("cmd+space")! }
    func applicationDidFinishLaunching(_ notification: Notification) {
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical], reason: "Show Magnetite the instant its hotkey is pressed")
        NSApp.mainMenu = mainMenu()
        controller.onChangeShortcut = { [weak self] in self?.changeShortcut() }
        if !setHotKey(shortcut) {
            retryTimer = .scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self, combo = shortcut] in if self?.setHotKey(combo) != false { $0.invalidate() } }
        }
        if Bundle.main.bundlePath.hasPrefix("/Applications/"), !UserDefaults.standard.bool(forKey: "didRegisterLoginItem"), (try? SMAppService.mainApp.register()) != nil {
            UserDefaults.standard.set(true, forKey: "didRegisterLoginItem")
        }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        controller.show()
        return false
    }
    @objc func changeShortcut() {
        retryTimer?.invalidate()
        hotKey = nil
        ShortcutPrompt.run(current: shortcut) { [weak self] combo in
            guard self?.setHotKey(combo) == true else { return false }
            UserDefaults.standard.set(combo.spec, forKey: "hotkey")
            return true
        }
        if hotKey == nil { _ = setHotKey(shortcut) }
    }
    private func setHotKey(_ combo: KeyCombo) -> Bool {
        hotKey = nil
        hotKey = HotKey(combo: combo) { [weak self] in self?.controller.toggle() }
        return hotKey != nil
    }
    private func mainMenu() -> NSMenu {
        let bar = NSMenu()
        for items in [[("Change Shortcut…", #selector(changeShortcut), ","), ("Quit Magnetite", #selector(NSApplication.terminate(_:)), "q")],
                      [("Undo", Selector(("undo:")), "z"), ("Redo", Selector(("redo:")), "Z"), ("Cut", #selector(NSText.cut(_:)), "x"),
                       ("Copy", #selector(NSText.copy(_:)), "c"), ("Paste", #selector(NSText.paste(_:)), "v"), ("Select All", #selector(NSText.selectAll(_:)), "a")]] {
            let menu = NSMenu()
            for (title, action, key) in items { menu.addItem(withTitle: title, action: action, keyEquivalent: key).target = action == #selector(changeShortcut) ? self : nil }
            bar.addItem(withTitle: "", action: nil, keyEquivalent: "").submenu = menu
        }
        return bar
    }
}

let app = NSApplication.shared, delegate = AppDelegate()
app.delegate = delegate
app.run()

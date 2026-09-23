import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: SearchController!
    private var settings: SettingsWindowController?
    private var hotKey: HotKey?
    private var retryTimer: Timer?
    private var activity: NSObjectProtocol?

    private var savedShortcut: KeyCombo {
        KeyCombo(UserDefaults.standard.string(forKey: "hotkey") ?? "") ?? KeyCombo("cmd+space")!
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // An idle background app gets App Nap: throttled and parked on slow cores,
        // which adds milliseconds to every hotkey press. Opt out; idle cost stays 0.
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical],
            reason: "Show the launcher the instant its hotkey is pressed"
        )
        NSApp.mainMenu = makeMainMenu()
        controller = SearchController()
        controller.onOpenSettings = { [weak self] in self?.openSettings() }
        registerHotKeyAtLaunch()
        registerLoginItemOnce()
    }

    @objc func openSettings() {
        if settings == nil {
            let model = SettingsModel(
                shortcut: savedShortcut,
                look: .current,
                registerShortcut: { [weak self] combo in self?.useHotKey(combo) ?? false },
                applyLook: { [weak self] look in
                    Look.current = look
                    self?.controller.apply(look)
                }
            )
            settings = SettingsWindowController(model: model)
        }
        settings?.present()
    }

    /// `open -a Launcher` (or double-clicking the app) while it's running shows the window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        controller.show()
        return false
    }

    /// Registers `combo` as the global hotkey, replacing the current one (nil
    /// just unregisters). False if macOS refuses it.
    private func useHotKey(_ combo: KeyCombo?) -> Bool {
        hotKey = nil
        retryTimer?.invalidate()
        retryTimer = nil
        guard let combo else { return true }
        hotKey = HotKey(combo: combo) { [weak self] in self?.controller.toggle() }
        return hotKey != nil
    }

    /// At login another app may briefly hold the shortcut; keep retrying until it's free.
    private func registerHotKeyAtLaunch() {
        let combo = savedShortcut
        guard !useHotKey(combo) else { return }
        NSLog("Launcher: %@ is taken by another app; retrying until it's free", combo.spec)
        retryTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] timer in
            guard let self, let hotKey = HotKey(combo: combo, action: { [weak self] in self?.controller.toggle() }) else { return }
            self.hotKey = hotKey
            timer.invalidate()
            self.retryTimer = nil
        }
    }

    /// Adds itself to Login Items once, only when installed in /Applications.
    /// Turning it off later in System Settings sticks.
    private func registerLoginItemOnce() {
        let key = "didRegisterLoginItem"
        guard Bundle.main.bundlePath.hasPrefix("/Applications/"), !UserDefaults.standard.bool(forKey: key) else { return }
        do {
            try SMAppService.mainApp.register()
            UserDefaults.standard.set(true, forKey: key)
        } catch {
            NSLog("Launcher: couldn't add login item: %@", error.localizedDescription)
        }
    }

    /// Never visible (no Dock icon or menu bar), but it's what makes ⌘A/⌘C/⌘V/⌘Z
    /// work in the search field, ⌘, open Settings, ⌘W close it and ⌘Q quit.
    private func makeMainMenu() -> NSMenu {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        appMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        appMenu.addItem(withTitle: "Quit Launcher", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)
        return main
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

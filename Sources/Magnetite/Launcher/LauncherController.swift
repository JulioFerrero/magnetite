import AppKit
import Carbon.HIToolbox
import MagnetiteCore

final class LauncherController: NSObject, NSWindowDelegate {
    var onOpenSettings: (() -> Void)?
    private let window = LauncherWindow(), bar = SearchBar(), list = ResultsList(), footer = Footer(), history = History()
    private let scanQueue = DispatchQueue(label: "magnetite.scan", qos: .userInitiated, autoreleaseFrequency: .workItem)
    private var state = LauncherState(), apps: [AppEntry] = [], stamps: Catalog.Stamps = [:], isShown = false
    private var keyMonitor: Any?, runningObservation: NSKeyValueObservation?
    func toggle() { isShown ? hide() : show() }
    func windowDidResignKey(_ notification: Notification) { hide() }
    override init() {
        super.init()
        list.fill(window.content)
        bar.place(in: window.content, top: 0, leading: 0, trailing: 0, height: Theme.headerHeight)
        footer.place(in: window.content, bottom: Theme.pillInset, trailing: Theme.pillInset)
        (window.delegate, window.background.onClick) = (self, { [weak self] in self?.hide() })
        (bar.onChange, bar.onCommand) = ({ [weak self] in self?.reload() }, { [weak self] in self?.perform($0) ?? false })
        (list.table.onHover, list.table.onClick) = ({ [weak self] in self?.hover($0) }, { [weak self] in self?.select($0, open: true) })
        list.onForget = { [weak self] app in
            self?.history.forget(app)
            self?.reload()
        }
        (footer.openButton.onClick, footer.actionsButton.onClick) = ({ [weak self] in self?.openSelected() }, { [weak self] in self?.showActions() })
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] in self?.handleKey($0) ?? $0 }
        apply(.current)
        runningObservation = NSWorkspace.shared.observe(\.runningApplications, options: .initial) { [weak self] workspace, _ in
            let ids = Set(workspace.runningApplications.compactMap(\.bundleIdentifier))
            DispatchQueue.main.async { self?.list.running = ids }
        }
        refreshIndex()
    }
    func show() {
        guard !isShown else { return }
        isShown = true
        window.reveal(focusing: bar.field)
        refreshIndex()
    }
    func hide() {
        guard isShown else { return }
        isShown = false
        window.park()
        DispatchQueue.main.async { self.bar.clear() }
    }
    func apply(_ look: Look) {
        hide()
        window.apply(look)
        footer.apply(look)
        list.apply(look)
        window.contentView?.layoutSubtreeIfNeeded()
        reload()
        window.park()
    }
    private func refreshIndex() {
        scanQueue.async { [self, stamps] in
            guard !Catalog.isUnchanged(stamps) else { return }
            let (scanned, newStamps) = Catalog.scan()
            DispatchQueue.main.async { [self] in
                self.stamps = newStamps
                guard scanned != apps else { return }
                apps = scanned
                list.prewarm(scanned)
                reload()
            }
        }
    }
    private func reload() {
        state.load(apps, query: bar.text, history: history, suggestions: Theme.suggestionCount)
        footer.openButton.isEnabled = state.selected != nil
        list.reload(state)
    }
    private func select(_ row: Int, open: Bool = false) {
        guard state.app(at: row) != nil else { return }
        state.selected = row
        list.update(state, animated: true)
        if open { openSelected() }
    }
    private func hover(_ row: Int?) {
        state.hovered = state.app(at: row)
        list.update(state)
    }
    private func move(by delta: Int) {
        guard let step = state.step(delta) else { return }
        select(step.row)
        list.table.scrollRowToVisible(step.reveal)
    }
    @objc private func openSelected() {
        guard let app = state.selectedApp else { return }
        history.record(app, query: bar.text)
        hide()
        NSWorkspace.shared.openApplication(at: app.url, configuration: NSWorkspace.OpenConfiguration())
    }
    @objc private func revealSelected() {
        guard let app = state.selectedApp else { return }
        hide()
        NSWorkspace.shared.activateFileViewerSelecting([app.url])
    }
    @objc private func openSettings() {
        hide()
        onOpenSettings?()
    }
    private func showActions() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for (title, action, mask) in [("Open Application", #selector(openSelected), NSEvent.ModifierFlags()), ("Show in Finder", #selector(revealSelected), .command)] {
            let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "\r")
            (item.target, item.keyEquivalentModifierMask, item.isEnabled) = (self, mask, state.selectedApp != nil)
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "Quit Magnetite", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: footer.actionsButton.bounds.height + menu.size.height + 6), in: footer.actionsButton)
    }
    private func perform(_ selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveUp(_:)): move(by: -1)
        case #selector(NSResponder.moveDown(_:)): move(by: 1)
        case #selector(NSResponder.insertNewline(_:)): openSelected()
        case #selector(NSResponder.cancelOperation(_:)): if bar.text.isEmpty { hide() } else { bar.clear() }
        case #selector(NSResponder.insertTab(_:)), #selector(NSResponder.insertBacktab(_:)): break
        default: return false
        }
        return true
    }
    private func handleKey(_ event: NSEvent) -> NSEvent? {
        guard event.window === window else { return event }
        switch (Int(event.keyCode), event.modifierFlags.intersection([.command, .option, .control, .shift])) {
        case (kVK_Return, .command), (kVK_ANSI_KeypadEnter, .command): revealSelected()
        case (kVK_ANSI_K, .command): showActions()
        case (kVK_ANSI_Comma, .command): openSettings()
        case (kVK_ANSI_J, .control): move(by: 1)
        case (kVK_ANSI_K, .control): move(by: -1)
        default: return event
        }
        return nil
    }
}

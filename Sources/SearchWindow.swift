import AppKit
import Carbon.HIToolbox

// MARK: - Controller

final class SearchController: NSObject, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate {
    private enum Row {
        case header(String)
        case app(AppEntry)

        var isApp: Bool {
            if case .app = self { return true }
            return false
        }
    }

    var onOpenSettings: (() -> Void)?

    private var look = Look.current
    private let panel = LauncherPanel(size: Look.current.panelSize)
    private let windowContent = PanelBackground()
    private let root = NSView()
    private let pillHost = NSView()
    private let pillContent = NSStackView()
    /// Theme-specific views (background, shadow, pill, selection lens), swapped by `apply(_:)`.
    private var chrome: [NSView] = []
    private var lens: NSGlassEffectView?
    private let field = NSTextField()
    private let placeholder = NSTextField(labelWithString: "")
    private let table = ListTable()
    private let scrollView = NSScrollView()
    private let listContainer = NSView()
    private let fade = CAGradientLayer()
    private let emptyLabel = NSTextField(labelWithString: "")
    private let openButton = FooterButton(title: "Open Application", keys: ["↵"], color: Theme.primaryText)
    private let actionsButton = FooterButton(title: "Actions", keys: ["⌘", "K"], color: Theme.secondaryText)

    private let usage = Usage()
    private let icons = IconCache(size: Theme.iconSize)
    // .workItem: release each scan's temporaries (every Info.plist read) when it
    // finishes, instead of whenever the worker thread happens to exit.
    private let scanQueue = DispatchQueue(label: "magnetite.scan", qos: .userInitiated, autoreleaseFrequency: .workItem)
    private var apps: [AppEntry] = []
    private var folderStamps: AppIndex.Stamps = [:]
    private var runningIDs: Set<String> = []
    private var isShown = false
    private var rows: [Row] = []
    /// Rows of the "Suggestions" section (your history); they get a remove button.
    private var suggestedRows = 0..<0
    private var selected: Int?
    private var hovered: Int?
    private var keyMonitor: Any?
    private var runningObservation: NSKeyValueObservation?

    override init() {
        super.init()
        buildUI()
        observeRunningApps()
        refreshIndex()
    }

    // MARK: Show / hide

    func toggle() {
        isShown ? hide() : show()
    }

    /// The window never leaves the screen: hidden, it's invisible and
    /// click-through (see `park()`). Showing is an alpha change plus keyboard
    /// focus. No window-server reordering, and the list was already reset and
    /// drawn right after the last hide.
    func show() {
        guard !isShown else { return }
        isShown = true
        position()
        panel.ignoresMouseEvents = false
        // Take keyboard focus before becoming visible (~4ms round trip through the
        // window server). Liquid Glass draws unfocused windows as flat, lighter
        // "inactive" glass, so showing first flashes that for a frame.
        panel.makeKey()
        if (panel.firstResponder as? NSTextView)?.delegate !== field { // stays focused between shows
            panel.makeFirstResponder(field)
        }
        panel.alphaValue = 1
        CATransaction.flush() // hand the now-visible frame to the window server right away
        if let editor = panel.fieldEditor(false, for: field) as? NSTextView {
            editor.insertionPointColor = Theme.primaryText
            editor.selectedTextAttributes = [.backgroundColor: Theme.textSelection]
        }
        refreshIndex() // picks up apps installed or removed since last time
    }

    func hide() {
        guard isShown else { return }
        isShown = false
        park()
        DispatchQueue.main.async { self.resetForNextShow() }
    }

    /// Invisible and click-through, but still ordered in. If it has keyboard
    /// focus, ordering out and back in is the only public way to hand focus back
    /// to the app underneath.
    private func park() {
        panel.alphaValue = 0
        panel.ignoresMouseEvents = true
        if panel.isKeyWindow || !panel.isVisible {
            panel.orderOut(nil)
            panel.orderFront(nil)
        }
    }

    private func resetForNextShow() {
        field.stringValue = ""
        update()
    }

    /// Keeps the running-app dots current as apps launch and quit, so showing
    /// the window never waits on the (~10ms) running-apps query.
    private func observeRunningApps() {
        runningObservation = NSWorkspace.shared.observe(\.runningApplications, options: [.initial]) { [weak self] workspace, _ in
            let ids = Set(workspace.runningApplications.compactMap(\.bundleIdentifier))
            DispatchQueue.main.async { self?.markRunningApps(ids) }
        }
    }

    private func markRunningApps(_ ids: Set<String>) {
        runningIDs = ids
        let visible = table.rows(in: table.visibleRect)
        for row in visible.lowerBound..<(visible.lowerBound + visible.length) where rows.indices.contains(row) {
            guard case .app(let app) = rows[row],
                  let cell = table.view(atColumn: 0, row: row, makeIfNecessary: false) as? AppCell else { continue }
            cell.runningDot.isHidden = !runningIDs.contains(app.id)
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }

    /// Centered horizontally on the screen with the pointer, a bit above center.
    private func position() {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main else { return }
        let area = screen.visibleFrame
        let size = Theme.windowSize
        let top = area.maxY - area.height * Theme.topOffsetRatio
        let card = NSPoint(x: (area.midX - size.width / 2).rounded(), y: (top - size.height).rounded())
        let origin = NSPoint(x: card.x - look.margin.left, y: card.y - look.margin.bottom)
        if panel.frame.origin != origin { panel.setFrameOrigin(origin) }
    }

    private func refreshIndex() {
        let stamps = folderStamps
        scanQueue.async { [weak self] in
            guard !AppIndex.isUnchanged(stamps) else { return }
            let (scanned, newStamps) = AppIndex.scan()
            DispatchQueue.main.async {
                guard let self else { return }
                self.folderStamps = newStamps
                guard scanned != self.apps else { return }
                self.apps = scanned
                self.icons.prewarm(scanned)
                self.update()
            }
        }
    }

    // MARK: Results

    private func update() {
        let query = field.stringValue.trimmingCharacters(in: .whitespaces)
        if query.isEmpty {
            let suggested = usage.suggestions(apps, limit: Theme.suggestionCount)
            let suggestedIDs = Set(suggested.map(\.id))
            rows = []
            if !suggested.isEmpty {
                rows.append(.header("Suggestions"))
                rows += suggested.map(Row.app)
            }
            suggestedRows = suggested.isEmpty ? 0..<0 : 1..<rows.count
            rows.append(.header("Applications"))
            rows += apps.filter { !suggestedIDs.contains($0.id) }.map(Row.app)
        } else {
            let results = usage.rank(apps, query: query)
            rows = results.isEmpty ? [] : [.header("Results")] + results.map(Row.app)
            suggestedRows = 0..<0
        }
        selected = rows.firstIndex(where: \.isApp)
        hovered = nil
        placeholder.isHidden = !field.stringValue.isEmpty
        table.reloadData()
        moveLens(animated: false)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: -Theme.listTopInset))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        emptyLabel.isHidden = !rows.isEmpty
        openButton.isEnabled = selected != nil
        updateFade()
    }

    private var selectedApp: AppEntry? {
        guard let selected, case .app(let app) = rows[selected] else { return nil }
        return app
    }

    private func highlight(for row: Int) -> RowView.Highlight {
        row == selected ? .selected : row == hovered ? .hovered : .none
    }

    private func refreshHighlights(_ changed: [Int?]) {
        for row in changed.compactMap({ $0 }) where rows.indices.contains(row) {
            (table.rowView(atRow: row, makeIfNecessary: false) as? RowView)?.highlight = highlight(for: row)
        }
    }

    private func select(_ index: Int) {
        guard rows.indices.contains(index), rows[index].isApp, index != selected else { return }
        let previous = selected
        selected = index
        refreshHighlights([previous, index])
        moveLens(animated: true)
    }

    private func hover(_ index: Int?) {
        let index = index.flatMap { rows.indices.contains($0) && rows[$0].isApp ? $0 : nil }
        guard index != hovered else { return }
        let previous = hovered
        hovered = index
        refreshHighlights([previous, index])
    }

    /// Moves the selection, skipping section headers, and keeps the header of the
    /// first row in a section visible when scrolling up to it.
    private func move(by delta: Int) {
        guard let current = selected else { return }
        var next = current + delta
        while rows.indices.contains(next), !rows[next].isApp { next += delta }
        guard rows.indices.contains(next) else { return }
        select(next)
        let reveal = next > 0 && !rows[next - 1].isApp ? next - 1 : next
        table.scrollRowToVisible(delta < 0 ? reveal : next)
    }

    @objc private func openSelected() {
        guard let app = selectedApp else { return }
        usage.record(app, query: field.stringValue)
        hide()
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: app.url, configuration: config) { _, error in
            if let error { NSLog("Magnetite: failed to open %@: %@", app.url.path, error.localizedDescription) }
        }
    }

    private func forget(_ app: AppEntry) {
        usage.forget(app)
        update()
    }

    private func clearHistory() {
        usage.forgetAll()
        update()
    }

    @objc private func revealSelected() {
        guard let app = selectedApp else { return }
        hide()
        NSWorkspace.shared.activateFileViewerSelecting([app.url])
    }

    @objc private func showActions() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let open = NSMenuItem(title: "Open Application", action: #selector(openSelected), keyEquivalent: "\r")
        open.keyEquivalentModifierMask = []
        let reveal = NSMenuItem(title: "Show in Finder", action: #selector(revealSelected), keyEquivalent: "\r")
        reveal.keyEquivalentModifierMask = .command
        for item in [open, reveal] {
            item.target = self
            item.isEnabled = selectedApp != nil
        }
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        let quit = NSMenuItem(title: "Quit Magnetite", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.items = [open, reveal, .separator(), settings, quit]
        // Open upward from the Actions button, like Raycast's action panel.
        let origin = NSPoint(x: 0, y: actionsButton.bounds.height + menu.size.height + 6)
        menu.popUp(positioning: nil, at: origin, in: actionsButton)
    }

    @objc private func openSettings() {
        hide()
        onOpenSettings?()
    }

    // MARK: Keyboard

    func controlTextDidChange(_ obj: Notification) {
        update()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveUp(_:)): move(by: -1)          // ↑ and ⌃P
        case #selector(NSResponder.moveDown(_:)): move(by: 1)         // ↓ and ⌃N
        case #selector(NSResponder.insertNewline(_:)): openSelected()
        case #selector(NSResponder.cancelOperation(_:)):              // Esc: clear, then close
            if field.stringValue.isEmpty { hide() } else { field.stringValue = ""; update() }
        case #selector(NSResponder.insertTab(_:)), #selector(NSResponder.insertBacktab(_:)): break
        default: return false
        }
        return true
    }

    /// ⌘↵ reveals in Finder, ⌘K opens actions, ⌘, settings, ⌃J/⌃K move like ⌃N/⌃P.
    private func handleKey(_ event: NSEvent) -> NSEvent? {
        guard event.window === panel else { return event }
        let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
        switch (Int(event.keyCode), mods) {
        case (kVK_Return, .command), (kVK_ANSI_KeypadEnter, .command): revealSelected()
        case (kVK_ANSI_K, .command): showActions()
        case (kVK_ANSI_Comma, .command): openSettings()
        case (kVK_ANSI_J, .control): move(by: 1)
        case (kVK_ANSI_K, .control): move(by: -1)
        default: return event
        }
        return nil
    }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        switch rows[row] {
        case .app: Theme.rowHeight
        case .header(let title): title == "Suggestions" ? Theme.sectionHeight + Theme.clearButtonGap : Theme.sectionHeight
        }
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let view = tableView.makeView(withIdentifier: RowView.identifier, owner: nil) as? RowView ?? RowView()
        view.identifier = RowView.identifier
        view.highlight = highlight(for: row)
        view.drawsSelection = lens == nil
        return view
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        switch rows[row] {
        case .header(let title):
            let cell = tableView.makeView(withIdentifier: SectionCell.identifier, owner: nil) as? SectionCell ?? SectionCell()
            cell.label.attributedStringValue = Theme.text(title, Theme.sectionFont, Theme.secondaryText)
            cell.onClear = title == "Suggestions" ? { [weak self] in self?.clearHistory() } : nil
            return cell
        case .app(let app):
            let cell = tableView.makeView(withIdentifier: AppCell.identifier, owner: nil) as? AppCell ?? AppCell()
            cell.title.attributedStringValue = Theme.text(app.name, Theme.titleFont, Theme.primaryText)
            cell.icon.image = icons.icon(for: app.url)
            cell.runningDot.isHidden = !runningIDs.contains(app.id)
            cell.onRemove = suggestedRows.contains(row) ? { [weak self] in self?.forget(app) } : nil
            return cell
        }
    }

    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool { false }
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { false }

    // MARK: Edge fades

    /// The list scrolls under the header and footer. Once scrolled away from an
    /// edge, content fades out toward it (Raycast: top over 96pt, bottom over
    /// 72pt down to 25%).
    @objc private func updateFade() {
        let bounds = listContainer.bounds
        guard bounds.height > 0 else { return }
        let clip = scrollView.contentView
        let offset = clip.bounds.minY + Theme.listTopInset
        let maxOffset = table.frame.height + Theme.listTopInset + Theme.listBottomInset - clip.bounds.height
        let top = min(1, max(0, offset / 32))
        let bottom = min(1, max(0, (maxOffset - offset) / 32))

        let h = bounds.height
        let a = { (alpha: CGFloat) in NSColor(white: 0, alpha: alpha).cgColor }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fade.frame = bounds
        // Unit y runs bottom → top in this (unflipped) layer. Raycast also blurs
        // under the header; without that, fully hiding what's behind the search
        // text reads better than letting it show through.
        let header = Theme.headerHeight
        fade.locations = [0, Theme.bottomFadeHeight / h, 1 - Theme.topFadeHeight / h, 1 - header / h, 1 - (header - 16) / h, 1]
            .map { NSNumber(value: Double($0)) }
        fade.colors = [a(1 - bottom * 0.75), a(1), a(1), a(1 - top * 0.75), a(1 - top), a(1 - top)]
        CATransaction.commit()
    }

    // MARK: Layout

    private func buildUI() {
        panel.delegate = self
        panel.acceptsMouseMovedEvents = true

        windowContent.onClickOutside = { [weak self] in self?.hide() }
        panel.contentView = windowContent

        let logo = LogoMark()

        field.cell = SearchFieldCell(textCell: "")
        field.isEditable = true
        field.isBezeled = false
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = Theme.searchFont
        field.textColor = Theme.primaryText
        field.cell?.usesSingleLineMode = true
        field.cell?.isScrollable = true
        // Our own placeholder: while editing, AppKit's field editor draws its
        // placeholder ~3.5pt above where it lays out typed text, clipping tall
        // letters and missing the caret. This label sits on the typed baseline.
        placeholder.attributedStringValue = Theme.text(Theme.placeholder, Theme.searchFont, Theme.tertiaryText, kern: 0) // typed text has no kern
        field.delegate = self

        let column = NSTableColumn(identifier: .init("main"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.headerView = nil
        table.style = .plain
        table.backgroundColor = .clear
        table.intercellSpacing = .zero
        table.selectionHighlightStyle = .none
        table.focusRingType = .none
        table.refusesFirstResponder = true
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.floatsGroupRows = false
        table.dataSource = self
        table.delegate = self
        table.onHover = { [weak self] in self?.hover($0) }
        table.onClick = { [weak self] row in
            self?.select(row)
            self?.openSelected()
        }

        scrollView.documentView = table
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.scrollerStyle = .overlay
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(top: Theme.listTopInset, left: 0, bottom: Theme.listBottomInset, right: 0)
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(updateFade), name: NSView.boundsDidChangeNotification, object: scrollView.contentView
        )

        listContainer.wantsLayer = true
        listContainer.layer?.mask = fade
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        listContainer.addSubview(scrollView)

        emptyLabel.attributedStringValue = Theme.text("No Results", Theme.emptyFont, Theme.secondaryText)
        emptyLabel.isHidden = true

        openButton.target = self
        openButton.action = #selector(openSelected)
        actionsButton.target = self
        actionsButton.action = #selector(showActions)
        pillContent.setViews([openButton, actionsButton], in: .leading)
        pillContent.spacing = 0
        pillContent.edgeInsets = NSEdgeInsets(
            top: Theme.pillPadding, left: Theme.pillPadding, bottom: Theme.pillPadding, right: Theme.pillPadding
        )
        let pillWidth = openButton.intrinsicContentSize.width + actionsButton.intrinsicContentSize.width + 2 * Theme.pillPadding

        for view in [listContainer, logo, placeholder, field, emptyLabel, pillHost] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
        }
        let headerCenter = Theme.headerHeight / 2
        NSLayoutConstraint.activate(
            listContainer.pin(to: root) + scrollView.pin(to: listContainer) + [
                logo.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: Theme.headerInset),
                logo.centerYAnchor.constraint(equalTo: root.topAnchor, constant: headerCenter),
                logo.widthAnchor.constraint(equalToConstant: Theme.logoSize),
                logo.heightAnchor.constraint(equalToConstant: Theme.logoSize),

                field.leadingAnchor.constraint(equalTo: logo.trailingAnchor, constant: Theme.headerGap),
                field.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -Theme.headerInset),
                field.centerYAnchor.constraint(equalTo: root.topAnchor, constant: headerCenter),
                field.heightAnchor.constraint(equalToConstant: Theme.searchFieldHeight),

                placeholder.leadingAnchor.constraint(equalTo: field.leadingAnchor),
                placeholder.trailingAnchor.constraint(lessThanOrEqualTo: field.trailingAnchor),
                placeholder.firstBaselineAnchor.constraint(
                    equalTo: root.topAnchor,
                    constant: headerCenter - Theme.searchFieldHeight / 2
                        + SearchFieldCell.line(fieldHeight: Theme.searchFieldHeight, font: Theme.searchFont).baseline
                ),

                emptyLabel.centerXAnchor.constraint(equalTo: root.centerXAnchor),
                emptyLabel.centerYAnchor.constraint(
                    equalTo: root.centerYAnchor, constant: (Theme.headerHeight - Theme.footerHeight) / 2
                ),

                pillHost.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -Theme.pillInset),
                pillHost.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -Theme.pillInset),
                pillHost.heightAnchor.constraint(equalToConstant: Theme.pillHeight),
                pillHost.widthAnchor.constraint(equalToConstant: pillWidth),
            ]
        )

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] in self?.handleKey($0) ?? $0 }
        apply(look)
    }

    /// Swaps the window's background, shadow, pill and selection style.
    func apply(_ look: Look) {
        self.look = look
        hide()
        chrome.forEach { $0.removeFromSuperview() }
        chrome = []
        lens = nil
        root.removeFromSuperview()
        pillContent.removeFromSuperview()
        panel.setContentSize(look.panelSize)

        // The card sits inside margins that hold its shadow (the system shadow
        // ignores the glass shape and leaves hard, tighter corners).
        let m = look.margin
        func addToCard(_ view: NSView) {
            view.translatesAutoresizingMaskIntoConstraints = false
            windowContent.addSubview(view)
            NSLayoutConstraint.activate([
                view.topAnchor.constraint(equalTo: windowContent.topAnchor, constant: m.top),
                view.bottomAnchor.constraint(equalTo: windowContent.bottomAnchor, constant: -m.bottom),
                view.leadingAnchor.constraint(equalTo: windowContent.leadingAnchor, constant: m.left),
                view.trailingAnchor.constraint(equalTo: windowContent.trailingAnchor, constant: -m.right),
            ])
            chrome.append(view)
        }
        func embed(_ content: NSView, in container: NSView) {
            content.translatesAutoresizingMaskIntoConstraints = true // a glass view may have switched it off
            content.frame = container.bounds
            content.autoresizingMask = [.width, .height]
            container.addSubview(content)
        }

        switch look {
        case .raycast, .glass:
            addToCard(ShadowView())
            let glass = NSGlassEffectView()
            glass.cornerRadius = Theme.cornerRadius
            glass.style = look == .glass ? .clear : .regular
            glass.tintColor = look == .glass ? Theme.clearGlassTint : Theme.glassTint
            glass.contentView = root
            addToCard(glass)
            addToCard(FillView(color: .clear, radius: Theme.cornerRadius, border: Theme.windowBorder))

            let pill = NSGlassEffectView()
            pill.cornerRadius = Theme.pillHeight / 2
            pill.style = glass.style
            pill.tintColor = look == .glass ? Theme.clearGlassTint : nil
            pill.contentView = pillContent
            pill.frame = pillHost.bounds
            pill.autoresizingMask = [.width, .height]
            pillHost.addSubview(pill)
            chrome.append(pill)
        case .performance:
            let card = NSView()
            addToCard(card)
            embed(FillView(color: Theme.solidBackground, radius: Theme.cornerRadius, border: Theme.solidBorder), in: card)
            embed(root, in: card)

            let pill = FillView(color: Theme.solidPill, radius: Theme.pillHeight / 2)
            embed(pill, in: pillHost)
            embed(pillContent, in: pillHost)
            chrome += [pill, pillContent]
        }

        if look == .glass {
            // A small pane of glass that slides to the selected row.
            let lens = NSGlassEffectView()
            lens.cornerRadius = Theme.rowRadius
            lens.style = .regular
            table.addSubview(lens, positioned: .below, relativeTo: nil)
            chrome.append(lens)
            self.lens = lens
        }

        windowContent.layoutSubtreeIfNeeded()
        update()
        position()
        park()
    }

    private func moveLens(animated: Bool) {
        guard let lens else { return }
        guard let selected else {
            lens.isHidden = true
            return
        }
        lens.isHidden = false
        let frame = table.rect(ofRow: selected).insetBy(dx: Theme.rowMargin, dy: 0)
        guard animated, lens.frame != .zero else {
            lens.frame = frame
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Theme.selectionAnimation
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            lens.animator().frame = frame
        }
    }
}

// MARK: - Window

final class LauncherPanel: NSPanel {
    init(size: NSSize) {
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        isFloatingPanel = true
        level = .modalPanel
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false // see ShadowView
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovable = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - Search bar

/// Centres the field editor's line box vertically in the field, so typed text
/// and the caret sit on the search bar's centre line. Uses the layout manager's
/// own line metrics, the ones the field editor lays out with.
final class SearchFieldCell: NSTextFieldCell {
    private static let layout = NSLayoutManager()

    /// Top of the line box, and its baseline, measured from the field's top.
    static func line(fieldHeight: CGFloat, font: NSFont) -> (top: CGFloat, baseline: CGFloat) {
        let top = ((fieldHeight - layout.defaultLineHeight(for: font)) / 2).rounded()
        return (top, top + layout.defaultBaselineOffset(for: font))
    }

    private func lineBox(in rect: NSRect) -> NSRect {
        guard let font else { return rect }
        let top = Self.line(fieldHeight: rect.height, font: font).top
        return NSRect(x: rect.minX, y: rect.minY + top, width: rect.width, height: Self.layout.defaultLineHeight(for: font))
    }

    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        lineBox(in: super.drawingRect(forBounds: rect))
    }

    override func edit(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, event: NSEvent?) {
        super.edit(withFrame: lineBox(in: rect), in: controlView, editor: textObj, delegate: delegate, event: event)
    }

    override func select(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, start selStart: Int, length selLength: Int) {
        super.select(withFrame: lineBox(in: rect), in: controlView, editor: textObj, delegate: delegate, start: selStart, length: selLength)
    }
}

/// The one-colour Magnetite mark (scripts/make-logo.swift with gap 36, which
/// stays legible at 22pt), where Raycast shows its logo.
final class LogoMark: NSView {
    private static let faces: [[NSPoint]] = [
        [(274.3, 87.5), (337.8, 279.7), (440.4, 219.1)],
        [(231.8, 73.7), (75.3, 274.6), (302.4, 287.1)],
        [(321.5, 385.3), (399.7, 285.0), (342.8, 318.5)],
        [(264.4, 445.7), (303.5, 323.2), (95.5, 311.8)],
    ].map { $0.map { NSPoint(x: $0.0, y: $0.1) } }

    override var isFlipped: Bool { true } // the coordinates are SVG's, top-down

    override func draw(_ dirtyRect: NSRect) {
        let scale = bounds.width / 512
        Theme.tertiaryText.setFill()
        let path = NSBezierPath()
        for face in Self.faces {
            path.move(to: NSPoint(x: face[0].x * scale, y: face[0].y * scale))
            face.dropFirst().forEach { path.line(to: NSPoint(x: $0.x * scale, y: $0.y * scale)) }
            path.close()
        }
        path.fill()
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

// MARK: - List

final class ListTable: NSTableView {
    var onHover: ((Int?) -> Void)?
    var onClick: ((Int) -> Void)?
    private var hoverArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        hoverArea = area
    }

    // Only real pointer movement hovers a row, so keyboard scrolling under a
    // resting pointer doesn't light anything up.
    override func mouseMoved(with event: NSEvent) {
        let row = row(at: convert(event.locationInWindow, from: nil))
        onHover?(row >= 0 ? row : nil)
    }

    override func mouseExited(with event: NSEvent) {
        onHover?(nil)
    }

    override func mouseDown(with event: NSEvent) {
        let row = row(at: convert(event.locationInWindow, from: nil))
        if row >= 0 { onClick?(row) }
    }
}

final class RowView: NSTableRowView {
    enum Highlight { case none, hovered, selected }

    static let identifier = NSUserInterfaceItemIdentifier("row")

    var highlight = Highlight.none {
        didSet { if highlight != oldValue { needsDisplay = true } }
    }
    /// Off in the Glass look, where a sliding glass lens marks the selection.
    var drawsSelection = true

    override func drawBackground(in dirtyRect: NSRect) {
        guard highlight == .hovered || (highlight == .selected && drawsSelection) else { return }
        (highlight == .selected ? Theme.selection : Theme.hover).setFill()
        let rect = bounds.insetBy(dx: Theme.rowMargin, dy: 0)
        NSBezierPath(roundedRect: rect, xRadius: Theme.rowRadius, yRadius: Theme.rowRadius).fill()
    }

    override func drawSelection(in dirtyRect: NSRect) {}
}

final class AppCell: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("app")

    let icon = NSImageView()
    let runningDot = FillView(color: Theme.tertiaryText, radius: Theme.runningDotSize / 2)
    let title = NSTextField(labelWithString: "")
    private let removeButton = SymbolButton(symbol: "xmark")
    /// Set for history rows: shows an × that removes the app from Suggestions.
    var onRemove: (() -> Void)? {
        didSet {
            removeButton.onClick = onRemove
            removeButton.isHidden = onRemove == nil
        }
    }

    init() {
        super.init(frame: .zero)
        identifier = Self.identifier
        icon.imageScaling = .scaleProportionallyUpOrDown
        title.lineBreakMode = .byTruncatingTail
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        removeButton.isHidden = true
        removeButton.toolTip = "Remove from Suggestions"

        for view in [icon, runningDot, title, removeButton] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        let inset = Theme.rowMargin + Theme.rowPadding
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: Theme.iconSize),
            icon.heightAnchor.constraint(equalToConstant: Theme.iconSize),

            runningDot.centerXAnchor.constraint(equalTo: icon.centerXAnchor),
            runningDot.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 2),
            runningDot.widthAnchor.constraint(equalToConstant: Theme.runningDotSize),
            runningDot.heightAnchor.constraint(equalToConstant: Theme.runningDotSize),

            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: Theme.iconGap),
            title.centerYAnchor.constraint(equalTo: centerYAnchor),

            title.trailingAnchor.constraint(lessThanOrEqualTo: removeButton.leadingAnchor, constant: -Theme.accessoryGap),

            removeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -(Theme.rowMargin + 4)),
            removeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            removeButton.widthAnchor.constraint(equalToConstant: Theme.smallButtonSize),
            removeButton.heightAnchor.constraint(equalToConstant: Theme.smallButtonSize),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }
}

final class SectionCell: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("section")

    let label = NSTextField(labelWithString: "")
    private let clearButton = FooterButton(title: "Clear", keys: [], color: Theme.secondaryText, height: Theme.smallButtonSize)
    /// Set for the Suggestions header: shows a Clear button that wipes the history.
    var onClear: (() -> Void)? {
        didSet {
            clearButton.onClick = onClear
            clearButton.isHidden = onClear == nil
        }
    }

    init() {
        super.init(frame: .zero)
        identifier = Self.identifier
        clearButton.isHidden = true
        clearButton.toolTip = "Clear all suggestions"
        for view in [label, clearButton] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Theme.rowMargin + Theme.rowPadding),
            label.centerYAnchor.constraint(equalTo: topAnchor, constant: Theme.sectionLabelCenterY),
            clearButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -(Theme.rowMargin + 4)),
            clearButton.centerYAnchor.constraint(equalTo: label.centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - Footer

/// "Open Application ↵" / "Actions ⌘ K": a title plus outlined keycaps, with a
/// faint rounded hover background. Without keys it's a plain text button ("Clear").
final class FooterButton: NSView {
    weak var target: AnyObject?
    var action: Selector?
    var onClick: (() -> Void)?
    var isEnabled = true {
        didSet { alphaValue = isEnabled ? 1 : 0.4 }
    }

    private let title: NSAttributedString
    private let keys: [NSAttributedString]
    private let height: CGFloat
    private var isHovered = false {
        didSet { needsDisplay = true }
    }

    init(title: String, keys: [String], color: NSColor, height: CGFloat = Theme.buttonHeight) {
        self.title = Theme.text(title, Theme.buttonFont, color)
        self.keys = keys.map { Theme.text($0, Theme.keyCapFont, Theme.secondaryText, kern: 0) }
        self.height = height
        super.init(frame: .zero)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    required init?(coder: NSCoder) { fatalError() }

    private func keyWidth(_ key: NSAttributedString) -> CGFloat {
        max(Theme.keyCapSize, ceil(key.size().width) + 2 * Theme.keyCapPadding)
    }

    override var intrinsicContentSize: NSSize {
        let keysWidth = keys.isEmpty ? 0
            : Theme.buttonGap + keys.map(keyWidth).reduce(0, +) + CGFloat(keys.count - 1) * Theme.keyCapGap
        let width = 2 * Theme.buttonPadding + 2 * Theme.buttonTitlePadding + ceil(title.size().width) + keysWidth
        return NSSize(width: width, height: height)
    }

    override func draw(_ dirtyRect: NSRect) {
        if isHovered && isEnabled {
            Theme.hover.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2).fill()
        }
        var x = Theme.buttonPadding + Theme.buttonTitlePadding
        let titleSize = title.size()
        title.draw(at: NSPoint(x: x, y: (bounds.height - titleSize.height) / 2))
        x += ceil(titleSize.width) + Theme.buttonTitlePadding + Theme.buttonGap

        for key in keys {
            let width = keyWidth(key)
            let cap = NSRect(x: x, y: (bounds.height - Theme.keyCapSize) / 2, width: width, height: Theme.keyCapSize)
            Theme.keyCapBorder.setStroke()
            let outline = NSBezierPath(roundedRect: cap.insetBy(dx: 0.5, dy: 0.5), xRadius: Theme.keyCapRadius, yRadius: Theme.keyCapRadius)
            outline.lineWidth = 1
            outline.stroke()
            let size = key.size()
            key.draw(at: NSPoint(x: cap.midX - size.width / 2, y: cap.midY - size.height / 2))
            x += width + Theme.keyCapGap
        }
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }

    /// Kept here so a click inside a list row doesn't also reach the row (and open the app).
    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        guard isEnabled, bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        if let action { NSApp.sendAction(action, to: target, from: self) } else { onClick?() }
    }
}

/// A small square icon button (the × on history rows).
final class SymbolButton: NSView {
    var onClick: (() -> Void)?

    private let image: NSImage
    private var isHovered = false {
        didSet { needsDisplay = true }
    }

    init(symbol: String) {
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)!
            .withSymbolConfiguration(.init(pointSize: 10, weight: .semibold))!
        super.init(frame: .zero)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        if isHovered {
            Theme.selection.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: Theme.keyCapRadius, yRadius: Theme.keyCapRadius).fill()
        }
        let tinted = NSImage(size: image.size, flipped: false) { rect in
            self.image.draw(in: rect)
            (self.isHovered ? Theme.primaryText : Theme.tertiaryText).set()
            rect.fill(using: .sourceAtop)
            return true
        }
        let size = image.size
        tinted.draw(in: NSRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2, width: size.width, height: size.height))
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }
    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick?() }
    }
}

/// The transparent area around the card only exists to hold the shadow; a
/// click there counts as a click outside.
final class PanelBackground: NSView {
    var onClickOutside: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        onClickOutside?()
    }
}

/// Raycast's launcher shadow (0 28px 72px black 42%, 0 8px 24px black 22%),
/// drawn only outside the card so it doesn't darken what the glass samples.
final class ShadowView: NSView {
    private let shadows: [(offset: CGFloat, blur: CGFloat, opacity: Float)] = [(28, 72, 0.42), (8, 24, 0.22)]
    private let cutout = CAShapeLayer()

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        clipsToBounds = false
        for shadow in shadows {
            let layer = CALayer()
            layer.shadowColor = NSColor.black.cgColor
            layer.shadowOpacity = shadow.opacity
            layer.shadowRadius = shadow.blur / 2
            layer.shadowOffset = CGSize(width: 0, height: -shadow.offset)
            self.layer?.addSublayer(layer)
        }
        cutout.fillRule = .evenOdd
        layer?.mask = cutout
    }

    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        let card = CGPath(roundedRect: bounds, cornerWidth: Theme.cornerRadius, cornerHeight: Theme.cornerRadius, transform: nil)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for layer in layer?.sublayers ?? [] {
            layer.frame = bounds
            layer.shadowPath = card
        }
        let outside = CGMutablePath()
        outside.addRect(bounds.insetBy(dx: -200, dy: -200))
        outside.addPath(card)
        cutout.frame = bounds
        cutout.path = outside
        CATransaction.commit()
    }
}

// MARK: - Helpers

/// A solid (optionally rounded / bordered) layer whose colors follow light/dark mode.
final class FillView: NSView {
    private let color: NSColor
    private let radius: CGFloat
    private let border: NSColor?

    init(color: NSColor, radius: CGFloat = 0, border: NSColor? = nil) {
        self.color = color
        self.radius = radius
        self.border = border
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = color.cgColor
        layer?.cornerRadius = radius
        layer?.cornerCurve = .continuous
        layer?.borderWidth = border == nil ? 0 : 1
        layer?.borderColor = border?.cgColor
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private extension NSView {
    func pin(to other: NSView) -> [NSLayoutConstraint] {
        [
            topAnchor.constraint(equalTo: other.topAnchor),
            bottomAnchor.constraint(equalTo: other.bottomAnchor),
            leadingAnchor.constraint(equalTo: other.leadingAnchor),
            trailingAnchor.constraint(equalTo: other.trailingAnchor),
        ]
    }
}

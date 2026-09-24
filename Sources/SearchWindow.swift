import AppKit
import Carbon.HIToolbox

final class SearchController: NSObject, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate {
    private enum Row {
        case header(String), app(AppEntry, removable: Bool = false)
        var app: AppEntry? { if case .app(let app, _) = self { app } else { nil } }
    }

    var onOpenSettings: (() -> Void)?
    private var look = Look.current
    private let panel = LauncherPanel(size: Look.current.panelSize)
    private let windowContent = PanelBackground(), root = NSView(), pillHost = NSView(), listContainer = NSView(), fade = CAGradientLayer()
    private let field = NSTextField(), placeholder = NSTextField(labelWithString: ""), emptyLabel = NSTextField(labelWithString: "")
    private let table = ListTable(), scrollView = NSScrollView(), usage = Usage(), icons = IconCache(size: Theme.iconSize)
    private let openButton = FooterButton(title: "Open Application", keys: ["↵"], color: Theme.primaryText)
    private let actionsButton = FooterButton(title: "Actions", keys: ["⌘", "K"], color: Theme.secondaryText)
    private lazy var pillContent = NSStackView(views: [openButton, actionsButton])
    private let scanQueue = DispatchQueue(label: "magnetite.scan", qos: .userInitiated, autoreleaseFrequency: .workItem)
    private var apps: [AppEntry] = [], rows: [Row] = [], folderStamps: AppIndex.Stamps = [:], chrome: [NSView] = []
    private var isShown = false, lens: NSGlassEffectView?, keyMonitor: Any?, runningObservation: NSKeyValueObservation?
    private var runningIDs: Set<String> = [] {
        didSet { table.reloadData(forRowIndexes: IndexSet(integersIn: Range(table.rows(in: table.visibleRect)) ?? 0..<0), columnIndexes: [0]) }
    }
    private var selected: Int? { didSet { redraw(oldValue, selected) } }
    private var hovered: Int? { didSet { redraw(oldValue, hovered) } }
    private var selectedApp: AppEntry? { selected.flatMap { rows[$0].app } }

    override init() {
        super.init()
        buildUI()
        runningObservation = NSWorkspace.shared.observe(\.runningApplications, options: .initial) { [weak self] workspace, _ in
            let ids = Set(workspace.runningApplications.compactMap(\.bundleIdentifier))
            DispatchQueue.main.async { self?.runningIDs = ids }
        }
        refreshIndex()
    }

    func toggle() { isShown ? hide() : show() }

    func show() {
        guard !isShown else { return }
        isShown = true
        position()
        panel.ignoresMouseEvents = false
        panel.makeKey()
        if (panel.firstResponder as? NSTextView)?.delegate !== field { panel.makeFirstResponder(field) }
        panel.alphaValue = 1
        CATransaction.flush()
        refreshIndex()
    }

    func hide() {
        guard isShown else { return }
        isShown = false
        park()
        DispatchQueue.main.async { self.clearQuery() }
    }

    func windowDidResignKey(_ notification: Notification) { hide() }

    private func park() {
        panel.alphaValue = 0
        panel.ignoresMouseEvents = true
        if panel.isKeyWindow || !panel.isVisible {
            panel.orderOut(nil)
            panel.orderFront(nil)
        }
    }

    private func clearQuery() {
        field.stringValue = ""
        update()
    }

    private func position() {
        let mouse = NSEvent.mouseLocation
        guard let area = (NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main)?.visibleFrame else { return }
        let origin = NSPoint(x: (area.midX - Theme.windowSize.width / 2).rounded() - look.margin.left,
                             y: (area.maxY - area.height * Theme.topOffsetRatio - Theme.windowSize.height).rounded() - look.margin.bottom)
        if panel.frame.origin != origin { panel.setFrameOrigin(origin) }
    }

    private func refreshIndex() {
        let stamps = folderStamps
        scanQueue.async { [self] in
            guard !AppIndex.isUnchanged(stamps) else { return }
            let (scanned, newStamps) = AppIndex.scan()
            DispatchQueue.main.async { [self] in
                folderStamps = newStamps
                guard scanned != apps else { return }
                apps = scanned
                icons.prewarm(scanned)
                update()
            }
        }
    }

    private func update() {
        let query = field.stringValue.trimmingCharacters(in: .whitespaces)
        if query.isEmpty {
            let suggested = usage.suggestions(apps, limit: Theme.suggestionCount), ids = Set(suggested.map(\.id))
            let history: [Row] = suggested.isEmpty ? [] : [.header("Suggestions")] + suggested.map { .app($0, removable: true) }
            rows = history + [.header("Applications")] + apps.filter { !ids.contains($0.id) }.map { .app($0) }
        } else {
            let results = usage.rank(apps, query: query)
            rows = results.isEmpty ? [] : [.header("Results")] + results.map { .app($0) }
        }
        (selected, hovered) = (rows.firstIndex { $0.app != nil }, nil)
        placeholder.isHidden = !field.stringValue.isEmpty
        emptyLabel.isHidden = !rows.isEmpty
        openButton.isEnabled = selected != nil
        table.reloadData()
        moveLens(animated: false)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: -Theme.listTopInset))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        updateFade()
    }

    private func highlight(for row: Int) -> RowView.Highlight { row == selected ? .selected : row == hovered ? .hovered : .none }

    private func redraw(_ changed: Int?...) {
        for row in changed.compactMap({ $0 }) where row < table.numberOfRows {
            (table.rowView(atRow: row, makeIfNecessary: false) as? RowView)?.highlight = highlight(for: row)
        }
    }

    private func select(_ index: Int) {
        guard rows.indices.contains(index), rows[index].app != nil, index != selected else { return }
        selected = index
        moveLens(animated: true)
    }

    private func hover(_ row: Int?) {
        hovered = row.flatMap { rows.indices.contains($0) && rows[$0].app != nil ? $0 : nil }
    }

    private func move(by delta: Int) {
        guard var next = selected.map({ $0 + delta }) else { return }
        while rows.indices.contains(next), rows[next].app == nil { next += delta }
        guard rows.indices.contains(next) else { return }
        select(next)
        table.scrollRowToVisible(delta < 0 && next > 0 && rows[next - 1].app == nil ? next - 1 : next)
    }

    @objc private func openSelected() {
        guard let app = selectedApp else { return }
        usage.record(app, query: field.stringValue)
        hide()
        NSWorkspace.shared.openApplication(at: app.url, configuration: NSWorkspace.OpenConfiguration())
    }

    @objc private func revealSelected() {
        guard let app = selectedApp else { return }
        hide()
        NSWorkspace.shared.activateFileViewerSelecting([app.url])
    }

    @objc private func openSettings() {
        hide()
        onOpenSettings?()
    }

    private func forget(_ app: AppEntry?) {
        usage.forget(app)
        update()
    }

    private func showActions() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for (title, action, mask) in [("Open Application", #selector(openSelected), NSEvent.ModifierFlags()), ("Show in Finder", #selector(revealSelected), .command)] {
            let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "\r")
            (item.target, item.keyEquivalentModifierMask, item.isEnabled) = (self, mask, selectedApp != nil)
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "Quit Magnetite", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: actionsButton.bounds.height + menu.size.height + 6), in: actionsButton)
    }

    func controlTextDidChange(_ obj: Notification) { update() }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveUp(_:)): move(by: -1)
        case #selector(NSResponder.moveDown(_:)): move(by: 1)
        case #selector(NSResponder.insertNewline(_:)): openSelected()
        case #selector(NSResponder.cancelOperation(_:)): field.stringValue.isEmpty ? hide() : clearQuery()
        case #selector(NSResponder.insertTab(_:)), #selector(NSResponder.insertBacktab(_:)): break
        default: return false
        }
        return true
    }

    private func handleKey(_ event: NSEvent) -> NSEvent? {
        guard event.window === panel else { return event }
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

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard case .header(let title) = rows[row] else { return Theme.rowHeight }
        return Theme.sectionHeight + (title == "Suggestions" ? Theme.clearButtonGap : 0)
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let view = tableView.makeView(withIdentifier: RowView.identifier, owner: nil) as? RowView ?? RowView()
        (view.identifier, view.highlight, view.drawsSelection) = (RowView.identifier, highlight(for: row), lens == nil)
        return view
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        switch rows[row] {
        case .header(let title):
            let cell = tableView.makeView(withIdentifier: SectionCell.identifier, owner: nil) as? SectionCell ?? SectionCell()
            cell.label.attributedStringValue = Theme.text(title, Theme.sectionFont, Theme.secondaryText)
            cell.onClear = title == "Suggestions" ? { [weak self] in self?.forget(nil) } : nil
            return cell
        case .app(let app, let removable):
            let cell = tableView.makeView(withIdentifier: AppCell.identifier, owner: nil) as? AppCell ?? AppCell()
            cell.title.attributedStringValue = Theme.text(app.name, Theme.titleFont, Theme.primaryText)
            cell.icon.image = icons.icon(for: app.url)
            cell.runningDot.isHidden = !runningIDs.contains(app.id)
            cell.onRemove = removable ? { [weak self] in self?.forget(app) } : nil
            return cell
        }
    }

    @objc private func updateFade() {
        let h = listContainer.bounds.height, clip = scrollView.contentView.bounds, header = Theme.headerHeight
        guard h > 0 else { return }
        let top = min(1, max(0, (clip.minY + Theme.listTopInset) / 32))
        let bottom = min(1, max(0, (table.frame.height + Theme.listBottomInset - clip.height - clip.minY) / 32))
        CATransaction.instantly {
            fade.frame = listContainer.bounds
            fade.locations = [0, Theme.bottomFadeHeight / h, 1 - Theme.topFadeHeight / h, 1 - header / h, 1 - (header - 16) / h, 1].map { NSNumber(value: $0) }
            fade.colors = [1 - bottom * 0.75, 1, 1, 1 - top * 0.75, 1 - top, 1 - top].map { NSColor(white: 0, alpha: $0).cgColor }
        }
    }

    private func buildUI() {
        panel.delegate = self
        panel.acceptsMouseMovedEvents = true
        panel.contentView = windowContent
        windowContent.onClickOutside = { [weak self] in self?.hide() }

        field.cell = SearchFieldCell(textCell: "")
        field.cell?.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.isEditable = true
        field.focusRingType = .none
        field.font = Theme.searchFont
        field.textColor = Theme.primaryText
        field.delegate = self
        placeholder.attributedStringValue = Theme.text(Theme.placeholder, Theme.searchFont, Theme.tertiaryText, kern: 0)
        emptyLabel.attributedStringValue = Theme.text("No Results", Theme.emptyFont, Theme.secondaryText)

        table.addTableColumn(NSTableColumn(identifier: .init("app")))
        table.headerView = nil
        table.style = .plain
        table.backgroundColor = .clear
        table.intercellSpacing = .zero
        table.refusesFirstResponder = true
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
        NotificationCenter.default.addObserver(self, selector: #selector(updateFade), name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        listContainer.wantsLayer = true
        listContainer.layer?.mask = fade
        listContainer.add(scrollView)

        openButton.onClick = { [weak self] in self?.openSelected() }
        actionsButton.onClick = { [weak self] in self?.showActions() }
        pillContent.spacing = 0
        pillContent.edgeInsets = NSEdgeInsets(top: Theme.pillPadding, left: Theme.pillPadding, bottom: Theme.pillPadding, right: Theme.pillPadding)

        let logo = LogoMark()
        root.add(listContainer, logo, placeholder, field, emptyLabel, pillHost)
        NSLayoutConstraint.activate(listContainer.pin(to: root) + scrollView.pin(to: listContainer) + logo.size(Theme.logoSize, Theme.logoSize) + [
            logo.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: Theme.headerInset),
            logo.centerYAnchor.constraint(equalTo: root.topAnchor, constant: Theme.headerHeight / 2),
            field.leadingAnchor.constraint(equalTo: logo.trailingAnchor, constant: Theme.headerGap),
            field.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -Theme.headerInset),
            field.centerYAnchor.constraint(equalTo: logo.centerYAnchor),
            field.heightAnchor.constraint(equalToConstant: Theme.searchFieldHeight),
            placeholder.leadingAnchor.constraint(equalTo: field.leadingAnchor),
            placeholder.trailingAnchor.constraint(lessThanOrEqualTo: field.trailingAnchor),
            placeholder.firstBaselineAnchor.constraint(equalTo: field.topAnchor, constant: SearchFieldCell.baseline(Theme.searchFieldHeight, Theme.searchFont)),
            emptyLabel.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: root.centerYAnchor, constant: (Theme.headerHeight - Theme.footerHeight) / 2),
            pillHost.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -Theme.pillInset),
            pillHost.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -Theme.pillInset),
            pillHost.heightAnchor.constraint(equalToConstant: Theme.pillHeight),
            pillHost.widthAnchor.constraint(equalToConstant: pillContent.fittingSize.width),
        ])
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] in self?.handleKey($0) ?? $0 }
        apply(look)
    }

    func apply(_ look: Look) {
        self.look = look
        hide()
        (chrome + [root, pillContent]).forEach { $0.removeFromSuperview() }
        lens = nil
        panel.setContentSize(look.panelSize)
        func card(_ view: NSView) -> NSView {
            windowContent.add(view)
            NSLayoutConstraint.activate(view.pin(to: windowContent, look.margin))
            return view
        }
        if look == .performance {
            let background = card(NSView())
            background.embed(FillView(color: Theme.solidBackground, radius: Theme.cornerRadius, border: Theme.solidBorder), root)
            pillHost.embed(FillView(color: Theme.solidPill, radius: Theme.pillHeight / 2), pillContent)
            chrome = [background] + pillHost.subviews
        } else {
            let style: NSGlassEffectView.Style = look == .glass ? .clear : .regular, tint = look == .glass ? Theme.clearGlassTint : nil
            chrome = [card(ShadowView([(28, 72, 0.42), (8, 24, 0.22)])), card(glass(style, Theme.cornerRadius, tint: tint ?? Theme.glassTint, content: root)),
                      card(FillView(color: .clear, radius: Theme.cornerRadius, border: Theme.windowBorder))]
            chrome += pillHost.embed(glass(style, Theme.pillHeight / 2, tint: tint, content: pillContent))
        }
        if look == .glass {
            let lens = glass(.regular, Theme.rowRadius)
            table.addSubview(lens, positioned: .below, relativeTo: nil)
            (self.lens, chrome) = (lens, chrome + [lens])
        }
        windowContent.layoutSubtreeIfNeeded()
        update()
        position()
        park()
    }

    private func glass(_ style: NSGlassEffectView.Style, _ radius: CGFloat, tint: NSColor? = nil, content: NSView? = nil) -> NSGlassEffectView {
        let glass = NSGlassEffectView()
        (glass.style, glass.cornerRadius, glass.tintColor, glass.contentView) = (style, radius, tint, content)
        return glass
    }

    private func moveLens(animated: Bool) {
        guard let lens else { return }
        lens.isHidden = selected == nil
        guard let selected else { return }
        let frame = table.rect(ofRow: selected).insetBy(dx: Theme.rowMargin, dy: 0)
        if animated, lens.frame != .zero {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Theme.selectionAnimation
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                lens.animator().frame = frame
            }
        } else {
            lens.frame = frame
        }
    }
}

final class LauncherPanel: NSPanel {
    init(size: NSSize) {
        super.init(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .modalPanel
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovable = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { true }
}

final class SearchFieldCell: NSTextFieldCell {
    private static let layout = NSLayoutManager()

    static func lineTop(_ height: CGFloat, _ font: NSFont) -> CGFloat { ((height - layout.defaultLineHeight(for: font)) / 2).rounded() }
    static func baseline(_ height: CGFloat, _ font: NSFont) -> CGFloat { lineTop(height, font) + layout.defaultBaselineOffset(for: font) }

    private func lineBox(_ rect: NSRect) -> NSRect {
        guard let font else { return rect }
        return NSRect(x: rect.minX, y: rect.minY + Self.lineTop(rect.height, font), width: rect.width, height: Self.layout.defaultLineHeight(for: font))
    }

    override func edit(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, event: NSEvent?) {
        super.edit(withFrame: lineBox(rect), in: controlView, editor: textObj, delegate: delegate, event: event)
    }

    override func select(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, start selStart: Int, length selLength: Int) {
        super.select(withFrame: lineBox(rect), in: controlView, editor: textObj, delegate: delegate, start: selStart, length: selLength)
    }

    override func setUpFieldEditorAttributes(_ textObj: NSText) -> NSText {
        let editor = super.setUpFieldEditorAttributes(textObj) as? NSTextView
        editor?.insertionPointColor = Theme.primaryText
        editor?.selectedTextAttributes = [.backgroundColor: Theme.textSelection]
        return editor ?? textObj
    }
}

final class LogoMark: NSView {
    private static let faces = [
        [(274.3, 87.5), (337.8, 279.7), (440.4, 219.1)], [(231.8, 73.7), (75.3, 274.6), (302.4, 287.1)],
        [(321.5, 385.3), (399.7, 285.0), (342.8, 318.5)], [(264.4, 445.7), (303.5, 323.2), (95.5, 311.8)],
    ]

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(), scale = bounds.width / 512
        for face in Self.faces {
            path.move(to: NSPoint(x: face[0].0 * scale, y: face[0].1 * scale))
            face.dropFirst().forEach { path.line(to: NSPoint(x: $0.0 * scale, y: $0.1 * scale)) }
            path.close()
        }
        Theme.tertiaryText.setFill()
        path.fill()
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

final class ListTable: NSTableView {
    var onHover: ((Int?) -> Void)?, onClick: ((Int) -> Void)?
    private lazy var hoverArea = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if !trackingAreas.contains(hoverArea) { addTrackingArea(hoverArea) }
    }

    private func row(for event: NSEvent) -> Int? {
        let index = row(at: convert(event.locationInWindow, from: nil))
        return index >= 0 ? index : nil
    }

    override func mouseMoved(with event: NSEvent) { onHover?(row(for: event)) }
    override func mouseExited(with event: NSEvent) { onHover?(nil) }
    override func mouseDown(with event: NSEvent) { if let row = row(for: event) { onClick?(row) } }
}

final class RowView: NSTableRowView {
    enum Highlight { case none, hovered, selected }
    static let identifier = NSUserInterfaceItemIdentifier("row")
    var highlight = Highlight.none { didSet { if highlight != oldValue { needsDisplay = true } } }
    var drawsSelection = true

    override func drawBackground(in dirtyRect: NSRect) {
        guard highlight == .hovered || (highlight == .selected && drawsSelection) else { return }
        bounds.insetBy(dx: Theme.rowMargin, dy: 0).fill(highlight == .selected ? Theme.selection : Theme.hover, radius: Theme.rowRadius)
    }

    override func drawSelection(in dirtyRect: NSRect) {}
}

final class AppCell: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("app")
    let icon = NSImageView(), title = NSTextField(labelWithString: ""), runningDot = FillView(color: Theme.tertiaryText, radius: Theme.runningDotSize / 2)
    private let removeButton = SymbolButton(symbol: "xmark")
    var onRemove: (() -> Void)? { didSet { (removeButton.onClick, removeButton.isHidden) = (onRemove, onRemove == nil) } }

    convenience init() {
        self.init(frame: .zero)
        identifier = Self.identifier
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        removeButton.toolTip = "Remove from Suggestions"
        add(icon, runningDot, title, removeButton)
        NSLayoutConstraint.activate(icon.size(Theme.iconSize, Theme.iconSize) + runningDot.size(Theme.runningDotSize, Theme.runningDotSize)
            + removeButton.size(Theme.smallButtonSize, Theme.smallButtonSize) + [
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Theme.rowMargin + Theme.rowPadding),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            runningDot.centerXAnchor.constraint(equalTo: icon.centerXAnchor),
            runningDot.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 2),
            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: Theme.iconGap),
            title.centerYAnchor.constraint(equalTo: centerYAnchor),
            title.trailingAnchor.constraint(lessThanOrEqualTo: removeButton.leadingAnchor, constant: -Theme.accessoryGap),
            removeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -(Theme.rowMargin + 4)),
            removeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
}

final class SectionCell: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("section")
    let label = NSTextField(labelWithString: "")
    private let clearButton = FooterButton(title: "Clear", keys: [], color: Theme.secondaryText, height: Theme.smallButtonSize)
    var onClear: (() -> Void)? { didSet { (clearButton.onClick, clearButton.isHidden) = (onClear, onClear == nil) } }

    convenience init() {
        self.init(frame: .zero)
        identifier = Self.identifier
        clearButton.toolTip = "Clear all suggestions"
        add(label, clearButton)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Theme.rowMargin + Theme.rowPadding),
            label.centerYAnchor.constraint(equalTo: topAnchor, constant: Theme.sectionLabelCenterY),
            clearButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -(Theme.rowMargin + 4)),
            clearButton.centerYAnchor.constraint(equalTo: label.centerYAnchor),
        ])
    }
}

class HoverButton: NSView {
    var onClick: (() -> Void)?
    var isEnabled = true { didSet { alphaValue = isEnabled ? 1 : 0.4 } }
    var isHovered = false { didSet { needsDisplay = true } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    required init?(coder: NSCoder) { fatalError() }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) { if isEnabled, bounds.contains(convert(event.locationInWindow, from: nil)) { onClick?() } }
}

final class FooterButton: HoverButton {
    private var title = NSAttributedString(), keys: [NSAttributedString] = [], height = Theme.buttonHeight

    convenience init(title: String, keys: [String], color: NSColor, height: CGFloat = Theme.buttonHeight) {
        self.init(frame: .zero)
        self.title = Theme.text(title, Theme.buttonFont, color)
        self.keys = keys.map { Theme.text($0, Theme.keyCapFont, Theme.secondaryText, kern: 0) }
        self.height = height
    }

    private func keyWidth(_ key: NSAttributedString) -> CGFloat { max(Theme.keyCapSize, ceil(key.size().width) + 2 * Theme.keyCapPadding) }

    override var intrinsicContentSize: NSSize {
        let keysWidth = keys.isEmpty ? 0 : Theme.buttonGap + keys.map(keyWidth).reduce(0, +) + CGFloat(keys.count - 1) * Theme.keyCapGap
        return NSSize(width: 2 * (Theme.buttonPadding + Theme.buttonTitlePadding) + ceil(title.size().width) + keysWidth, height: height)
    }

    override func draw(_ dirtyRect: NSRect) {
        if isHovered && isEnabled { bounds.fill(Theme.hover, radius: bounds.height / 2) }
        title.draw(at: NSPoint(x: Theme.buttonPadding + Theme.buttonTitlePadding, y: (bounds.height - title.size().height) / 2))
        var x = Theme.buttonPadding + 2 * Theme.buttonTitlePadding + ceil(title.size().width) + Theme.buttonGap
        for key in keys {
            let cap = NSRect(x: x, y: (bounds.height - Theme.keyCapSize) / 2, width: keyWidth(key), height: Theme.keyCapSize)
            Theme.keyCapBorder.setStroke()
            NSBezierPath(roundedRect: cap.insetBy(dx: 0.5, dy: 0.5), xRadius: Theme.keyCapRadius, yRadius: Theme.keyCapRadius).stroke()
            key.draw(at: NSPoint(x: cap.midX - key.size().width / 2, y: cap.midY - key.size().height / 2))
            x = cap.maxX + Theme.keyCapGap
        }
    }
}

final class SymbolButton: HoverButton {
    private var symbol = NSImage()

    convenience init(symbol: String) {
        self.init(frame: .zero)
        self.symbol = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)!.withSymbolConfiguration(.init(pointSize: 10, weight: .semibold))!
    }

    override func draw(_ dirtyRect: NSRect) {
        if isHovered { bounds.fill(Theme.selection, radius: Theme.keyCapRadius) }
        let size = symbol.size, tinted = NSImage(size: size, flipped: false) { rect in
            self.symbol.draw(in: rect)
            (self.isHovered ? Theme.primaryText : Theme.tertiaryText).set()
            rect.fill(using: .sourceAtop)
            return true
        }
        tinted.draw(in: NSRect(origin: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2), size: size))
    }
}

final class PanelBackground: NSView {
    var onClickOutside: (() -> Void)?
    override func mouseDown(with event: NSEvent) { onClickOutside?() }
}

final class ShadowView: NSView {
    private let cutout = CAShapeLayer()

    convenience init(_ shadows: [(offset: CGFloat, blur: CGFloat, opacity: Float)]) {
        self.init(frame: .zero)
        wantsLayer = true
        cutout.fillRule = .evenOdd
        layer?.mask = cutout
        for shadow in shadows {
            let layer = CALayer()
            (layer.shadowColor, layer.shadowOpacity, layer.shadowRadius, layer.shadowOffset) = (.black, shadow.opacity, shadow.blur / 2, CGSize(width: 0, height: -shadow.offset))
            self.layer?.addSublayer(layer)
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        let card = CGPath(roundedRect: bounds, cornerWidth: Theme.cornerRadius, cornerHeight: Theme.cornerRadius, transform: nil), outside = CGMutablePath()
        outside.addRect(bounds.insetBy(dx: -200, dy: -200))
        outside.addPath(card)
        CATransaction.instantly {
            layer?.sublayers?.forEach { ($0.frame, $0.shadowPath) = (bounds, card) }
            (cutout.frame, cutout.path) = (bounds, outside)
        }
    }
}

final class FillView: NSView {
    private var color = NSColor.clear, radius: CGFloat = 0, border: NSColor?

    convenience init(color: NSColor, radius: CGFloat = 0, border: NSColor? = nil) {
        self.init(frame: .zero)
        (self.color, self.radius, self.border, wantsLayer) = (color, radius, border, true)
    }

    override var wantsUpdateLayer: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func updateLayer() {
        guard let layer else { return }
        (layer.backgroundColor, layer.cornerRadius, layer.cornerCurve) = (color.cgColor, radius, .continuous)
        (layer.borderWidth, layer.borderColor) = (border == nil ? 0 : 1, border?.cgColor)
    }
}

extension NSView {
    func add(_ views: NSView...) {
        for view in views {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
    }

    @discardableResult func embed(_ views: NSView...) -> [NSView] {
        for view in views {
            (view.translatesAutoresizingMaskIntoConstraints, view.frame, view.autoresizingMask) = (true, bounds, [.width, .height])
            addSubview(view)
        }
        return views
    }

    func pin(to other: NSView, _ inset: NSEdgeInsets = NSEdgeInsets()) -> [NSLayoutConstraint] {
        [topAnchor.constraint(equalTo: other.topAnchor, constant: inset.top), bottomAnchor.constraint(equalTo: other.bottomAnchor, constant: -inset.bottom),
         leadingAnchor.constraint(equalTo: other.leadingAnchor, constant: inset.left), trailingAnchor.constraint(equalTo: other.trailingAnchor, constant: -inset.right)]
    }

    func size(_ width: CGFloat, _ height: CGFloat) -> [NSLayoutConstraint] {
        [widthAnchor.constraint(equalToConstant: width), heightAnchor.constraint(equalToConstant: height)]
    }
}

extension NSRect {
    func fill(_ color: NSColor, radius: CGFloat) {
        color.setFill()
        NSBezierPath(roundedRect: self, xRadius: radius, yRadius: radius).fill()
    }
}

extension CATransaction {
    static func instantly(_ changes: () -> Void) {
        begin()
        setDisableActions(true)
        changes()
        commit()
    }
}

import AppKit
import MagnetiteCore

final class ResultsList: NSView, NSTableViewDataSource, NSTableViewDelegate {
    let table = ListTable()
    var onForget: ((AppEntry?) -> Void)?
    var running: Set<String> = [] { didSet { table.reloadData(forRowIndexes: IndexSet(integersIn: Range(table.rows(in: table.visibleRect)) ?? 0..<0), columnIndexes: [0]) } }
    private(set) var state = LauncherState()
    private let scrollView = NSScrollView(), fade = CAGradientLayer(), icons = IconCache()
    private let emptyLabel = NSTextField(labelWithAttributedString: Theme.text("No Results", Theme.emptyFont, Theme.secondaryText))
    private var lens: NSGlassEffectView?
    func prewarm(_ apps: [AppEntry]) { icons.prewarm(apps) }
    func numberOfRows(in tableView: NSTableView) -> Int { state.rows.count }
    private func highlight(_ row: Int) -> RowView.Highlight { row == state.selected ? .selected : row == state.hovered ? .hovered : .none }
    convenience init() {
        self.init(frame: .zero)
        table.addTableColumn(NSTableColumn(identifier: .init("app")))
        (table.headerView, table.style, table.backgroundColor, table.intercellSpacing, table.refusesFirstResponder) = (nil, .plain, .clear, .zero, true)
        (table.dataSource, table.delegate, scrollView.documentView) = (self, self, table)
        (scrollView.drawsBackground, scrollView.hasVerticalScroller, scrollView.scrollerStyle, scrollView.automaticallyAdjustsContentInsets) = (false, true, .overlay, false)
        scrollView.contentInsets = NSEdgeInsets(top: Theme.listTopInset, left: 0, bottom: Theme.listBottomInset, right: 0)
        NotificationCenter.default.addObserver(self, selector: #selector(updateFade), name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        wantsLayer = true
        layer?.mask = fade
        scrollView.fill(self)
        emptyLabel.place(in: self, centerX: 0, centerY: (Theme.headerHeight - Theme.footerHeight) / 2)
    }
    func apply(_ look: Look) {
        lens?.removeFromSuperview()
        lens = look == .glass ? NSGlassEffectView(style: .regular, radius: Theme.rowRadius) : nil
        if let lens { table.addSubview(lens, positioned: .below, relativeTo: nil) }
    }
    func reload(_ state: LauncherState) {
        self.state = state
        emptyLabel.isHidden = !state.rows.isEmpty
        table.reloadData()
        moveLens(animated: false)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: -Theme.listTopInset))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        updateFade()
    }
    func update(_ state: LauncherState, animated: Bool = false) {
        let old = self.state
        self.state = state
        for row in [old.selected, old.hovered, state.selected, state.hovered].compactMap({ $0 }) where row < table.numberOfRows {
            (table.rowView(atRow: row, makeIfNecessary: false) as? RowView)?.highlight = highlight(row)
        }
        if animated { moveLens(animated: true) }
    }
    private func moveLens(animated: Bool) {
        guard let lens else { return }
        lens.isHidden = state.selected == nil
        guard let selected = state.selected else { return }
        NSAnimationContext.runAnimationGroup { context in
            (context.duration, context.timingFunction) = (animated && lens.frame != .zero ? Theme.selectionAnimation : 0, CAMediaTimingFunction(name: .easeOut))
            lens.animator().frame = table.rect(ofRow: selected).insetBy(dx: Theme.rowMargin, dy: 0)
        }
    }
    @objc private func updateFade() {
        let h = bounds.height, clip = scrollView.contentView.bounds, header = Theme.headerHeight
        guard h > 0 else { return }
        let top = min(1, max(0, (clip.minY + Theme.listTopInset) / 32)), bottom = min(1, max(0, (table.frame.height + Theme.listBottomInset - clip.height - clip.minY) / 32))
        CATransaction.instantly {
            fade.frame = bounds
            fade.locations = [0, Theme.bottomFadeHeight / h, 1 - Theme.topFadeHeight / h, 1 - header / h, 1 - (header - 16) / h, 1].map { NSNumber(value: $0) }
            fade.colors = [1 - bottom * 0.75, 1, 1, 1 - top * 0.75, 1 - top, 1 - top].map { NSColor(white: 0, alpha: $0).cgColor }
        }
    }
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard case .header(let title) = state.rows[row] else { return Theme.rowHeight }
        return Theme.sectionHeight + (title == "Suggestions" ? Theme.clearButtonGap : 0)
    }
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let view = tableView.makeView(withIdentifier: RowView.identifier, owner: nil) as? RowView ?? RowView()
        (view.identifier, view.highlight, view.drawsSelection) = (RowView.identifier, highlight(row), lens == nil)
        return view
    }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        switch state.rows[row] {
        case .header(let title):
            let cell = tableView.makeView(withIdentifier: SectionCell.identifier, owner: nil) as? SectionCell ?? SectionCell()
            cell.label.attributedStringValue = Theme.text(title, Theme.sectionFont, Theme.secondaryText)
            cell.onClear = title == "Suggestions" ? { [weak self] in self?.onForget?(nil) } : nil
            return cell
        case .app(let app, let removable):
            let cell = tableView.makeView(withIdentifier: AppCell.identifier, owner: nil) as? AppCell ?? AppCell()
            (cell.title.attributedStringValue, cell.icon.image) = (Theme.text(app.name, Theme.titleFont, Theme.primaryText), icons.icon(for: app.url))
            cell.runningDot.isHidden = !running.contains(app.id)
            cell.onRemove = removable ? { [weak self] in self?.onForget?(app) } : nil
            return cell
        }
    }
}

final class ListTable: NSTableView {
    var onHover: ((Int?) -> Void)?, onClick: ((Int) -> Void)?
    private lazy var hoverArea = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
    override func mouseMoved(with event: NSEvent) { onHover?(row(for: event)) }
    override func mouseExited(with event: NSEvent) { onHover?(nil) }
    override func mouseDown(with event: NSEvent) { onClick?(row(for: event)) }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if !trackingAreas.contains(hoverArea) { addTrackingArea(hoverArea) }
    }
    private func row(for event: NSEvent) -> Int { row(at: convert(event.locationInWindow, from: nil)) }
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
}

final class AppCell: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("app")
    let icon = NSImageView(), title = NSTextField(labelWithString: ""), runningDot = FillView(color: Theme.tertiaryText, radius: Theme.runningDotSize / 2)
    private let removeButton = SymbolButton(symbol: "xmark")
    var onRemove: (() -> Void)? { didSet { (removeButton.onClick, removeButton.isHidden) = (onRemove, onRemove == nil) } }
    convenience init() {
        self.init(frame: .zero)
        (identifier, removeButton.toolTip) = (Self.identifier, "Remove from Suggestions")
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let inset = Theme.rowMargin + Theme.rowPadding
        icon.place(in: self, leading: inset, centerY: 0, width: Theme.iconSize, height: Theme.iconSize)
        runningDot.place(in: self, top: (Theme.rowHeight + Theme.iconSize) / 2 + 2, leading: inset + (Theme.iconSize - Theme.runningDotSize) / 2,
                         width: Theme.runningDotSize, height: Theme.runningDotSize)
        title.place(in: self, leading: inset + Theme.iconSize + Theme.iconGap, centerY: 0)
        removeButton.place(in: self, trailing: Theme.rowMargin + 4, centerY: 0, width: Theme.smallButtonSize, height: Theme.smallButtonSize)
        title.trailingAnchor.constraint(lessThanOrEqualTo: removeButton.leadingAnchor, constant: -Theme.accessoryGap).isActive = true
    }
}

final class SectionCell: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("section")
    let label = NSTextField(labelWithString: "")
    private let clearButton = FooterButton(title: "Clear", color: Theme.secondaryText, height: Theme.smallButtonSize)
    var onClear: (() -> Void)? { didSet { (clearButton.onClick, clearButton.isHidden) = (onClear, onClear == nil) } }
    convenience init() {
        self.init(frame: .zero)
        (identifier, clearButton.toolTip) = (Self.identifier, "Clear all suggestions")
        label.place(in: self, leading: Theme.rowMargin + Theme.rowPadding).centerYAnchor.constraint(equalTo: topAnchor, constant: Theme.sectionLabelCenterY).isActive = true
        clearButton.place(in: self, trailing: Theme.rowMargin + 4).centerYAnchor.constraint(equalTo: label.centerYAnchor).isActive = true
    }
}

final class IconCache {
    private var images: [URL: NSImage] = [:]
    private let queue = DispatchQueue(label: "magnetite.icons", qos: .userInitiated, autoreleaseFrequency: .workItem), size = Theme.iconSize
    func icon(for url: URL) -> NSImage {
        if images[url] == nil { images[url] = render(url) }
        return images[url]!
    }
    func prewarm(_ apps: [AppEntry]) {
        let missing = apps.map(\.url).filter { images[$0] == nil }
        queue.async {
            let rendered = missing.map { ($0, self.render($0)) }
            DispatchQueue.main.async { for (url, image) in rendered where self.images[url] == nil { self.images[url] = image } }
        }
    }
    private func render(_ url: URL) -> NSImage {
        autoreleasepool {
            let icon = NSWorkspace.shared.icon(forFile: url.path), pixels = Int(size * 2)
            guard let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
            else { return icon }
            context.interpolationQuality = .high
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            icon.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
            NSGraphicsContext.restoreGraphicsState()
            return context.makeImage().map { NSImage(cgImage: $0, size: NSSize(width: size, height: size)) } ?? icon
        }
    }
}

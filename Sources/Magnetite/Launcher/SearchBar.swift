import AppKit

final class SearchBar: NSView, NSTextFieldDelegate {
    let field = NSTextField()
    var onChange: (() -> Void)?, onCommand: ((Selector) -> Bool)?
    var text: String { field.stringValue }
    private let placeholder = NSTextField(labelWithAttributedString: Theme.text(Theme.placeholder, Theme.searchFont, Theme.tertiaryText, kern: 0))
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool { onCommand?(selector) ?? false }
    convenience init() {
        self.init(frame: .zero)
        field.cell = SearchFieldCell(textCell: "")
        (field.cell!.usesSingleLineMode, field.cell!.isScrollable, field.isEditable, field.focusRingType) = (true, true, true, .none)
        (field.font, field.textColor, field.delegate) = (Theme.searchFont, Theme.primaryText, self)
        let textLeading = Theme.headerInset + Theme.logoSize + Theme.headerGap
        LogoMark().place(in: self, leading: Theme.headerInset, centerY: 0, width: Theme.logoSize, height: Theme.logoSize)
        placeholder.place(in: self, leading: textLeading)
        field.place(in: self, leading: textLeading, trailing: Theme.headerInset, centerY: 0, height: Theme.searchFieldHeight)
        placeholder.firstBaselineAnchor.constraint(equalTo: field.topAnchor, constant: SearchFieldCell.baseline(Theme.searchFieldHeight, Theme.searchFont)).isActive = true
    }
    func clear() {
        field.stringValue = ""
        controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
    }
    func controlTextDidChange(_ obj: Notification) {
        placeholder.isHidden = !field.stringValue.isEmpty
        onChange?()
    }
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
        guard let editor = super.setUpFieldEditorAttributes(textObj) as? NSTextView else { return textObj }
        (editor.insertionPointColor, editor.selectedTextAttributes) = (Theme.primaryText, [.backgroundColor: Theme.textSelection])
        return editor
    }
}

final class LogoMark: NSView {
    private static let faces = [[(274.3, 87.5), (337.8, 279.7), (440.4, 219.1)], [(231.8, 73.7), (75.3, 274.6), (302.4, 287.1)],
                                [(321.5, 385.3), (399.7, 285.0), (342.8, 318.5)], [(264.4, 445.7), (303.5, 323.2), (95.5, 311.8)]]
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
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
}

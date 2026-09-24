import AppKit

class HoverButton: NSView {
    var onClick: (() -> Void)?
    var isEnabled = true { didSet { alphaValue = isEnabled ? 1 : 0.4 } }
    var isHovered = false { didSet { needsDisplay = true } }
    required init?(coder: NSCoder) { fatalError() }
    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) { if isEnabled, bounds.contains(convert(event.locationInWindow, from: nil)) { onClick?() } }
    override init(frame: NSRect) {
        super.init(frame: frame)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
}

final class FooterButton: HoverButton {
    private var title = NSAttributedString(), keys: [NSAttributedString] = [], height = Theme.buttonHeight
    private func keyWidth(_ key: NSAttributedString) -> CGFloat { max(Theme.keyCapSize, ceil(key.size().width) + 2 * Theme.keyCapPadding) }
    override var intrinsicContentSize: NSSize {
        let keysWidth = keys.isEmpty ? 0 : Theme.buttonGap + keys.map(keyWidth).reduce(0, +) + CGFloat(keys.count - 1) * Theme.keyCapGap
        return NSSize(width: 2 * (Theme.buttonPadding + Theme.buttonTitlePadding) + ceil(title.size().width) + keysWidth, height: height)
    }
    convenience init(title: String, keys: [String] = [], color: NSColor, height: CGFloat = Theme.buttonHeight) {
        self.init(frame: .zero)
        (self.title, self.keys, self.height) = (Theme.text(title, Theme.buttonFont, color), keys.map { Theme.text($0, Theme.keyCapFont, Theme.secondaryText, kern: 0) }, height)
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

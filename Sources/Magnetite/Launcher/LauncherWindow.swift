import AppKit

final class LauncherWindow: NSPanel {
    let content = NSView(), background = PanelBackground()
    override var canBecomeKey: Bool { true }
    init() {
        super.init(contentRect: NSRect(origin: .zero, size: Theme.panelSize), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        (level, collectionBehavior, animationBehavior) = (.modalPanel, [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle], .none)
        (isOpaque, backgroundColor, hasShadow, hidesOnDeactivate, isReleasedWhenClosed, isMovable) = (false, .clear, false, false, false, false)
        (acceptsMouseMovedEvents, contentView) = (true, background)
        for card in [ShadowView([(28, 72, 0.42), (8, 24, 0.22)]), NSGlassEffectView(style: .regular, radius: Theme.cornerRadius, tint: Theme.glassTint, content: content),
                      FillView(color: .clear, radius: Theme.cornerRadius, border: Theme.windowBorder)] { card.fill(background, Theme.shadowMargin) }
        position()
    }
    func reveal(focusing field: NSView) {
        position()
        ignoresMouseEvents = false
        makeKey()
        if (firstResponder as? NSTextView)?.delegate !== field { makeFirstResponder(field) }
        alphaValue = 1
        CATransaction.flush()
    }
    func park() {
        (alphaValue, ignoresMouseEvents) = (0, true)
        guard isKeyWindow || !isVisible else { return }
        orderOut(nil)
        orderFront(nil)
    }
    private func position() {
        let mouse = NSEvent.mouseLocation
        guard let area = (NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main)?.visibleFrame else { return }
        let origin = NSPoint(x: (area.midX - Theme.windowSize.width / 2).rounded() - Theme.shadowMargin.left,
                             y: (area.maxY - area.height * Theme.topOffsetRatio - Theme.windowSize.height).rounded() - Theme.shadowMargin.bottom)
        if frame.origin != origin { setFrameOrigin(origin) }
    }
}

final class PanelBackground: NSView {
    var onClick: (() -> Void)?
    override func mouseDown(with event: NSEvent) { onClick?() }
}

final class ShadowView: NSView {
    private let cutout = CAShapeLayer()
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    convenience init(_ shadows: [(offset: CGFloat, blur: CGFloat, opacity: Float)]) {
        self.init(frame: .zero)
        (wantsLayer, cutout.fillRule) = (true, .evenOdd)
        layer?.mask = cutout
        for shadow in shadows {
            let layer = CALayer()
            (layer.shadowColor, layer.shadowOpacity, layer.shadowRadius, layer.shadowOffset) = (.black, shadow.opacity, shadow.blur / 2, CGSize(width: 0, height: -shadow.offset))
            self.layer?.addSublayer(layer)
        }
    }
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

import AppKit

final class FillView: NSView {
    private var color = NSColor.clear, radius: CGFloat = 0, border: NSColor?
    override var wantsUpdateLayer: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    convenience init(color: NSColor, radius: CGFloat = 0, border: NSColor? = nil) {
        self.init(frame: .zero)
        (self.color, self.radius, self.border, wantsLayer) = (color, radius, border, true)
    }
    override func updateLayer() {
        guard let layer else { return }
        (layer.backgroundColor, layer.cornerRadius, layer.cornerCurve) = (color.cgColor, radius, .continuous)
        (layer.borderWidth, layer.borderColor) = (border == nil ? 0 : 1, border?.cgColor)
    }
}

func surface(radius: CGFloat, tint: NSColor? = nil, solid: NSColor, content: NSView) -> NSView {
    guard #available(macOS 26, *) else {
        let view = NSView()
        FillView(color: solid, radius: radius).fill(view)
        content.fill(view)
        return view
    }
    let glass = NSGlassEffectView()
    (glass.style, glass.cornerRadius, glass.tintColor, glass.contentView) = (.regular, radius, tint, content)
    return glass
}

extension NSView {
    @discardableResult func place(in parent: NSView, top: CGFloat? = nil, bottom: CGFloat? = nil, leading: CGFloat? = nil, trailing: CGFloat? = nil,
                                  centerX: CGFloat? = nil, centerY: CGFloat? = nil, width: CGFloat? = nil, height: CGFloat? = nil) -> Self {
        translatesAutoresizingMaskIntoConstraints = false
        if superview == nil { parent.addSubview(self) }
        NSLayoutConstraint.activate([
            top.map { topAnchor.constraint(equalTo: parent.topAnchor, constant: $0) }, bottom.map { bottomAnchor.constraint(equalTo: parent.bottomAnchor, constant: -$0) },
            leading.map { leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: $0) }, trailing.map { trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -$0) },
            centerX.map { centerXAnchor.constraint(equalTo: parent.centerXAnchor, constant: $0) }, centerY.map { centerYAnchor.constraint(equalTo: parent.centerYAnchor, constant: $0) },
            width.map { widthAnchor.constraint(equalToConstant: $0) }, height.map { heightAnchor.constraint(equalToConstant: $0) },
        ].compactMap { $0 })
        return self
    }
    @discardableResult func fill(_ parent: NSView, _ inset: NSEdgeInsets = NSEdgeInsets()) -> Self {
        place(in: parent, top: inset.top, bottom: inset.bottom, leading: inset.left, trailing: inset.right)
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

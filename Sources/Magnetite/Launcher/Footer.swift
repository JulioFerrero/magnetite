import AppKit

final class Footer: NSView {
    let openButton = FooterButton(title: "Open Application", keys: ["↵"], color: Theme.primaryText)
    let actionsButton = FooterButton(title: "Actions", keys: ["⌘", "K"], color: Theme.secondaryText)
    private lazy var buttons = NSStackView(views: [openButton, actionsButton])
    convenience init() {
        self.init(frame: .zero)
        (buttons.spacing, buttons.edgeInsets) = (0, NSEdgeInsets(top: Theme.pillPadding, left: Theme.pillPadding, bottom: Theme.pillPadding, right: Theme.pillPadding))
        NSLayoutConstraint.activate([widthAnchor.constraint(equalToConstant: buttons.fittingSize.width), heightAnchor.constraint(equalToConstant: Theme.pillHeight)])
    }
    func apply(_ look: Look) {
        subviews.forEach { $0.removeFromSuperview() }
        if look == .performance {
            embed(FillView(color: Theme.solidPill, radius: Theme.pillHeight / 2), buttons)
        } else {
            embed(NSGlassEffectView(style: look.glassStyle, radius: Theme.pillHeight / 2, tint: look == .glass ? Theme.clearGlassTint : nil, content: buttons))
        }
    }
}

import AppKit

enum Theme {
    static let windowSize = NSSize(width: 750, height: 475), shadowMargin = NSEdgeInsets(top: 50, left: 80, bottom: 110, right: 80)
    static let panelSize = NSSize(width: windowSize.width + shadowMargin.left + shadowMargin.right, height: windowSize.height + shadowMargin.top + shadowMargin.bottom)
    static let cornerRadius = 26.0, topOffsetRatio = 0.22, suggestionCount = 5
    static let glassTint = dynamic(NSColor(white: 0, alpha: 0.40), NSColor(white: 1, alpha: 0.40)), windowBorder = dynamic(fg(0.10), .clear)
    static let solidBackground = dynamic(NSColor(white: 0x26 / 255.0, alpha: 1), .white), solidPill = dynamic(NSColor(white: 0x33 / 255.0, alpha: 1), NSColor(white: 0xF2 / 255.0, alpha: 1))
    static let headerHeight = 64.0, headerInset = 16.0, headerGap = 12.0, logoSize = 22.0, searchFieldHeight = 32.0
    static let searchFont = inter(18, weight: 350), placeholder = "Search for apps…"
    static let listTopInset = headerHeight + 8, listBottomInset = footerHeight + 16, topFadeHeight = 96.0, bottomFadeHeight = 72.0
    static let rowMargin = 8.0, rowPadding = 8.0, rowHeight = 38.0, rowRadius = 10.0, iconSize = 22.0, iconGap = 12.0
    static let accessoryGap = 16.0, runningDotSize = 3.0, smallButtonSize = 22.0, sectionHeight = 32.0, sectionLabelCenterY = 19.0, clearButtonGap = 6.0
    static let titleFont = inter(13, contextualAlternates: false), sectionFont = inter(11), emptyFont = inter(13)
    static let footerHeight = 44.0, pillInset = 8.0, pillHeight = 36.0, pillPadding = 4.0
    static let buttonHeight = 28.0, buttonPadding = 6.0, buttonTitlePadding = 4.0, buttonGap = 4.0, buttonFont = inter(12)
    static let keyCapSize = 18.0, keyCapPadding = 4.0, keyCapRadius = 6.0, keyCapGap = 2.0, keyCapFont = inter(10, weight: 500)
    static let primaryText = fg(1), secondaryText = fg(0.60), tertiaryText = fg(0.40), textSelection = fg(0.20)
    static let keyCapBorder = fg(0.20), selection = fg(0.10), hover = fg(0.05)
    private static let interBase = Bundle.main.url(forResource: "InterVariable", withExtension: "ttf")
        .flatMap { (CTFontManagerCreateFontDescriptorsFromURL($0 as CFURL) as? [CTFontDescriptor])?.first }
    static func text(_ string: String, _ font: NSFont, _ color: NSColor, kern: CGFloat = 0.1) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        return NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color, .kern: kern, .paragraphStyle: paragraph])
    }
    private static func fg(_ alpha: CGFloat) -> NSColor { dynamic(NSColor(white: 1, alpha: alpha), NSColor(white: 0, alpha: alpha)) }
    private static func dynamic(_ dark: NSColor, _ light: NSColor) -> NSColor { NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light } }
    private static func inter(_ size: CGFloat, weight: CGFloat = 400, contextualAlternates: Bool = true) -> NSFont {
        guard let interBase else { return .systemFont(ofSize: size) }
        let features: [[CFString: Any]] = [[kCTFontOpenTypeFeatureTag: "ss03", kCTFontOpenTypeFeatureValue: 1]]
            + (contextualAlternates ? [] : [[kCTFontOpenTypeFeatureTag: "calt", kCTFontOpenTypeFeatureValue: 0]])
        let attributes: [CFString: Any] = [kCTFontVariationAttribute: [NSNumber(value: 0x7767_6874): NSNumber(value: weight)], kCTFontFeatureSettingsAttribute: features]
        return CTFontCreateWithFontDescriptor(CTFontDescriptorCreateCopyWithAttributes(interBase, attributes as CFDictionary), size, nil) as NSFont
    }
}

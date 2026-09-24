import AppKit

/// The three window styles offered in Settings.
enum Look: String, CaseIterable, Identifiable {
    case raycast, glass, performance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .raycast: "Raycast"
        case .glass: "Glass"
        case .performance: "Performance"
        }
    }

    var summary: String {
        switch self {
        case .raycast: "Dark-tinted Liquid Glass and a soft shadow, like Raycast 2."
        case .glass: "Clear Liquid Glass with a glass selection that slides between rows."
        case .performance: "Solid background, no blur and no shadow. Lightest on the GPU."
        }
    }

    static var current: Look {
        get { Look(rawValue: UserDefaults.standard.string(forKey: "theme") ?? "") ?? .raycast }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "theme") }
    }

    var usesGlass: Bool { self != .performance }

    /// Room around the card for the shadow; the solid look has no shadow.
    var margin: NSEdgeInsets { usesGlass ? Theme.shadowMargin : NSEdgeInsets() }

    var panelSize: NSSize {
        NSSize(width: Theme.windowSize.width + margin.left + margin.right,
               height: Theme.windowSize.height + margin.top + margin.bottom)
    }
}

/// Every size, color and font in one place. Values mirror Raycast 2.x's root
/// search window on macOS 26+: Liquid Glass window, borderless header floating
/// over the list, floating glass pill footer, Inter everywhere.
enum Theme {
    // Window
    static let windowSize = NSSize(width: 750, height: 475)
    /// Transparent room around the card for its shadow.
    static let shadowMargin = NSEdgeInsets(top: 50, left: 80, bottom: 110, right: 80)
    static let cornerRadius: CGFloat = 26
    static let topOffsetRatio: CGFloat = 0.22
    static let glassTint = dynamic(dark: NSColor(white: 0, alpha: 0.40), light: NSColor(white: 1, alpha: 0.40))
    /// Clear glass barely dims what's behind it; Apple pairs it with a dimming
    /// layer, strong enough here to keep text readable over busy backgrounds.
    static let clearGlassTint = dynamic(dark: NSColor(white: 0, alpha: 0.55), light: NSColor(white: 1, alpha: 0.62))
    /// Performance look: Raycast's own opaque fallbacks (--color-window-base, inactive pill).
    static let solidBackground = dynamic(dark: NSColor(white: 0x26 / 255.0, alpha: 1), light: .white)
    static let solidPill = dynamic(dark: NSColor(white: 0x33 / 255.0, alpha: 1), light: NSColor(white: 0xF2 / 255.0, alpha: 1))
    static let solidBorder = dynamic(dark: NSColor(white: 1, alpha: 0.10), light: NSColor(white: 0, alpha: 0.10))
    static let selectionAnimation: TimeInterval = 0.16
    static let windowBorder = dynamic(dark: fg(0.10), light: .clear)

    // Header (search bar)
    static let headerHeight: CGFloat = 64
    static let headerInset: CGFloat = 16
    static let headerGap: CGFloat = 12
    static let logoSize: CGFloat = 22
    static let searchFont = inter(18, weight: 350)
    static let placeholder = "Search for apps…"

    // List
    static let listTopInset: CGFloat = headerHeight + 8
    static let listBottomInset: CGFloat = footerHeight + 8 + 8
    static let rowMargin: CGFloat = 8
    static let rowPadding: CGFloat = 8
    static let rowHeight: CGFloat = 38
    static let rowRadius: CGFloat = 10
    static let iconSize: CGFloat = 22
    static let iconGap: CGFloat = 12
    static let accessoryGap: CGFloat = 16
    static let runningDotSize: CGFloat = 3
    static let smallButtonSize: CGFloat = 22 // × on history rows, "Clear" in their header
    static let titleFont = inter(13, contextualAlternates: false)
    static let sectionHeight: CGFloat = 32       // 12 spacer + 12 label + 8 margin
    static let sectionLabelCenterY: CGFloat = 19 // from the section row's top
    static let clearButtonGap: CGFloat = 6        // extra room under the Suggestions header's Clear button
    static let sectionFont = inter(11)
    static let emptyFont = inter(13)
    static let suggestionCount = 5
    static let topFadeHeight: CGFloat = 96
    static let bottomFadeHeight: CGFloat = 72

    // Footer: a floating glass pill holding [Open Application ↵] [Actions ⌘ K]
    static let footerHeight: CGFloat = 44
    static let pillInset: CGFloat = 8
    static let pillHeight: CGFloat = 36
    static let pillPadding: CGFloat = 4
    static let buttonHeight: CGFloat = 28
    static let buttonPadding: CGFloat = 6
    static let buttonTitlePadding: CGFloat = 4
    static let buttonGap: CGFloat = 4
    static let buttonFont = inter(12)
    static let keyCapSize: CGFloat = 18
    static let keyCapPadding: CGFloat = 4
    static let keyCapRadius: CGFloat = 6
    static let keyCapGap: CGFloat = 2
    static let keyCapFont = inter(10, weight: 500)

    // Colors: the theme foreground (white in dark, black in light) at fixed alphas
    static let primaryText = fg(1)
    static let secondaryText = fg(0.60)
    static let tertiaryText = fg(0.40)
    static let textSelection = fg(0.20)
    static let keyCapBorder = fg(0.20)
    static let selection = fg(0.10)
    static let hover = fg(0.05)

    // Letter spacing (Inter at 11–13px uses +0.1)
    static let smallKern: CGFloat = 0.1

    static func text(_ string: String, _ font: NSFont, _ color: NSColor, kern: CGFloat = smallKern) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        return NSAttributedString(string: string, attributes: [
            .font: font, .foregroundColor: color, .kern: kern, .paragraphStyle: paragraph,
        ])
    }

    private static func fg(_ alpha: CGFloat) -> NSColor {
        dynamic(dark: NSColor(white: 1, alpha: alpha), light: NSColor(white: 0, alpha: alpha))
    }

    private static func dynamic(dark: NSColor, light: NSColor) -> NSColor {
        NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light }
    }

    // MARK: Inter

    /// Bundled InterVariable.ttf (SIL OFL), loaded straight from the file.
    /// Registering it with the font manager instead costs ~2 MB more: macOS then
    /// works out which of ~300 languages it covers and keeps those tables.
    private static let interBase: CTFontDescriptor? = {
        guard let url = Bundle.main.url(forResource: "InterVariable", withExtension: "ttf") else {
            NSLog("Magnetite: InterVariable.ttf missing from bundle, falling back to the system font")
            return nil
        }
        return (CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor])?.first
    }()

    /// Inter at an exact variable weight, optical size 14 (CSS
    /// `font-optical-sizing: none`) and stylistic set 3, like Raycast. The
    /// bundled file is trimmed to what the UI uses (scripts/make-font.sh).
    private static func inter(_ size: CGFloat, weight: CGFloat = 400, contextualAlternates: Bool = true) -> NSFont {
        guard let interBase else { return .systemFont(ofSize: size) }
        var features: [[CFString: Any]] = [[kCTFontOpenTypeFeatureTag: "ss03", kCTFontOpenTypeFeatureValue: 1]]
        if !contextualAlternates {
            features.append([kCTFontOpenTypeFeatureTag: "calt", kCTFontOpenTypeFeatureValue: 0])
        }
        let attributes: [CFString: Any] = [
            kCTFontVariationAttribute: [NSNumber(value: 0x7767_6874): NSNumber(value: Double(weight))], // wght
            kCTFontFeatureSettingsAttribute: features,
        ]
        let descriptor = CTFontDescriptorCreateCopyWithAttributes(interBase, attributes as CFDictionary)
        return CTFontCreateWithFontDescriptor(descriptor, size, nil) as NSFont
    }
}

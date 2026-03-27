import AppKit

struct PopoverTheme {
    let name: String
    // Popover
    let popoverBg: NSColor
    let popoverBorder: NSColor
    let popoverBorderWidth: CGFloat
    let popoverCornerRadius: CGFloat
    let titleBarBg: NSColor
    let titleText: NSColor
    let titleFont: NSFont
    let titleFormat: TitleFormat
    let separatorColor: NSColor
    // Terminal
    let font: NSFont
    let fontBold: NSFont
    let textPrimary: NSColor
    let textDim: NSColor
    let accentColor: NSColor
    let errorColor: NSColor
    let successColor: NSColor
    let inputBg: NSColor
    let inputCornerRadius: CGFloat
    // Bubble
    let bubbleBg: NSColor
    let bubbleBorder: NSColor
    let bubbleText: NSColor
    let bubbleCompletionBorder: NSColor
    let bubbleCompletionText: NSColor
    let bubbleFont: NSFont
    let bubbleCornerRadius: CGFloat

    // MARK: - Presets

    static let teenageEngineering = PopoverTheme(
        name: "Midnight",
        popoverBg: NSColor(red: 0.07, green: 0.07, blue: 0.07, alpha: 0.96),
        popoverBorder: NSColor(red: 1.0, green: 0.4, blue: 0.0, alpha: 0.7),
        popoverBorderWidth: 1.5,
        popoverCornerRadius: 12,
        titleBarBg: NSColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0),
        titleText: NSColor(red: 1.0, green: 0.4, blue: 0.0, alpha: 1.0),
        titleFont: NSFont(name: "SFMono-Bold", size: 10) ?? .monospacedSystemFont(ofSize: 10, weight: .bold),
        titleFormat: .uppercase,
        separatorColor: NSColor(red: 1.0, green: 0.4, blue: 0.0, alpha: 0.3),
        font: NSFont(name: "SFMono-Regular", size: 11.5) ?? .monospacedSystemFont(ofSize: 11.5, weight: .regular),
        fontBold: NSFont(name: "SFMono-Medium", size: 11.5) ?? .monospacedSystemFont(ofSize: 11.5, weight: .medium),
        textPrimary: NSColor.white,
        textDim: NSColor(white: 0.6, alpha: 1.0),
        accentColor: NSColor(red: 1.0, green: 0.4, blue: 0.0, alpha: 1.0),
        errorColor: NSColor(red: 1.0, green: 0.3, blue: 0.2, alpha: 1.0),
        successColor: NSColor(red: 0.4, green: 0.65, blue: 0.4, alpha: 1.0),
        inputBg: NSColor(red: 0.12, green: 0.12, blue: 0.12, alpha: 1.0),
        inputCornerRadius: 4,
        bubbleBg: NSColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 0.92),
        bubbleBorder: NSColor(red: 1.0, green: 0.4, blue: 0.0, alpha: 0.6),
        bubbleText: NSColor(white: 0.7, alpha: 1.0),
        bubbleCompletionBorder: NSColor(red: 0.3, green: 0.8, blue: 0.3, alpha: 0.7),
        bubbleCompletionText: NSColor(red: 0.3, green: 0.85, blue: 0.3, alpha: 1.0),
        bubbleFont: .monospacedSystemFont(ofSize: 10, weight: .medium),
        bubbleCornerRadius: 12
    )

    static let playful = PopoverTheme(
        name: "Peach",
        popoverBg: NSColor(red: 1.0, green: 0.97, blue: 0.92, alpha: 0.97),
        popoverBorder: NSColor(red: 0.95, green: 0.55, blue: 0.65, alpha: 0.8),
        popoverBorderWidth: 2.5,
        popoverCornerRadius: 24,
        titleBarBg: NSColor(red: 0.98, green: 0.93, blue: 0.88, alpha: 1.0),
        titleText: NSColor(red: 0.85, green: 0.35, blue: 0.45, alpha: 1.0),
        titleFont: .systemFont(ofSize: 12, weight: .heavy),
        titleFormat: .lowercaseTilde,
        separatorColor: NSColor(red: 0.95, green: 0.55, blue: 0.65, alpha: 0.25),
        font: .systemFont(ofSize: 12, weight: .regular),
        fontBold: .systemFont(ofSize: 12, weight: .semibold),
        textPrimary: NSColor(red: 0.2, green: 0.18, blue: 0.22, alpha: 1.0),
        textDim: NSColor(red: 0.5, green: 0.47, blue: 0.52, alpha: 1.0),
        accentColor: NSColor(red: 0.85, green: 0.35, blue: 0.45, alpha: 1.0),
        errorColor: NSColor(red: 0.9, green: 0.3, blue: 0.2, alpha: 1.0),
        successColor: NSColor(red: 0.3, green: 0.72, blue: 0.5, alpha: 1.0),
        inputBg: NSColor(red: 1.0, green: 0.98, blue: 0.95, alpha: 1.0),
        inputCornerRadius: 14,
        bubbleBg: NSColor(red: 1.0, green: 0.95, blue: 0.90, alpha: 0.95),
        bubbleBorder: NSColor(red: 0.95, green: 0.55, blue: 0.65, alpha: 0.6),
        bubbleText: NSColor(red: 0.55, green: 0.5, blue: 0.52, alpha: 1.0),
        bubbleCompletionBorder: NSColor(red: 0.3, green: 0.75, blue: 0.5, alpha: 0.7),
        bubbleCompletionText: NSColor(red: 0.2, green: 0.6, blue: 0.4, alpha: 1.0),
        bubbleFont: .systemFont(ofSize: 11, weight: .semibold),
        bubbleCornerRadius: 14
    )

    static let wii = PopoverTheme(
        name: "Cloud",
        popoverBg: NSColor(red: 0.94, green: 0.95, blue: 0.96, alpha: 0.98),
        popoverBorder: NSColor(red: 0.78, green: 0.80, blue: 0.84, alpha: 0.6),
        popoverBorderWidth: 1,
        popoverCornerRadius: 16,
        titleBarBg: NSColor(red: 0.88, green: 0.90, blue: 0.93, alpha: 1.0),
        titleText: NSColor(red: 0.3, green: 0.3, blue: 0.35, alpha: 1.0),
        titleFont: .systemFont(ofSize: 12, weight: .semibold),
        titleFormat: .lowercaseTilde,
        separatorColor: NSColor(red: 0.8, green: 0.82, blue: 0.85, alpha: 0.4),
        font: .systemFont(ofSize: 12, weight: .regular),
        fontBold: .systemFont(ofSize: 12, weight: .semibold),
        textPrimary: NSColor(red: 0.15, green: 0.15, blue: 0.2, alpha: 1.0),
        textDim: NSColor(red: 0.5, green: 0.5, blue: 0.55, alpha: 1.0),
        accentColor: NSColor(red: 0.0, green: 0.47, blue: 0.84, alpha: 1.0),
        errorColor: NSColor(red: 0.85, green: 0.2, blue: 0.15, alpha: 1.0),
        successColor: NSColor(red: 0.2, green: 0.65, blue: 0.3, alpha: 1.0),
        inputBg: NSColor.white,
        inputCornerRadius: 8,
        bubbleBg: NSColor(red: 0.94, green: 0.95, blue: 0.97, alpha: 0.95),
        bubbleBorder: NSColor(red: 0.0, green: 0.47, blue: 0.84, alpha: 0.4),
        bubbleText: NSColor(red: 0.45, green: 0.47, blue: 0.52, alpha: 1.0),
        bubbleCompletionBorder: NSColor(red: 0.2, green: 0.7, blue: 0.3, alpha: 0.6),
        bubbleCompletionText: NSColor(red: 0.15, green: 0.55, blue: 0.2, alpha: 1.0),
        bubbleFont: .systemFont(ofSize: 10, weight: .semibold),
        bubbleCornerRadius: 12
    )

    static let iPod = PopoverTheme(
        name: "Moss",
        popoverBg: NSColor(red: 0.82, green: 0.84, blue: 0.78, alpha: 0.98),
        popoverBorder: NSColor(red: 0.55, green: 0.58, blue: 0.50, alpha: 0.8),
        popoverBorderWidth: 2,
        popoverCornerRadius: 10,
        titleBarBg: NSColor(red: 0.72, green: 0.75, blue: 0.68, alpha: 1.0),
        titleText: NSColor(red: 0.15, green: 0.17, blue: 0.12, alpha: 1.0),
        titleFont: NSFont(name: "Chicago", size: 11) ?? .systemFont(ofSize: 11, weight: .bold),
        titleFormat: .capitalized,
        separatorColor: NSColor(red: 0.55, green: 0.58, blue: 0.50, alpha: 0.5),
        font: NSFont(name: "Geneva", size: 11) ?? .monospacedSystemFont(ofSize: 11, weight: .regular),
        fontBold: NSFont(name: "Geneva", size: 11) ?? .monospacedSystemFont(ofSize: 11, weight: .bold),
        textPrimary: NSColor(red: 0.1, green: 0.12, blue: 0.08, alpha: 1.0),
        textDim: NSColor(red: 0.35, green: 0.38, blue: 0.30, alpha: 1.0),
        accentColor: NSColor(red: 0.2, green: 0.22, blue: 0.15, alpha: 1.0),
        errorColor: NSColor(red: 0.6, green: 0.15, blue: 0.1, alpha: 1.0),
        successColor: NSColor(red: 0.15, green: 0.4, blue: 0.15, alpha: 1.0),
        inputBg: NSColor(red: 0.88, green: 0.90, blue: 0.84, alpha: 1.0),
        inputCornerRadius: 3,
        bubbleBg: NSColor(red: 0.82, green: 0.84, blue: 0.78, alpha: 0.95),
        bubbleBorder: NSColor(red: 0.55, green: 0.58, blue: 0.50, alpha: 0.7),
        bubbleText: NSColor(red: 0.4, green: 0.42, blue: 0.38, alpha: 1.0),
        bubbleCompletionBorder: NSColor(red: 0.2, green: 0.5, blue: 0.2, alpha: 0.7),
        bubbleCompletionText: NSColor(red: 0.15, green: 0.4, blue: 0.15, alpha: 1.0),
        bubbleFont: NSFont(name: "Geneva", size: 10) ?? .monospacedSystemFont(ofSize: 10, weight: .medium),
        bubbleCornerRadius: 8
    )

    static let allThemes: [PopoverTheme] = [.playful, .teenageEngineering, .wii, .iPod]
    static var current: PopoverTheme = .playful
    static var customFontName: String? = ".AppleSystemUIFontRounded"
    static var customFontSize: CGFloat = 13

    // MARK: - Theme Modifiers

    func withCharacterColor(_ color: NSColor) -> PopoverTheme {
        guard name == "Peach" else { return self }
        let r = color.redComponent, g = color.greenComponent, b = color.blueComponent
        let light = NSColor(red: min(r + 0.4, 1), green: min(g + 0.4, 1), blue: min(b + 0.4, 1), alpha: 0.25)
        let border = NSColor(red: r, green: g, blue: b, alpha: 0.6)
        return PopoverTheme(
            name: name, popoverBg: popoverBg,
            popoverBorder: border,
            popoverBorderWidth: popoverBorderWidth, popoverCornerRadius: popoverCornerRadius,
            titleBarBg: NSColor(red: min(r * 0.3 + 0.7, 1), green: min(g * 0.3 + 0.7, 1), blue: min(b * 0.3 + 0.7, 1), alpha: 1.0),
            titleText: color, titleFont: titleFont, titleFormat: titleFormat,
            separatorColor: light,
            font: font, fontBold: fontBold,
            textPrimary: textPrimary, textDim: textDim,
            accentColor: color,
            errorColor: errorColor, successColor: successColor,
            inputBg: inputBg, inputCornerRadius: inputCornerRadius,
            bubbleBg: NSColor(red: min(r * 0.15 + 0.85, 1), green: min(g * 0.15 + 0.85, 1), blue: min(b * 0.15 + 0.85, 1), alpha: 0.95),
            bubbleBorder: border,
            bubbleText: bubbleText,
            bubbleCompletionBorder: bubbleCompletionBorder, bubbleCompletionText: bubbleCompletionText,
            bubbleFont: bubbleFont, bubbleCornerRadius: bubbleCornerRadius
        )
    }

    func withCustomFont() -> PopoverTheme {
        // Midnight uses its own mono font — don't override
        guard name != "Midnight" else { return self }
        guard let fontName = PopoverTheme.customFontName,
              let baseFont = NSFont(name: fontName, size: PopoverTheme.customFontSize) else { return self }
        let boldFont = NSFontManager.shared.convert(baseFont, toHaveTrait: .boldFontMask)
        let smallFont = NSFont(name: fontName, size: PopoverTheme.customFontSize - 1) ?? baseFont
        return PopoverTheme(
            name: name, popoverBg: popoverBg, popoverBorder: popoverBorder,
            popoverBorderWidth: popoverBorderWidth, popoverCornerRadius: popoverCornerRadius,
            titleBarBg: titleBarBg, titleText: titleText, titleFont: titleFont, titleFormat: titleFormat,
            separatorColor: separatorColor,
            font: baseFont, fontBold: boldFont,
            textPrimary: textPrimary, textDim: textDim, accentColor: accentColor,
            errorColor: errorColor, successColor: successColor,
            inputBg: inputBg, inputCornerRadius: inputCornerRadius,
            bubbleBg: bubbleBg, bubbleBorder: bubbleBorder, bubbleText: bubbleText,
            bubbleCompletionBorder: bubbleCompletionBorder, bubbleCompletionText: bubbleCompletionText,
            bubbleFont: smallFont, bubbleCornerRadius: bubbleCornerRadius
        )
    }
}

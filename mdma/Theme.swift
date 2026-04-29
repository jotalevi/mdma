import AppKit
import SwiftUI
import Combine

// MARK: - ThemeColors (live NSColor cache for current theme)

final class ThemeColors {

    // Appearance-adaptive colors
    let bg:          NSColor
    let sidebar:     NSColor
    let text:        NSColor
    let heading:     NSColor
    let muted:       NSColor
    let quote:       NSColor
    let codeBg:      NSColor
    let syntaxCol:   NSColor
    let tableHead:   NSColor
    let tableEven:   NSColor
    let tableOdd:    NSColor
    let tableBorder: NSColor

    // Fixed accent colors (same in dark & light)
    let accent:      NSColor
    let contactCol:  NSColor
    let fileRefCol:  NSColor
    let linkColor:   NSColor
    let codeColor:   NSColor
    let greenCol:    NSColor

    init(theme t: Theme) {
        let n = t.name   // use name to disambiguate NSColor cache entries

        bg          = ThemeColors.adaptive(dark: t.bgDark,          light: t.bgLight,          name: "bg.\(n)")
        sidebar     = ThemeColors.adaptive(dark: t.sidebarDark,     light: t.sidebarLight,     name: "sidebar.\(n)")
        text        = ThemeColors.adaptive(dark: t.textDark,        light: t.textLight,        name: "text.\(n)")
        heading     = ThemeColors.adaptive(dark: t.headingDark,     light: t.headingLight,     name: "heading.\(n)")
        muted       = ThemeColors.adaptive(dark: t.mutedDark,       light: t.mutedLight,       name: "muted.\(n)")
        quote       = ThemeColors.adaptive(dark: t.quoteDark,       light: t.quoteLight,       name: "quote.\(n)")
        codeBg      = ThemeColors.adaptive(dark: t.codeBgDark,      light: t.codeBgLight,      name: "codeBg.\(n)")
        syntaxCol   = ThemeColors.adaptive(dark: t.syntaxColDark,   light: t.syntaxColLight,   name: "syntaxCol.\(n)")
        tableHead   = ThemeColors.adaptive(dark: t.tableHeadDark,   light: t.tableHeadLight,   name: "tableHead.\(n)")
        tableEven   = ThemeColors.adaptive(dark: t.tableEvenDark,   light: t.tableEvenLight,   name: "tableEven.\(n)")
        tableOdd    = ThemeColors.adaptive(dark: t.tableOddDark,    light: t.tableOddLight,    name: "tableOdd.\(n)")
        tableBorder = ThemeColors.adaptive(dark: t.tableBorderDark, light: t.tableBorderLight, name: "tableBorder.\(n)")

        accent     = t.accent
        contactCol = t.contactCol
        fileRefCol = t.fileRefCol
        linkColor  = t.linkColor
        codeColor  = t.codeColor
        greenCol   = t.greenCol
    }

    private static func adaptive(dark: NSColor, light: NSColor, name: String) -> NSColor {
        NSColor(name: name) { ap in
            ap.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }
    }
}

// MARK: - Theme (definition)

struct Theme {
    let name: String

    // Adaptive palette
    let bgDark:          NSColor; let bgLight:          NSColor
    let sidebarDark:     NSColor; let sidebarLight:     NSColor
    let textDark:        NSColor; let textLight:        NSColor
    let headingDark:     NSColor; let headingLight:     NSColor
    let mutedDark:       NSColor; let mutedLight:       NSColor
    let quoteDark:       NSColor; let quoteLight:       NSColor
    let codeBgDark:      NSColor; let codeBgLight:      NSColor
    let syntaxColDark:   NSColor; let syntaxColLight:   NSColor
    let tableHeadDark:   NSColor; let tableHeadLight:   NSColor
    let tableEvenDark:   NSColor; let tableEvenLight:   NSColor
    let tableOddDark:    NSColor; let tableOddLight:    NSColor
    let tableBorderDark: NSColor; let tableBorderLight: NSColor

    // Fixed accents
    let accent:      NSColor
    let contactCol:  NSColor
    let fileRefCol:  NSColor
    let linkColor:   NSColor
    let codeColor:   NSColor
    let greenCol:    NSColor
}

// MARK: - Predefined Themes

extension Theme {

    // ─── Original ───────────────────────────────────────────────────────────
    static let original = Theme(
        name: "Original",
        bgDark:          rgb(0.105, 0.105, 0.115), bgLight:          rgb(0.970, 0.970, 0.975),
        sidebarDark:     rgb(0.118, 0.118, 0.128), sidebarLight:     rgb(0.948, 0.948, 0.955),
        textDark:        rgb(0.830, 0.830, 0.850), textLight:        rgb(0.110, 0.110, 0.130),
        headingDark:     rgb(1.000, 1.000, 1.000), headingLight:     rgb(0.000, 0.000, 0.000),
        mutedDark:       rgb(0.400, 0.400, 0.450), mutedLight:       rgb(0.520, 0.520, 0.560),
        quoteDark:       rgb(0.520, 0.520, 0.580), quoteLight:       rgb(0.420, 0.420, 0.470),
        codeBgDark:      rgb(0.140, 0.140, 0.158), codeBgLight:      rgb(0.900, 0.900, 0.912),
        syntaxColDark:   rgb(0.340, 0.340, 0.390), syntaxColLight:   rgb(0.580, 0.580, 0.620),
        tableHeadDark:   rgb(0.200, 0.185, 0.290), tableHeadLight:   rgb(0.880, 0.870, 0.950),
        tableEvenDark:   rgb(0.140, 0.140, 0.158), tableEvenLight:   rgb(0.940, 0.940, 0.950),
        tableOddDark:    rgb(0.125, 0.125, 0.142), tableOddLight:    rgb(0.920, 0.920, 0.932),
        tableBorderDark: rgb(0.320, 0.300, 0.440), tableBorderLight: rgb(0.680, 0.660, 0.780),
        accent:      rgb(0.490, 0.420, 0.940),
        contactCol:  rgb(0.300, 0.750, 0.650),
        fileRefCol:  rgb(0.900, 0.650, 0.250),
        linkColor:   rgb(0.380, 0.660, 1.000),
        codeColor:   rgb(0.780, 0.510, 0.410),
        greenCol:    rgb(0.380, 0.780, 0.500)
    )

    // ─── High Contrast ───────────────────────────────────────────────────────
    static let highContrast = Theme(
        name: "High Contrast",
        bgDark:          rgb(0.000, 0.000, 0.000), bgLight:          rgb(1.000, 1.000, 1.000),
        sidebarDark:     rgb(0.050, 0.050, 0.050), sidebarLight:     rgb(0.940, 0.940, 0.940),
        textDark:        rgb(0.940, 0.940, 0.940), textLight:        rgb(0.060, 0.060, 0.060),
        headingDark:     rgb(1.000, 1.000, 1.000), headingLight:     rgb(0.000, 0.000, 0.000),
        mutedDark:       rgb(0.600, 0.600, 0.600), mutedLight:       rgb(0.400, 0.400, 0.400),
        quoteDark:       rgb(0.750, 0.750, 0.750), quoteLight:       rgb(0.300, 0.300, 0.300),
        codeBgDark:      rgb(0.090, 0.090, 0.090), codeBgLight:      rgb(0.900, 0.900, 0.900),
        syntaxColDark:   rgb(0.500, 0.500, 0.500), syntaxColLight:   rgb(0.500, 0.500, 0.500),
        tableHeadDark:   rgb(0.100, 0.100, 0.180), tableHeadLight:   rgb(0.820, 0.820, 0.940),
        tableEvenDark:   rgb(0.090, 0.090, 0.090), tableEvenLight:   rgb(0.900, 0.900, 0.900),
        tableOddDark:    rgb(0.070, 0.070, 0.070), tableOddLight:    rgb(0.880, 0.880, 0.880),
        tableBorderDark: rgb(0.800, 0.800, 0.800), tableBorderLight: rgb(0.200, 0.200, 0.200),
        accent:      rgb(1.000, 0.850, 0.000),   // gold
        contactCol:  rgb(0.000, 0.900, 1.000),   // cyan
        fileRefCol:  rgb(1.000, 0.400, 0.000),   // orange
        linkColor:   rgb(0.000, 0.533, 1.000),   // electric blue
        codeColor:   rgb(1.000, 0.500, 0.500),   // salmon
        greenCol:    rgb(0.200, 1.000, 0.400)    // bright green
    )

    // ─── Pastel ───────────────────────────────────────────────────────────────
    static let pastel = Theme(
        name: "Pastel",
        bgDark:          rgb(0.118, 0.102, 0.180), bgLight:          rgb(0.980, 0.972, 1.000),
        sidebarDark:     rgb(0.137, 0.122, 0.200), sidebarLight:     rgb(0.950, 0.940, 0.990),
        textDark:        rgb(0.832, 0.800, 0.940), textLight:        rgb(0.230, 0.190, 0.310),
        headingDark:     rgb(0.950, 0.930, 1.000), headingLight:     rgb(0.100, 0.060, 0.200),
        mutedDark:       rgb(0.470, 0.440, 0.620), mutedLight:       rgb(0.560, 0.510, 0.680),
        quoteDark:       rgb(0.560, 0.530, 0.700), quoteLight:       rgb(0.440, 0.400, 0.600),
        codeBgDark:      rgb(0.168, 0.148, 0.252), codeBgLight:      rgb(0.928, 0.912, 0.980),
        syntaxColDark:   rgb(0.420, 0.390, 0.560), syntaxColLight:   rgb(0.600, 0.560, 0.720),
        tableHeadDark:   rgb(0.188, 0.165, 0.310), tableHeadLight:   rgb(0.882, 0.866, 0.970),
        tableEvenDark:   rgb(0.168, 0.148, 0.252), tableEvenLight:   rgb(0.928, 0.912, 0.980),
        tableOddDark:    rgb(0.148, 0.130, 0.228), tableOddLight:    rgb(0.908, 0.890, 0.964),
        tableBorderDark: rgb(0.380, 0.348, 0.620), tableBorderLight: rgb(0.700, 0.668, 0.860),
        accent:      rgb(0.788, 0.565, 0.878),   // lavender-rose
        contactCol:  rgb(0.490, 0.784, 0.627),   // sage green
        fileRefCol:  rgb(0.942, 0.659, 0.471),   // peach
        linkColor:   rgb(0.502, 0.565, 0.910),   // periwinkle
        codeColor:   rgb(0.878, 0.541, 0.541),   // dusty rose
        greenCol:    rgb(0.490, 0.878, 0.627)    // mint
    )

    // ─── Solarized ────────────────────────────────────────────────────────────
    static let solarized = Theme(
        name: "Solarized",
        bgDark:          rgb(0.000, 0.169, 0.212), bgLight:          rgb(0.992, 0.965, 0.890),
        sidebarDark:     rgb(0.027, 0.212, 0.259), sidebarLight:     rgb(0.933, 0.910, 0.835),
        textDark:        rgb(0.514, 0.580, 0.588), textLight:        rgb(0.396, 0.482, 0.514),
        headingDark:     rgb(0.576, 0.631, 0.631), headingLight:     rgb(0.027, 0.212, 0.259),
        mutedDark:       rgb(0.345, 0.431, 0.459), mutedLight:       rgb(0.576, 0.631, 0.631),
        quoteDark:       rgb(0.420, 0.486, 0.490), quoteLight:       rgb(0.480, 0.545, 0.550),
        codeBgDark:      rgb(0.027, 0.212, 0.259), codeBgLight:      rgb(0.933, 0.910, 0.835),
        syntaxColDark:   rgb(0.310, 0.390, 0.420), syntaxColLight:   rgb(0.620, 0.675, 0.680),
        tableHeadDark:   rgb(0.027, 0.212, 0.259), tableHeadLight:   rgb(0.878, 0.851, 0.780),
        tableEvenDark:   rgb(0.027, 0.212, 0.259), tableEvenLight:   rgb(0.933, 0.910, 0.835),
        tableOddDark:    rgb(0.000, 0.169, 0.212), tableOddLight:    rgb(0.908, 0.882, 0.808),
        tableBorderDark: rgb(0.165, 0.631, 0.596), tableBorderLight: rgb(0.576, 0.631, 0.631),
        accent:      rgb(0.424, 0.443, 0.769),   // violet
        contactCol:  rgb(0.165, 0.631, 0.596),   // cyan
        fileRefCol:  rgb(0.796, 0.294, 0.086),   // orange-red
        linkColor:   rgb(0.149, 0.545, 0.824),   // blue
        codeColor:   rgb(0.522, 0.600, 0.000),   // green
        greenCol:    rgb(0.522, 0.600, 0.000)    // green
    )

    // ─── Nord ─────────────────────────────────────────────────────────────────
    // Polar-inspired palette: cool arctic blues/greens on dark slate or snow-white.
    static let nord = Theme(
        name: "Nord",
        bgDark:          rgb(0.180, 0.204, 0.251), bgLight:          rgb(0.957, 0.961, 0.973),
        sidebarDark:     rgb(0.196, 0.220, 0.267), sidebarLight:     rgb(0.922, 0.929, 0.945),
        textDark:        rgb(0.847, 0.871, 0.914), textLight:        rgb(0.180, 0.204, 0.251),
        headingDark:     rgb(0.925, 0.937, 0.957), headingLight:     rgb(0.118, 0.141, 0.192),
        mutedDark:       rgb(0.506, 0.537, 0.600), mutedLight:       rgb(0.537, 0.561, 0.624),
        quoteDark:       rgb(0.580, 0.612, 0.675), quoteLight:       rgb(0.506, 0.537, 0.600),
        codeBgDark:      rgb(0.231, 0.259, 0.318), codeBgLight:      rgb(0.902, 0.910, 0.929),
        syntaxColDark:   rgb(0.380, 0.412, 0.478), syntaxColLight:   rgb(0.612, 0.639, 0.702),
        tableHeadDark:   rgb(0.231, 0.259, 0.318), tableHeadLight:   rgb(0.871, 0.882, 0.910),
        tableEvenDark:   rgb(0.231, 0.259, 0.318), tableEvenLight:   rgb(0.902, 0.910, 0.929),
        tableOddDark:    rgb(0.212, 0.239, 0.298), tableOddLight:    rgb(0.882, 0.894, 0.918),
        tableBorderDark: rgb(0.384, 0.678, 0.773), tableBorderLight: rgb(0.384, 0.678, 0.773),
        accent:      rgb(0.384, 0.678, 0.773),   // frost blue
        contactCol:  rgb(0.631, 0.792, 0.663),   // aurora green
        fileRefCol:  rgb(0.922, 0.729, 0.392),   // aurora yellow
        linkColor:   rgb(0.486, 0.725, 0.855),   // frost light
        codeColor:   rgb(0.816, 0.529, 0.439),   // aurora red
        greenCol:    rgb(0.631, 0.792, 0.663)    // aurora green
    )

    // ─── Sepia ────────────────────────────────────────────────────────────────
    // Warm parchment tones — like writing on aged paper. Rich amber in dark mode.
    static let sepia = Theme(
        name: "Sepia",
        bgDark:          rgb(0.157, 0.125, 0.086), bgLight:          rgb(0.973, 0.953, 0.910),
        sidebarDark:     rgb(0.180, 0.145, 0.102), sidebarLight:     rgb(0.941, 0.914, 0.863),
        textDark:        rgb(0.855, 0.800, 0.710), textLight:        rgb(0.259, 0.196, 0.125),
        headingDark:     rgb(0.957, 0.902, 0.800), headingLight:     rgb(0.157, 0.110, 0.063),
        mutedDark:       rgb(0.518, 0.443, 0.337), mutedLight:       rgb(0.569, 0.490, 0.384),
        quoteDark:       rgb(0.604, 0.518, 0.400), quoteLight:       rgb(0.510, 0.435, 0.341),
        codeBgDark:      rgb(0.208, 0.165, 0.118), codeBgLight:      rgb(0.906, 0.875, 0.820),
        syntaxColDark:   rgb(0.443, 0.369, 0.263), syntaxColLight:   rgb(0.624, 0.541, 0.435),
        tableHeadDark:   rgb(0.235, 0.188, 0.133), tableHeadLight:   rgb(0.878, 0.843, 0.773),
        tableEvenDark:   rgb(0.208, 0.165, 0.118), tableEvenLight:   rgb(0.910, 0.878, 0.820),
        tableOddDark:    rgb(0.188, 0.149, 0.106), tableOddLight:    rgb(0.886, 0.855, 0.796),
        tableBorderDark: rgb(0.604, 0.471, 0.275), tableBorderLight: rgb(0.663, 0.514, 0.310),
        accent:      rgb(0.780, 0.502, 0.153),   // warm amber
        contactCol:  rgb(0.431, 0.706, 0.514),   // sage
        fileRefCol:  rgb(0.820, 0.604, 0.290),   // gold
        linkColor:   rgb(0.502, 0.647, 0.796),   // dusty blue
        codeColor:   rgb(0.741, 0.400, 0.310),   // terracotta
        greenCol:    rgb(0.431, 0.706, 0.514)    // sage
    )

    static let all: [Theme] = [original, highContrast, pastel, solarized, nord, sepia]

    // Helper
    private static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
        NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
    }
}

// MARK: - ThemeManager

final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    @AppStorage("themeName") var themeName: String = "Original" {
        didSet {
            guard oldValue != themeName else { return }
            rebuildColors()
            objectWillChange.send()
            NotificationCenter.default.post(name: .themeDidChange, object: nil)
        }
    }

    private(set) var colors: ThemeColors

    private init() {
        let saved = UserDefaults.standard.string(forKey: "themeName") ?? "Original"
        let theme = Theme.all.first { $0.name == saved } ?? Theme.original
        colors = ThemeColors(theme: theme)
    }

    private func rebuildColors() {
        let theme = Theme.all.first { $0.name == themeName } ?? Theme.original
        colors = ThemeColors(theme: theme)
    }

    var currentTheme: Theme {
        Theme.all.first { $0.name == themeName } ?? Theme.original
    }
}

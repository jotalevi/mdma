import UIKit
import Combine

// MARK: - ThemeColors

final class ThemeColors {

    let bg:          UIColor
    let sidebar:     UIColor
    let text:        UIColor
    let heading:     UIColor
    let muted:       UIColor
    let quote:       UIColor
    let codeBg:      UIColor
    let syntaxCol:   UIColor
    let tableHead:   UIColor
    let tableEven:   UIColor
    let tableOdd:    UIColor
    let tableBorder: UIColor

    let accent:      UIColor
    let contactCol:  UIColor
    let fileRefCol:  UIColor
    let linkColor:   UIColor
    let codeColor:   UIColor
    let greenCol:    UIColor

    init(theme t: Theme) {
        bg          = ThemeColors.adaptive(dark: t.bgDark,          light: t.bgLight)
        sidebar     = ThemeColors.adaptive(dark: t.sidebarDark,     light: t.sidebarLight)
        text        = ThemeColors.adaptive(dark: t.textDark,        light: t.textLight)
        heading     = ThemeColors.adaptive(dark: t.headingDark,     light: t.headingLight)
        muted       = ThemeColors.adaptive(dark: t.mutedDark,       light: t.mutedLight)
        quote       = ThemeColors.adaptive(dark: t.quoteDark,       light: t.quoteLight)
        codeBg      = ThemeColors.adaptive(dark: t.codeBgDark,      light: t.codeBgLight)
        syntaxCol   = ThemeColors.adaptive(dark: t.syntaxColDark,   light: t.syntaxColLight)
        tableHead   = ThemeColors.adaptive(dark: t.tableHeadDark,   light: t.tableHeadLight)
        tableEven   = ThemeColors.adaptive(dark: t.tableEvenDark,   light: t.tableEvenLight)
        tableOdd    = ThemeColors.adaptive(dark: t.tableOddDark,    light: t.tableOddLight)
        tableBorder = ThemeColors.adaptive(dark: t.tableBorderDark, light: t.tableBorderLight)
        accent     = t.accent
        contactCol = t.contactCol
        fileRefCol = t.fileRefCol
        linkColor  = t.linkColor
        codeColor  = t.codeColor
        greenCol   = t.greenCol
    }

    private static func adaptive(dark: UIColor, light: UIColor) -> UIColor {
        UIColor { traits in traits.userInterfaceStyle == .dark ? dark : light }
    }
}

// MARK: - Theme

struct Theme {
    let name: String

    let bgDark:          UIColor; let bgLight:          UIColor
    let sidebarDark:     UIColor; let sidebarLight:     UIColor
    let textDark:        UIColor; let textLight:        UIColor
    let headingDark:     UIColor; let headingLight:     UIColor
    let mutedDark:       UIColor; let mutedLight:       UIColor
    let quoteDark:       UIColor; let quoteLight:       UIColor
    let codeBgDark:      UIColor; let codeBgLight:      UIColor
    let syntaxColDark:   UIColor; let syntaxColLight:   UIColor
    let tableHeadDark:   UIColor; let tableHeadLight:   UIColor
    let tableEvenDark:   UIColor; let tableEvenLight:   UIColor
    let tableOddDark:    UIColor; let tableOddLight:    UIColor
    let tableBorderDark: UIColor; let tableBorderLight: UIColor

    let accent:      UIColor
    let contactCol:  UIColor
    let fileRefCol:  UIColor
    let linkColor:   UIColor
    let codeColor:   UIColor
    let greenCol:    UIColor
}

extension Theme {
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
        accent:      rgb(1.000, 0.850, 0.000),
        contactCol:  rgb(0.000, 0.900, 1.000),
        fileRefCol:  rgb(1.000, 0.400, 0.000),
        linkColor:   rgb(0.000, 0.533, 1.000),
        codeColor:   rgb(1.000, 0.500, 0.500),
        greenCol:    rgb(0.200, 1.000, 0.400)
    )

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
        accent:      rgb(0.788, 0.565, 0.878),
        contactCol:  rgb(0.490, 0.784, 0.627),
        fileRefCol:  rgb(0.942, 0.659, 0.471),
        linkColor:   rgb(0.502, 0.565, 0.910),
        codeColor:   rgb(0.878, 0.541, 0.541),
        greenCol:    rgb(0.490, 0.878, 0.627)
    )

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
        accent:      rgb(0.424, 0.443, 0.769),
        contactCol:  rgb(0.165, 0.631, 0.596),
        fileRefCol:  rgb(0.796, 0.294, 0.086),
        linkColor:   rgb(0.149, 0.545, 0.824),
        codeColor:   rgb(0.522, 0.600, 0.000),
        greenCol:    rgb(0.522, 0.600, 0.000)
    )

    static let all: [Theme] = [original, highContrast, pastel, solarized]

    private static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> UIColor {
        UIColor(red: r, green: g, blue: b, alpha: 1)
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

extension Notification.Name {
    static let themeDidChange = Notification.Name("themeDidChange")
}

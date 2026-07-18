import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Central design tokens for Helm — a nautical navy & brass palette.
/// Keeping spacing, radii, colors and typography in one place is what makes the
/// app feel consistent across iPhone, iPad and Mac.
enum Theme {

    // MARK: Palette — The Bridge
    // A confident, warm palette rooted in deep navy sea tones with a brass
    // compass-rose accent. Brand colors (navy, brass, sidebar) are constant in
    // both appearances; canvas/surface/text tokens resolve per light/dark via
    // `Color.dynamic` so the whole app adapts without touching call sites.
    enum Palette {
        /// Deep navy — sidebar, brand backgrounds, dark cards. Constant in both modes.
        static let navy = Color(hex: "#142138")
        /// Brass / gold — the compass-rose accent, active nav indicators, CTAs.
        static let brass = Color(hex: "#D4AF37")
        /// Diminished gold — completed checkboxes, muted brass accents.
        static let brassDim = Color(hex: "#B9922E")
        /// Light text/icons sitting on navy surfaces (wordmark, chat bubbles).
        /// Constant: navy stays navy in dark mode, so its foreground must stay light.
        static let onNavy = Color(hex: "#F5F7FA")
        /// Page-level backgrounds.
        static let canvas = Color.dynamic(light: "#F2F3F5", dark: "#101826")
        /// Card surfaces.
        static let surface = Color.dynamic(light: "#FFFFFF", dark: "#1A2436")
        /// Card / divider borders.
        static let border = Color.dynamic(light: "#E2E5EA", dark: "#2C3A54")
        /// Very subtle divider.
        static let hairline = Color.dynamic(light: "#EEF0F3", dark: "#24304A")
        /// Card drop shadow — black works over both light and dark canvases.
        static let cardShadow = Color.black.opacity(0.06)

        // Primary / secondary text (on canvas or card surfaces)
        static let textPrimary = Color.dynamic(light: "#1D2637", dark: "#E8ECF4")
        static let textSecondary = Color.dynamic(light: "#6B7484", dark: "#A7B1C4")
        static let textMuted = Color.dynamic(light: "#9AA3B2", dark: "#7A8699")

        // Sidebar text hierarchy (on navy — constant in both modes)
        static let sidebarText = Color(hex: "#C7CEDC")
        static let sidebarMuted = Color(hex: "#8E99AD")
        static let sidebarDark = Color(hex: "#5D6B84")
        /// Active nav item background (brass tint on navy).
        static let sidebarActiveBg = Color(hex: "#D4AF37").opacity(0.12)
        /// Active nav item text / accent.
        static let sidebarActiveText = Color(hex: "#E9D48A")
        /// Active/hover row background for secondary sidebar rows (charts list).
        static let sidebarRowActiveBg = Color.white.opacity(0.06)

        // Semantic — lifted slightly in dark so they read on dark surfaces
        static let success = Color.dynamic(light: "#4FBF8B", dark: "#5FD09B")
        static let danger = Color.dynamic(light: "#C2503E", dark: "#E06B58")
        static let warning = Color.dynamic(light: "#C77E28", dark: "#E09A44")
        static let info = Color.dynamic(light: "#5B8DB8", dark: "#7FA9CE")
        static let infoLight = Color.dynamic(light: "#8FB6D9", dark: "#A5C6E4")

        // Tag / chip backgrounds (on surface)
        static let tagBg = Color.dynamic(light: "#E8ECF3", dark: "#263349")
        static let tagText = Color.dynamic(light: "#142138", dark: "#D8DFEC")

        // Focus block (calendar) — subtle diagonal hatch
        static let focusBg = Color.dynamic(light: "#F7F0DC", dark: "#2C2718")
        static let focusBorder = Color.dynamic(light: "#DFCE9A", dark: "#59491F")
        static let focusText = Color.dynamic(light: "#8A742C", dark: "#D9C26A")

        // Won deal card
        static let wonBg = Color.dynamic(light: "#F7F9F8", dark: "#1B2822")
        static let wonBorder = Color.dynamic(light: "#DCE9E1", dark: "#2E4A3B")
        static let wonText = Color.dynamic(light: "#3E6B52", dark: "#86C7A1")
    }

    // MARK: Spacing
    enum Spacing {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    // MARK: Corner radii
    enum Radius {
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 14
        static let xl: CGFloat = 18
        static let pill: CGFloat = 999
    }

    // MARK: Semantic surfaces
    /// Card / grouped background that adapts to light & dark and to platform.
    static var cardBackground: Color {
        #if os(macOS)
        Color(nsColor: .textBackgroundColor)
        #else
        Color(uiColor: .secondarySystemGroupedBackground)
        #endif
    }

    static var canvasBackground: Color {
        #if os(macOS)
        Color(nsColor: .underPageBackgroundColor)
        #else
        Color(uiColor: .systemGroupedBackground)
        #endif
    }

    static var subtleFill: Color {
        #if os(macOS)
        Color(nsColor: .quaternaryLabelColor).opacity(0.35)
        #else
        Color(uiColor: .tertiarySystemFill)
        #endif
    }
}

// MARK: - Color hex support

extension Color {
    /// A color that resolves to a different hex value in light vs. dark
    /// appearance. Built on the platform "dynamic provider" APIs, which are
    /// re-queried whenever the effective appearance changes — including when
    /// the user forces Light/Dark via `preferredColorScheme`.
    static func dynamic(light: String, dark: String) -> Color {
        #if os(macOS)
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(Color(hex: isDark ? dark : light))
        })
        #else
        Color(uiColor: UIColor { traits in
            UIColor(Color(hex: traits.userInterfaceStyle == .dark ? dark : light))
        })
        #endif
    }

    /// Creates a color from a hex string such as `#RRGGBB` or `RRGGBBAA`.
    init(hex: String) {
        let sanitized = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var rgb: UInt64 = 0
        Scanner(string: sanitized).scanHexInt64(&rgb)

        let r, g, b, a: Double
        switch sanitized.count {
        case 8: // RRGGBBAA
            r = Double((rgb & 0xFF00_0000) >> 24) / 255
            g = Double((rgb & 0x00FF_0000) >> 16) / 255
            b = Double((rgb & 0x0000_FF00) >> 8) / 255
            a = Double(rgb & 0x0000_00FF) / 255
        default: // RRGGBB
            r = Double((rgb & 0xFF0000) >> 16) / 255
            g = Double((rgb & 0x00FF00) >> 8) / 255
            b = Double(rgb & 0x0000FF) / 255
            a = 1
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }

    /// Hex string representation (`#RRGGBB`). Falls back to a neutral gray if the
    /// components can't be resolved on the current platform.
    var hexString: String {
        #if os(macOS)
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return "#6B7280" }
        let r = Int(round(c.redComponent * 255))
        let g = Int(round(c.greenComponent * 255))
        let b = Int(round(c.blueComponent * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
        #else
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(round(r * 255)), Int(round(g * 255)), Int(round(b * 255)))
        #endif
    }
}
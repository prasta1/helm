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
    // compass-rose accent. Silver-gray text on light canvas keeps the UI
    // readable without competing with the brand color.
    enum Palette {
        /// Deep navy — sidebar, brand backgrounds, dark cards.
        static let navy = Color(hex: "#142138")
        /// Brass / gold — the compass-rose accent, active nav indicators, CTAs.
        static let brass = Color(hex: "#D4AF37")
        /// Diminished gold — completed checkboxes, muted brass accents.
        static let brassDim = Color(hex: "#B9922E")
        /// Light canvas — page-level backgrounds.
        static let canvas = Color(hex: "#F2F3F5")
        /// Card surfaces.
        static let surface = Color(hex: "#FFFFFF")
        /// Card / divider borders.
        static let border = Color(hex: "#E2E5EA")
        /// Very subtle divider.
        static let hairline = Color(hex: "#EEF0F3")

        // Primary / secondary text (on light canvas or white cards)
        static let textPrimary = Color(hex: "#1D2637")
        static let textSecondary = Color(hex: "#6B7484")
        static let textMuted = Color(hex: "#9AA3B2")

        // Sidebar text hierarchy (on navy)
        static let sidebarText = Color(hex: "#C7CEDC")
        static let sidebarMuted = Color(hex: "#8E99AD")
        static let sidebarDark = Color(hex: "#5D6B84")
        /// Active nav item background (brass tint on navy).
        static let sidebarActiveBg = Color(hex: "#D4AF37").opacity(0.12)
        /// Active nav item text / accent.
        static let sidebarActiveText = Color(hex: "#E9D48A")

        // Semantic
        static let success = Color(hex: "#4FBF8B")
        static let danger = Color(hex: "#C2503E")
        static let warning = Color(hex: "#C77E28")
        static let info = Color(hex: "#5B8DB8")
        static let infoLight = Color(hex: "#8FB6D9")

        // Tag / chip backgrounds (on surface)
        static let tagBg = Color(hex: "#E8ECF3")
        static let tagText = Color(hex: "#142138")

        // Focus block (calendar) — subtle diagonal hatch
        static let focusBg = Color(hex: "#F7F0DC")
        static let focusBorder = Color(hex: "#DFCE9A")
        static let focusText = Color(hex: "#8A742C")

        // Won deal card
        static let wonBg = Color(hex: "#F7F9F8")
        static let wonBorder = Color(hex: "#DCE9E1")
        static let wonText = Color(hex: "#3E6B52")
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
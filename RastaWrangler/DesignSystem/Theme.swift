import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Central design tokens for RastaWrangler. Keeping spacing, radii, colors and
/// typography in one place is what makes the app feel consistent across
/// iPhone, iPad and Mac.
enum Theme {

    // MARK: Palette
    // A warm, confident palette with a subtle reggae-inspired accent trio used
    // sparingly for highlights and the brand mark.
    enum Palette {
        static let green = Color(hex: "#1DB954")
        static let gold = Color(hex: "#F5B301")
        static let red = Color(hex: "#E23D3D")

        /// Primary brand accent used for interactive elements.
        static let accent = Color(hex: "#1DB954")
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
        static let lg: CGFloat = 16
        static let xl: CGFloat = 22
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

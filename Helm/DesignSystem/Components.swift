import SwiftUI

// MARK: - Card container

/// A rounded, subtly shadowed surface used for cards throughout the app.
struct Card<Content: View>: View {
    var padding: CGFloat = Theme.Spacing.lg
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background(
                Theme.Palette.surface,
                in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                    .strokeBorder(Theme.Palette.border, lineWidth: 1)
            )
            .shadow(color: Theme.Palette.cardShadow, radius: 3, x: 0, y: 1)
    }
}

// MARK: - Tag / chip

struct Chip: View {
    let text: String
    var systemImage: String? = nil
    var color: Color = .secondary

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption2)
            }
            Text(text)
                .font(.caption.weight(.medium))
        }
        .foregroundStyle(color)
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xs)
        .background(color.opacity(0.12), in: Capsule())
    }
}

// MARK: - Helm source badge

/// Small badge like "GOOGLE", "APPLE", "REMINDERS", "HELM" used to tag task/event origins.
struct SourceBadge: View {
    let text: String
    var color: Color = Theme.Palette.textMuted

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 8.5, weight: .bold, design: .default))
            .kerning(0.5)
            .foregroundStyle(color)
    }
}

// MARK: - Avatar

struct AvatarView: View {
    let initials: String
    let colorHex: String
    var size: CGFloat = 36

    var body: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [Color(hex: colorHex), Color(hex: colorHex).opacity(0.7)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: size, height: size)
            .overlay(
                Text(initials.isEmpty ? "?" : initials)
                    .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            )
    }
}

// MARK: - Section header

struct SectionHeader: View {
    let title: String
    var systemImage: String? = nil
    var action: (() -> Void)? = nil
    var actionLabel: String = "Add"

    var body: some View {
        HStack {
            Label {
                Text(title)
                    .font(.headline)
            } icon: {
                if let systemImage {
                    Image(systemName: systemImage)
                        .foregroundStyle(Theme.Palette.brass)
                }
            }
            Spacer()
            if let action {
                Button(action: action) {
                    Label(actionLabel, systemImage: "plus")
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.borderless)
            }
        }
    }
}

// MARK: - Empty state

struct EmptyStateView: View {
    let title: String
    let message: String
    var systemImage: String = "tray"
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: systemImage)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Theme.Palette.brass.gradient)
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.Palette.textPrimary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.Palette.brass)
                    .padding(.top, Theme.Spacing.xs)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Theme.Spacing.xxl)
    }
}

// MARK: - Brand mark (compass rose)

/// The Helm compass rose wordmark — a minimalist compass rose + "HELM" in tight letter-spacing.
struct BrandMark: View {
    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            CompassRose()
                .frame(width: 22, height: 22)
            Text("HELM")
                .font(.system(size: 14, weight: .bold, design: .default))
                .kerning(3.5)
        }
    }
}

/// SVG-style compass rose icon matching the design's nautical identity.
struct CompassRose: View {
    var accentColor: Color = Theme.Palette.brass
    var bodyColor: Color = .white

    var body: some View {
        ZStack {
            // Outer ring
            Circle()
                .stroke(accentColor, lineWidth: 1.5)
            // Centre dot
            Circle()
                .fill(accentColor)
                .frame(width: 4.4, height: 4.4)
            // Cardinal points
            Path { path in
                // N
                path.move(to: CGPoint(x: 11, y: 1))
                path.addLine(to: CGPoint(x: 11, y: 5))
                // S
                path.move(to: CGPoint(x: 11, y: 17))
                path.addLine(to: CGPoint(x: 11, y: 21))
                // E
                path.move(to: CGPoint(x: 1, y: 11))
                path.addLine(to: CGPoint(x: 5, y: 11))
                // W
                path.move(to: CGPoint(x: 17, y: 11))
                path.addLine(to: CGPoint(x: 21, y: 11))
            }
            .stroke(accentColor, lineWidth: 1.5)

            // Intercardinal diagonals (shorter)
            Path { path in
                path.move(to: CGPoint(x: 4, y: 4))
                path.addLine(to: CGPoint(x: 6.8, y: 6.8))
                path.move(to: CGPoint(x: 18, y: 4))
                path.addLine(to: CGPoint(x: 15.2, y: 6.8))
                path.move(to: CGPoint(x: 4, y: 18))
                path.addLine(to: CGPoint(x: 6.8, y: 15.2))
                path.move(to: CGPoint(x: 18, y: 18))
                path.addLine(to: CGPoint(x: 15.2, y: 15.2))
            }
            .stroke(accentColor, lineWidth: 1.2)
        }
    }
}

// MARK: - Navigation item button

/// A styled button for use in the navy sidebar.
struct NavItem: View {
    let title: String
    let systemImage: String?
    var count: Int? = nil
    let isActive: Bool

    var body: some View {
        HStack(spacing: 10) {
            if isActive {
                Rectangle()
                    .fill(Theme.Palette.brass)
                    .frame(width: 3, height: 14)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
            } else {
                Spacer().frame(width: 3)
            }

            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 16)
            }

            Text(title.uppercased())
                .font(.system(size: 12, weight: isActive ? .bold : .regular))
                .kerning(0.08)

            if let count {
                Spacer()
                Text("\(count)")
                    .font(.system(size: 10.5, design: .monospaced))
            }
        }
        .foregroundStyle(isActive ? Theme.Palette.sidebarActiveText : Theme.Palette.sidebarText)
        .padding(.horizontal, 10)
        .padding(.vertical, isActive ? 8 : 8)
        .background(isActive ? Theme.Palette.sidebarActiveBg : Color.clear, in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Progress bar

/// A thin horizontal progress bar used in deal cards, headings, etc.
struct ProgressBar: View {
    let progress: CGFloat // 0.0 - 1.0
    var color: Color = Theme.Palette.brass
    var trackColor: Color = Theme.Palette.hairline

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(trackColor)
                    .frame(height: 4)
                Capsule()
                    .fill(color)
                    .frame(width: geo.size.width * min(max(progress, 0), 1), height: 4)
            }
        }
        .frame(height: 4)
    }
}

// MARK: - Pill button

struct PillButton: View {
    let title: String
    var color: Color = Theme.Palette.brass
    var textColor: Color = Theme.Palette.navy
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(textColor)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(color, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Pill button style (legacy)

struct PillButtonStyle: ButtonStyle {
    var tint: Color = Theme.Palette.brass
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.sm)
            .background(tint.opacity(configuration.isPressed ? 0.7 : 1), in: Capsule())
            .foregroundStyle(.white)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Full-screen loader

struct LoadingOverlay: View {
    var body: some View {
        ZStack {
            // `.primary` flips with the appearance, so the scrim stays visible
            // over both the light and dark canvas.
            Color.primary.opacity(0.03)
                .ignoresSafeArea()
            ProgressView()
                .scaleEffect(0.8)
                .tint(Theme.Palette.brass)
        }
    }
}

// MARK: - Inline monospace text

extension Text {
    func helmMonospace(_ size: CGFloat = 10.5) -> Text {
        self.font(.system(size: size, design: .monospaced))
    }
}

// MARK: - Monospaced label style

struct MonospacedLabel: ViewModifier {
    var size: CGFloat = 10.5
    func body(content: Content) -> some View {
        content
            .font(.system(size: size, design: .monospaced))
    }
}

extension View {
    func helmMonospaced(_ size: CGFloat = 10.5) -> some View {
        modifier(MonospacedLabel(size: size))
    }
}
import SwiftUI

// MARK: - Card container

/// A rounded, subtly shadowed surface used for cards throughout the app.
struct Card<Content: View>: View {
    var padding: CGFloat = Theme.Spacing.lg
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
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
                        .foregroundStyle(Theme.Palette.accent)
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
                .foregroundStyle(Theme.Palette.accent.gradient)
            Text(title)
                .font(.title3.weight(.semibold))
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.Palette.accent)
                    .padding(.top, Theme.Spacing.xs)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Theme.Spacing.xxl)
    }
}

// MARK: - Brand mark

/// The Helm wordmark with a subtle green/gold/red accent bar.
struct BrandMark: View {
    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            RoundedRectangle(cornerRadius: 2)
                .fill(
                    LinearGradient(
                        colors: [Theme.Palette.green, Theme.Palette.gold, Theme.Palette.red],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 5, height: 22)
            Text("Helm")
                .font(.headline.weight(.bold))
        }
    }
}

// MARK: - Pill button style

struct PillButtonStyle: ButtonStyle {
    var tint: Color = Theme.Palette.accent
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

import SwiftUI

/// A compact card representing a deal on the board, matching the Helm design.
/// Shows amount, contacts, days since last touch, and drift warnings.
struct DealCardView: View {
    let deal: Deal

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Title + amount row
            HStack(alignment: .top) {
                Text(deal.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(titleColor)
                    .lineLimit(2)
                Spacer()
                if let amount = deal.formattedAmount {
                    Text(amount)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(amountColor)
                }
            }

            // Next action / stage note
            if let actionText = nextActionText {
                Text(actionText)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(actionColor)
                    .lineLimit(1)
            }

            // Drift warning
            if isDrifting {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Theme.Palette.warning)
                        .frame(width: 6, height: 6)
                    Text("Drifting \u{2014} \(daysSinceTouch)d since last touch")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.Palette.warning)
                        .lineLimit(1)
                }
            }

            // Progress bar (for deals with some progress)
            if deal.status == .open, let progress = progressValue {
                ProgressBar(progress: progress, color: Theme.Palette.brass, trackColor: Theme.Palette.hairline)
                    .padding(.top, 4)
            }

            // Contact + days row
            HStack(spacing: 7) {
                if let primaryContact = deal.contacts.first {
                    AvatarView(
                        initials: primaryContact.initials,
                        colorHex: primaryContact.avatarColorHex,
                        size: 18
                    )
                    Text(primaryContact.name)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .lineLimit(1)
                } else if deal.status == .open {
                    Text("No contact yet")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.Palette.textMuted)
                }

                Spacer()

                Text(daysSinceTouchLabel)
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(daysSinceTouchColor)
            }
        }
        .padding(13)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 11))
        .overlay(
            RoundedRectangle(cornerRadius: 11)
                .strokeBorder(cardBorder, lineWidth: isDealWon ? 1 : (isHighlighted ? 1.5 : 1))
        )
        .shadow(color: isHighlighted ? Color.black.opacity(0.09) : Theme.Palette.navy.opacity(0.06),
                radius: isHighlighted ? 8 : 3, x: 0, y: isHighlighted ? 2 : 1)
        .contentShape(Rectangle())
    }

    // MARK: Helpers

    private var isDealWon: Bool { deal.status == .won }
    private var isDealLost: Bool { deal.status == .lost }

    private var daysSinceTouch: Int {
        Calendar.current.dateComponents([.day], from: deal.updatedAt, to: .now).day ?? 0
    }

    private var isDrifting: Bool {
        deal.status == .open && daysSinceTouch >= 5
    }

    private var isHighlighted: Bool {
        // Highlight deals needing attention (e.g., due today items)
        daysSinceTouch >= 7
    }

    private var daysSinceTouchLabel: String {
        if isDealWon { return "won" }
        if isDealLost { return "lost" }
        return "\(daysSinceTouch)d"
    }

    private var daysSinceTouchColor: Color {
        if isDealWon { return Theme.Palette.success }
        if isDealLost { return Theme.Palette.danger }
        if daysSinceTouch >= 7 { return Theme.Palette.warning }
        return Theme.Palette.textMuted
    }

    private var titleColor: Color {
        if isDealWon { return Theme.Palette.wonText }
        if isDealLost { return Theme.Palette.textMuted }
        return Theme.Palette.textPrimary
    }

    private var amountColor: Color {
        if isDealWon { return Theme.Palette.wonText }
        return Theme.Palette.textPrimary
    }

    private var cardBackground: Color {
        if isDealWon { return Theme.Palette.wonBg }
        return Theme.Palette.surface
    }

    private var cardBorder: Color {
        if isDealWon { return Theme.Palette.wonBorder }
        if isHighlighted { return Theme.Palette.brass }
        if isDealLost { return Theme.Palette.border }
        return Theme.Palette.border
    }

    private var nextActionText: String? {
        if isDealWon { return nil }
        if isDealLost { return nil }
        // Try to surface a relevant next action from activities
        if let nextActivity = deal.activities.first(where: { !$0.isCompleted && $0.kind == .task }) {
            return nextActivity.title
        }
        // Fallback: show time since creation
        let daysSinceCreated = Calendar.current.dateComponents([.day], from: deal.createdAt, to: .now).day ?? 0
        if daysSinceCreated < 7 {
            return nil // Too new, no action needed
        }
        return nil
    }

    private var actionColor: Color {
        if isDrifting { return Theme.Palette.warning }
        // Check for deadlines
        return Theme.Palette.textSecondary
    }

    /// Simple progress based on days since creation vs expected cycle
    private var progressValue: Double? {
        guard deal.amount != nil && deal.amount! > 0 && daysSinceTouch < 30 else { return nil }
        // Rough heuristic: deals progress ~7% per day of activity, capped at 0.9
        let raw = min(Double(daysSinceTouch) * 0.07, 0.9)
        return max(raw, 0.1) // at least some bar visible
    }
}

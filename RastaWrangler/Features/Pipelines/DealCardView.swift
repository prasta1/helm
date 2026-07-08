import SwiftUI

/// A compact card representing a deal on the board.
struct DealCardView: View {
    let deal: Deal

    var body: some View {
        Card(padding: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack(alignment: .top) {
                    Text(deal.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                    Spacer()
                    if deal.status != .open {
                        Image(systemName: deal.status == .won ? "checkmark.seal.fill" : "xmark.seal.fill")
                            .foregroundStyle(deal.status.tint)
                    }
                }

                if let amount = deal.formattedAmount {
                    Text(amount)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.Palette.accent)
                }

                if !deal.contacts.isEmpty {
                    HStack(spacing: -8) {
                        ForEach(deal.contacts.prefix(3)) { contact in
                            AvatarView(initials: contact.initials, colorHex: contact.avatarColorHex, size: 24)
                                .overlay(Circle().strokeBorder(Theme.cardBackground, lineWidth: 1.5))
                        }
                        if deal.contacts.count > 3 {
                            Text("+\(deal.contacts.count - 3)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .padding(.leading, Theme.Spacing.md)
                        }
                    }
                }

                let openTasks = deal.openTasks.count
                if openTasks > 0 {
                    Chip(text: "\(openTasks) task\(openTasks == 1 ? "" : "s")", systemImage: "checkmark.circle", color: .orange)
                }
            }
        }
        .contentShape(Rectangle())
    }
}

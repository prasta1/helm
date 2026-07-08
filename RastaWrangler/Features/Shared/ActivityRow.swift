import SwiftUI

/// A single row in an activity timeline.
struct ActivityRow: View {
    @Bindable var activity: Activity

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            if activity.kind == .task {
                Button {
                    activity.isCompleted.toggle()
                } label: {
                    Image(systemName: activity.isCompleted ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(activity.isCompleted ? Theme.Palette.green : .secondary)
                }
                .buttonStyle(.plain)
            } else {
                Image(systemName: activity.kind.systemImage)
                    .foregroundStyle(Theme.Palette.accent)
                    .frame(width: 20)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(activity.title.isEmpty ? activity.body : activity.title)
                    .font(.subheadline)
                    .strikethrough(activity.isCompleted)
                    .foregroundStyle(activity.isCompleted ? .secondary : .primary)
                if !activity.body.isEmpty && !activity.title.isEmpty {
                    Text(activity.body)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                HStack(spacing: Theme.Spacing.sm) {
                    Text(activity.date, format: .dateTime.month().day().hour().minute())
                    if activity.source == .ai {
                        Chip(text: "AI", systemImage: "sparkles", color: Theme.Palette.gold)
                    } else if activity.source == .granola {
                        Chip(text: "Granola", color: .purple)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}

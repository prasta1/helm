import SwiftUI

/// Lets the user choose which parsed Granola meetings to import. Already-imported
/// meetings (matched by external id) are pre-marked and skipped.
struct GranolaImportSheet: View {
    let candidates: [GranolaMeeting]
    let existingIDs: Set<String>
    let onImport: ([GranolaMeeting]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedIDs: Set<String> = []

    var body: some View {
        NavigationStack {
            List {
                ForEach(candidates) { meeting in
                    let alreadyImported = existingIDs.contains(meeting.id)
                    Button {
                        guard !alreadyImported else { return }
                        toggle(meeting.id)
                    } label: {
                        HStack(alignment: .top) {
                            Image(systemName: selectedIDs.contains(meeting.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(alreadyImported ? .secondary : Theme.Palette.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(meeting.title).foregroundStyle(.primary)
                                Text(meeting.date, format: .dateTime.month().day().year())
                                    .font(.caption).foregroundStyle(.secondary)
                                if !meeting.summaryMarkdown.isEmpty {
                                    Text(meeting.summaryMarkdown).font(.caption2).foregroundStyle(.tertiary).lineLimit(2)
                                }
                            }
                            Spacer()
                            if alreadyImported {
                                Text("Imported").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(alreadyImported)
                }
            }
            .navigationTitle("Import Meetings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import \(selectedIDs.count)") {
                        onImport(candidates.filter { selectedIDs.contains($0.id) })
                        dismiss()
                    }
                    .disabled(selectedIDs.isEmpty)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button("Select All New") {
                    selectedIDs = Set(candidates.map(\.id)).subtracting(existingIDs)
                }
                .buttonStyle(.bordered)
                .padding(.bottom, Theme.Spacing.sm)
            }
        }
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 520)
        #endif
    }

    private func toggle(_ id: String) {
        if selectedIDs.contains(id) { selectedIDs.remove(id) } else { selectedIDs.insert(id) }
    }
}

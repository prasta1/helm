import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// A reusable sheet that runs an async AI task and presents the result with
/// copy / save affordances. Used from deals, contacts and meetings.
struct AIResultSheet: View {
    let title: String
    let run: () async throws -> String
    /// When provided, shows a "Save as note" button that hands back the result.
    var onSave: ((String) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var text: String = ""
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                Group {
                    if isLoading {
                        VStack(spacing: Theme.Spacing.md) {
                            ProgressView()
                            Text("Thinking…").foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 200)
                    } else if let errorMessage {
                        EmptyStateView(
                            title: "Couldn't complete",
                            message: errorMessage,
                            systemImage: "exclamationmark.triangle"
                        )
                    } else {
                        Text(attributed)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                }
            }
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    if !isLoading, errorMessage == nil {
                        Button {
                            copyToClipboard(text)
                        } label: { Label("Copy", systemImage: "doc.on.doc") }

                        if let onSave {
                            Button {
                                onSave(text)
                                dismiss()
                            } label: { Label("Save as Note", systemImage: "tray.and.arrow.down") }
                        }
                    }
                }
            }
        }
        .task {
            do {
                text = try await run()
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 420)
        #endif
    }

    /// Best-effort markdown rendering; falls back to plain text.
    private var attributed: AttributedString {
        (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }

    private func copyToClipboard(_ string: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #else
        UIPasteboard.general.string = string
        #endif
    }
}

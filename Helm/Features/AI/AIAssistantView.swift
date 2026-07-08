import SwiftUI
import SwiftData

/// A lightweight chat with the configured LLM. Can optionally include a summary
/// of the user's pipelines as context.
struct AIAssistantView: View {
    @Environment(AppSettings.self) private var settings
    @Query(sort: \Pipeline.sortOrder) private var pipelines: [Pipeline]

    @State private var transcript: [ChatTurn] = []
    @State private var input = ""
    @State private var includeContext = true
    @State private var isSending = false

    var body: some View {
        VStack(spacing: 0) {
            if !settings.isLLMConfigured {
                EmptyStateView(
                    title: "Set Up AI",
                    message: "Choose a provider and add an API key in Settings to chat with your assistant.",
                    systemImage: "sparkles"
                )
            } else {
                transcriptView
                inputBar
            }
        }
        .navigationTitle("AI Assistant")
        .toolbar {
            ToolbarItem {
                Toggle(isOn: $includeContext) {
                    Label("Use CRM Context", systemImage: "brain")
                }
                .toggleStyle(.button)
            }
        }
    }

    private var transcriptView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    if transcript.isEmpty {
                        VStack(spacing: Theme.Spacing.md) {
                            Image(systemName: "sparkles")
                                .font(.largeTitle)
                                .foregroundStyle(Theme.Palette.gold.gradient)
                            Text("Ask about your pipelines, draft outreach, or plan your week.")
                                .font(.callout).foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, Theme.Spacing.xxl)
                    }
                    ForEach(transcript) { turn in
                        ChatBubble(turn: turn).id(turn.id)
                    }
                    if isSending {
                        HStack { ProgressView(); Text("Thinking…").foregroundStyle(.secondary) }
                    }
                }
                .padding()
            }
            .onChange(of: transcript.count) {
                if let last = transcript.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
            }
        }
    }

    private var inputBar: some View {
        HStack(spacing: Theme.Spacing.md) {
            TextField("Message…", text: $input, axis: .vertical)
                .lineLimit(1...5)
                .textFieldStyle(.plain)
                .padding(Theme.Spacing.md)
                .background(Theme.subtleFill, in: RoundedRectangle(cornerRadius: Theme.Radius.lg))
                .onSubmit(send)

            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title)
                    .foregroundStyle(Theme.Palette.accent)
            }
            .buttonStyle(.plain)
            .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty || isSending)
        }
        .padding()
        .background(.bar)
    }

    // MARK: Send

    private func send() {
        let question = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isSending else { return }
        input = ""
        transcript.append(ChatTurn(role: .user, text: question))
        isSending = true

        let assistant = AIAssistant(manager: LLMManager(config: settings.activeLLMConfig))
        let context = includeContext ? pipelineContext : nil

        Task {
            do {
                let reply = try await assistant.ask(question, context: context)
                transcript.append(ChatTurn(role: .assistant, text: reply))
            } catch {
                transcript.append(ChatTurn(role: .assistant, text: "⚠️ \(error.localizedDescription)"))
            }
            isSending = false
        }
    }

    private var pipelineContext: String {
        pipelines.map { pipeline in
            let deals = pipeline.deals.filter { $0.status == .open }
            let byStage = Dictionary(grouping: deals) { $0.stage?.name ?? "—" }
            let stageLines = byStage.map { "  \($0.key): \($0.value.map(\.title).joined(separator: ", "))" }.joined(separator: "\n")
            return "Pipeline \"\(pipeline.name)\" (\(deals.count) open):\n\(stageLines)"
        }.joined(separator: "\n\n")
    }
}

struct ChatTurn: Identifiable {
    enum Role { case user, assistant }
    let id = UUID()
    let role: Role
    let text: String
}

private struct ChatBubble: View {
    let turn: ChatTurn

    var body: some View {
        HStack {
            if turn.role == .user { Spacer(minLength: 40) }
            VStack(alignment: turn.role == .user ? .trailing : .leading) {
                Text(attributed)
                    .textSelection(.enabled)
                    .padding(Theme.Spacing.md)
                    .background(
                        turn.role == .user ? AnyShapeStyle(Theme.Palette.accent) : AnyShapeStyle(Theme.cardBackground),
                        in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                    )
                    .foregroundStyle(turn.role == .user ? .white : .primary)
            }
            if turn.role == .assistant { Spacer(minLength: 40) }
        }
    }

    private var attributed: AttributedString {
        (try? AttributedString(markdown: turn.text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(turn.text)
    }
}

import SwiftUI
import SwiftData

/// Ask Helm — the AI chat that reads your day and acts with your OK.
/// Shows a centered conversation, action suggestions, and a context sidebar.
struct AIAssistantView: View {
    @Environment(AppSettings.self) private var settings
    @Query(sort: \Pipeline.sortOrder) private var pipelines: [Pipeline]

    @State private var transcript: [ChatTurn] = []
    @State private var input = ""
    @State private var includeContext = true
    @State private var isSending = false

    // Context toggles
    @State private var contextCalendar = true
    @State private var contextCharts = true
    @State private var contextContacts = true
    @State private var contextGmail = false

    var body: some View {
        HStack(spacing: 0) {
            if !settings.isLLMConfigured {
                EmptyStateView(
                    title: "Set Up AI",
                    message: "Choose a provider and add an API key in Settings to chat with Helm.",
                    systemImage: "sparkles"
                )
                .frame(maxWidth: .infinity)
            } else {
                // Chat area
                chatArea

                // Right context sidebar
                contextSidebar
            }
        }
        .background(Theme.Palette.canvas)
        .navigationTitle("Ask Helm")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: Chat Area

    private var chatArea: some View {
        VStack(spacing: 0) {
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 18) {
                        // Timestamp header
                        Text(formattedTimestamp)
                            .font(.system(size: 10, design: .monospaced))
                            .kerning(1.0)
                            .foregroundStyle(Theme.Palette.textMuted)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 36)

                        if transcript.isEmpty {
                            // Empty state
                            VStack(spacing: 16) {
                                CompassRose(accentColor: Theme.Palette.brass, bodyColor: Theme.Palette.navy)
                                    .frame(width: 36, height: 36)

                                Text("Ask about your day, draft a note, or plan your week.")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Theme.Palette.textMuted)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                        }

                        ForEach(transcript) { turn in
                            ChatBubble(turn: turn).id(turn.id)
                        }

                        if isSending {
                            HStack(spacing: 10) {
                                CompassRose(accentColor: Theme.Palette.brass, bodyColor: Theme.Palette.navy)
                                    .frame(width: 26, height: 26)
                                ProgressView()
                                    .tint(Theme.Palette.brass)
                                Text("Thinking…")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.Palette.textMuted)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.horizontal, 44)
                    .frame(maxWidth: 780)
                    .frame(maxWidth: .infinity)
                }
                .onChange(of: transcript.count) {
                    if let last = transcript.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
            }

            // Input bar
            inputBar
                .padding(.horizontal, 44)
                .padding(.vertical, 16)
                .frame(maxWidth: 780)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
    }

    private var inputBar: some View {
        HStack(spacing: 12) {
            CompassRose(accentColor: Theme.Palette.brass, bodyColor: Theme.Palette.surface)
                .frame(width: 15, height: 15)

            TextField("Reply, or ask anything…", text: $input, axis: .vertical)
                .font(.system(size: 13))
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .onSubmit(send)

            Button(action: send) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Theme.Palette.brass)
                    .frame(width: 26, height: 26)
                    .overlay(
                        Image(systemName: "arrow.up")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Theme.Palette.navy)
                    )
            }
            .buttonStyle(.plain)
            .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty || isSending)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
        .background(
            Theme.Palette.navy,
            in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
        )
    }

    // MARK: Context sidebar

    private var contextSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Helm Can See
            VStack(alignment: .leading, spacing: 12) {
                Text("HELM CAN SEE")
                    .font(.system(size: 10, weight: .bold))
                    .kerning(1.6)
                    .foregroundStyle(Theme.Palette.textMuted)

                VStack(spacing: 2) {
                    contextToggle("Today & calendar", isOn: $contextCalendar)
                    contextToggle("Charts & deals", isOn: $contextCharts)
                    contextToggle("Contacts & notes", isOn: $contextContacts)
                    contextToggle("Gmail inbox", isOn: $contextGmail, muted: true)
                }

                Text("Helm reads to advise. It acts — send, move, book — only with your OK.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Palette.textMuted)
                    .lineSpacing(2)
                    .padding(.top, 4)
            }
            .padding(20)

            Divider()
                .padding(.horizontal, 20)

            // Ship's Log — derived from the current session's transcript
            VStack(alignment: .leading, spacing: 12) {
                Text("SHIP'S LOG")
                    .font(.system(size: 10, weight: .bold))
                    .kerning(1.6)
                    .foregroundStyle(Theme.Palette.textMuted)

                VStack(spacing: 10) {
                    if shipLogEntries.isEmpty {
                        Text("No history this session.")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.Palette.textMuted)
                    } else {
                        ForEach(shipLogEntries, id: \.self) { entry in
                            logEntry(entry)
                        }
                    }
                }
            }
            .padding(20)

            Spacer()

            // Try section
            VStack(alignment: .leading, spacing: 6) {
                Text("TRY")
                    .font(.system(size: 11, weight: .bold))
                    .kerning(0.8)
                    .foregroundStyle(Theme.Palette.focusText)

                Text("\"What's slipping this week?\"")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Palette.focusText.opacity(0.8))

                Text("\"Plot tomorrow like today.\"")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Palette.focusText.opacity(0.8))
            }
            .padding(14)
            .background(
                Theme.Palette.focusBg,
                in: RoundedRectangle(cornerRadius: 10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Theme.Palette.focusBorder, lineWidth: 1)
            )
            .padding(20)
        }
        .frame(width: 300)
        .background(Theme.Palette.surface)
        .overlay(Divider(), alignment: .leading)
    }

    private func contextToggle(_ title: String, isOn: Binding<Bool>, muted: Bool = false) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
                .font(.system(size: 12.5))
                .foregroundStyle(muted ? Theme.Palette.textMuted : Theme.Palette.textPrimary)
        }
        .toggleStyle(HelmToggleStyle())
        .padding(.vertical, 6)
    }

    private func logEntry(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(Theme.Palette.textPrimary.opacity(0.85))
            .lineSpacing(2)
    }

    /// Recent assistant turns from this session, formatted as log lines.
    private var shipLogEntries: [String] {
        transcript
            .filter { $0.role == .assistant }
            .suffix(3)
            .reversed()
            .map { turn in
                let preview = String(turn.text.prefix(48)).replacingOccurrences(of: "\n", with: " ")
                let truncated = turn.text.count > 48 ? "\(preview)…" : preview
                return "Today — \(truncated)"
            }
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
                transcript.append(ChatTurn(role: .assistant, text: "\u{26A0}\u{FE0F} \(error.localizedDescription)"))
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

    private var formattedTimestamp: String {
        let df = DateFormatter()
        df.dateFormat = "EEEE · HH:mm"
        return df.string(from: .now).uppercased()
    }
}

// MARK: - Chat Bubble

private struct ChatBubble: View {
    let turn: ChatTurn

    var body: some View {
        if turn.role == .user {
            // User message — navy bubble right-aligned
            Text(turn.text)
                .font(.system(size: 13.5))
                .foregroundStyle(Theme.Palette.onNavy)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    Theme.Palette.navy,
                    in: UnevenRoundedRectangle(
                        topLeadingRadius: 14, bottomLeadingRadius: 14,
                        bottomTrailingRadius: 14, topTrailingRadius: 4
                    )
                )
                .frame(maxWidth: .infinity, alignment: .trailing)
        } else {
            // Helm message — white card left-aligned with compass avatar
            HStack(alignment: .top, spacing: 12) {
                CompassRose(accentColor: Theme.Palette.brass, bodyColor: Theme.Palette.navy)
                    .frame(width: 26, height: 26)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 10) {
                    Text(attributedMessage)
                        .font(.system(size: 13.5))
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .lineSpacing(4)
                        .textSelection(.enabled)

                    // Action chips (design shows suggested actions)
                    if let actions = suggestedActions {
                        HStack(spacing: 8) {
                            ForEach(actions, id: \.self) { action in
                                Text(action)
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundStyle(Theme.Palette.textPrimary)
                                    .padding(.horizontal, 11)
                                    .padding(.vertical, 5)
                                    .background(Theme.Palette.canvas, in: RoundedRectangle(cornerRadius: 7))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 7)
                                            .strokeBorder(Theme.Palette.border, lineWidth: 1)
                                    )
                            }
                        }
                    }
                }
                .padding(16)
                .background(
                    Theme.Palette.surface,
                    in: UnevenRoundedRectangle(
                        topLeadingRadius: 4, bottomLeadingRadius: 14,
                        bottomTrailingRadius: 14, topTrailingRadius: 14
                    )
                )
                .overlay(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 4, bottomLeadingRadius: 14,
                        bottomTrailingRadius: 14, topTrailingRadius: 14
                    )
                    .strokeBorder(Theme.Palette.border, lineWidth: 1)
                )
                .shadow(color: Theme.Palette.navy.opacity(0.06), radius: 3, x: 0, y: 1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var attributedMessage: AttributedString {
        (try? AttributedString(markdown: turn.text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(turn.text)
    }

    /// Extract suggested actions from the message — looks for quoted action items
    private var suggestedActions: [String]? {
        // Only show action suggestions for assistant responses
        guard turn.role == .assistant else { return nil }
        // Parse out any quoted actions from the response
        let pattern = try? NSRegularExpression(pattern: "\"([^\"]{4,30})\"")
        let nsRange = NSRange(turn.text.startIndex..., in: turn.text)
        let matches = pattern?.matches(in: turn.text, range: nsRange) ?? []
        let actions = matches.prefix(3).compactMap { match -> String? in
            guard let range = Range(match.range(at: 1), in: turn.text) else { return nil }
            return String(turn.text[range])
        }
        return actions.isEmpty ? nil : actions
    }
}

// MARK: - Chat turn model

struct ChatTurn: Identifiable {
    enum Role { case user, assistant }
    let id = UUID()
    let role: Role
    let text: String
}

// MARK: - Helm Toggle Style

private struct HelmToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 10) {
            // The knob is inset with padding rather than an offset, so it can
            // never travel outside the track (offset + edge alignment pushed
            // it over the label).
            RoundedRectangle(cornerRadius: 9)
                .fill(configuration.isOn
                      ? Color.dynamic(light: "#142138", dark: "#3D4E73")
                      : Theme.Palette.tagBg)
                .frame(width: 28, height: 16)
                .overlay(
                    Circle()
                        .fill(configuration.isOn ? Theme.Palette.brass : Color.white)
                        .frame(width: 12, height: 12)
                        .padding(2),
                    alignment: configuration.isOn ? .trailing : .leading
                )
            configuration.label
            Spacer(minLength: 0)
        }
        // The whole row toggles, not just the 28pt track.
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeOut(duration: 0.15)) { configuration.isOn.toggle() }
        }
        // VoiceOver should see a real switch, not a shape and a label.
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
        }
    }
}

#Preview {
    NavigationStack {
        AIAssistantView()
            .environment(AppSettings())
            .modelContainer(PersistenceController.makeInMemoryContainer())
    }
}

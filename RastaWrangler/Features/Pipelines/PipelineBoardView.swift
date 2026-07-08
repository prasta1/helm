import SwiftUI
import SwiftData

/// A kanban board for a pipeline: horizontally scrolling stage columns with
/// draggable deal cards. Matches the Helm design with drift warnings and metrics.
struct PipelineBoardView: View {
    @Bindable var pipeline: Pipeline
    @Environment(\.modelContext) private var modelContext

    @State private var selectedDeal: Deal?
    @State private var showingPipelineEditor = false
    @State private var draggingDealID: UUID?

    private let columnWidth: CGFloat = 280

    var body: some View {
        VStack(spacing: 0) {
            // Metrics header
            metricsBar

            // Kanban columns
            ScrollView([.horizontal]) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(pipeline.orderedStages) { stage in
                        stageColumn(stage)
                            .frame(width: columnWidth)
                    }
                }
                .padding(.horizontal, 44)
                .padding(.vertical, 22)
            }

            // Ask bar
            askBar
                .padding(.horizontal, 44)
                .padding(.bottom, 20)
        }
        .background(Theme.Palette.canvas)
        .navigationTitle(pipeline.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .safeAreaInset(edge: .top, spacing: 0) { EmptyView() }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    addDeal(to: pipeline.orderedStages.first)
                } label: {
                    Label("New Deal", systemImage: "plus")
                }
                Menu {
                    Button("Edit Pipeline…", systemImage: "slider.horizontal.3") { showingPipelineEditor = true }
                } label: {
                    Label("Options", systemImage: "ellipsis.circle")
                }
            }
        }
        .sheet(item: $selectedDeal) { deal in
            NavigationStack { DealDetailView(deal: deal) }
        }
        .sheet(isPresented: $showingPipelineEditor) {
            PipelineEditorView(pipeline: pipeline)
        }
    }

    // MARK: Metrics bar

    private var metricsBar: some View {
        HStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(pipeline.name)
                    .font(.system(size: 25, weight: .bold))
                    .kerning(-0.2)
                    .foregroundStyle(Theme.Palette.textPrimary)

                // "switch chart" dropdown placeholder
                Text("switch chart \u{25BE}")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: 7))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .strokeBorder(Theme.Palette.border, lineWidth: 1)
                    )
            }

            Spacer()

            HStack(spacing: 28) {
                metricView(title: "WEIGHTED", value: pipeline.openValue.formatted(.currency(code: "USD").precision(.fractionLength(0))))
                metricView(title: "OPEN", value: "\(pipeline.deals.filter { $0.status == .open }.count)")
                metricView(title: "DRIFTING", value: "\(driftingCount)", color: Theme.Palette.warning)
            }

            PillButton(title: "+ New deal", action: { addDeal(to: pipeline.orderedStages.first) })
                .padding(.leading, 20)
        }
        .padding(.horizontal, 44)
        .padding(.top, 28)
        .padding(.bottom, 16)
    }

    private func metricView(title: String, value: String, color: Color = Theme.Palette.textMuted) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .kerning(1.4)
                .foregroundStyle(Theme.Palette.textMuted)
            Text(value)
                .font(.system(size: 14, design: .monospaced))
                .foregroundStyle(color == Theme.Palette.textMuted ? Theme.Palette.textPrimary : color)
        }
    }

    private var driftingCount: Int {
        let daysThreshold = 5
        return pipeline.deals.filter { deal in
            guard deal.status == .open else { return false }
            let days = Calendar.current.dateComponents([.day], from: deal.updatedAt, to: .now).day ?? 0
            return days >= daysThreshold
        }.count
    }

    // MARK: Stage column

    private func stageColumn(_ stage: Stage) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Stage header
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(hex: stage.colorHex))
                    .frame(width: 8, height: 8)

                Text(stage.name.uppercased())
                    .font(.system(size: 10.5, weight: .bold))
                    .kerning(1.4)
                    .foregroundStyle(Theme.Palette.textSecondary)

                Spacer()

                Text("\(stage.deals.count)")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Theme.Palette.textMuted)

                let stageValue = stage.deals.reduce(0.0) { $0 + ($1.amount ?? 0) }
                if stageValue > 0 {
                    Text(stageValue.formatted(.currency(code: "USD").precision(.fractionLength(0))))
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 4)
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(hex: stage.colorHex))
                    .frame(height: 3),
                alignment: .top
            )

            // Cards
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(stage.orderedDeals) { deal in
                        DealCardView(deal: deal)
                            .onTapGesture { selectedDeal = deal }
                            .draggable(DealTransfer(id: deal.id)) {
                                DealCardView(deal: deal)
                                    .frame(width: columnWidth - 8)
                                    .opacity(0.9)
                            }
                    }

                    // Add new deal placeholder
                    Button {
                        addDeal(to: stage)
                    } label: {
                        HStack {
                            Spacer()
                            Text("+ New deal")
                                .font(.system(size: 11.5))
                                .foregroundStyle(Theme.Palette.textMuted)
                            Spacer()
                        }
                        .padding(.vertical, 10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 11)
                                .strokeBorder(Theme.Palette.border, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        )
                    }
                    .buttonStyle(.plain)

                    if stage.deals.isEmpty {
                        Text("Drop deals here")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Theme.Spacing.xl)
                    }
                }
                .padding(.bottom, Theme.Spacing.xl)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(Theme.Palette.surface.opacity(0.5), in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .strokeBorder(Theme.Palette.border, lineWidth: 1)
        )
        .dropDestination(for: DealTransfer.self) { items, _ in
            guard let transfer = items.first else { return false }
            return move(dealID: transfer.id, to: stage)
        }
    }

    // MARK: Ask bar

    private var askBar: some View {
        HStack(spacing: 12) {
            CompassRose(accentColor: Theme.Palette.brass, bodyColor: Theme.Palette.surface)
                .frame(width: 15, height: 15)

            Text("Ask Helm — “which deals are drifting?”, “draft a nudge for Northwind”…")
                .font(.system(size: 13))
                .foregroundStyle(Theme.Palette.sidebarMuted)
                .lineLimit(1)

            Spacer()

            Text("\u{2318}J")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Theme.Palette.sidebarMuted)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(Theme.Palette.sidebarDark.opacity(0.5), lineWidth: 1)
                )
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(
            Theme.Palette.navy,
            in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
        )
    }

    // MARK: Actions

    private func addDeal(to stage: Stage?) {
        let deal = Deal(title: "New Deal", sortOrder: (stage?.deals.count ?? 0))
        deal.pipeline = pipeline
        deal.stage = stage
        modelContext.insert(deal)
        try? modelContext.save()
        selectedDeal = deal
    }

    private func move(dealID: UUID, to stage: Stage) -> Bool {
        guard let deal = pipeline.deals.first(where: { $0.id == dealID }) else { return false }
        guard deal.stage?.id != stage.id else { return false }
        deal.stage = stage
        deal.sortOrder = (stage.deals.map(\.sortOrder).max() ?? -1) + 1
        if stage.isWon { deal.status = .won; deal.closeDate = .now }
        else if stage.isLost { deal.status = .lost; deal.closeDate = .now }
        else { deal.status = .open }
        deal.touch()
        try? modelContext.save()
        return true
    }
}

#Preview {
    let container = PersistenceController.makeInMemoryContainer()
    let pipeline = try! container.mainContext.fetch(FetchDescriptor<Pipeline>()).first!
    return NavigationStack {
        PipelineBoardView(pipeline: pipeline)
    }
    .modelContainer(container)
    .environment(AppSettings())
}

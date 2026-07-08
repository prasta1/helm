import SwiftUI
import SwiftData

/// A kanban board for a pipeline: horizontally scrolling stage columns with
/// draggable deal cards. Adapts to Mac, iPad and iPhone widths.
struct PipelineBoardView: View {
    @Bindable var pipeline: Pipeline
    @Environment(\.modelContext) private var modelContext

    @State private var selectedDeal: Deal?
    @State private var newDealStage: Stage?
    @State private var showingPipelineEditor = false
    @State private var draggingDealID: UUID?

    private let columnWidth: CGFloat = 300

    var body: some View {
        ScrollView([.horizontal]) {
            HStack(alignment: .top, spacing: Theme.Spacing.lg) {
                ForEach(pipeline.orderedStages) { stage in
                    stageColumn(stage)
                        .frame(width: columnWidth)
                }
            }
            .padding(Theme.Spacing.lg)
        }
        .background(Theme.canvasBackground)
        .navigationTitle(pipeline.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .safeAreaInset(edge: .top, spacing: 0) { metricsBar }
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
        HStack(spacing: Theme.Spacing.xl) {
            metric(title: "Deals", value: "\(pipeline.deals.filter { $0.status == .open }.count)")
            metric(title: "Open Value", value: pipeline.openValue.formatted(.currency(code: "USD").precision(.fractionLength(0))))
            metric(title: "Stages", value: "\(pipeline.orderedStages.count)")
            Spacer()
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.sm)
        .background(.bar)
    }

    private func metric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(.headline)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: Stage column

    private func stageColumn(_ stage: Stage) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.sm) {
                Circle()
                    .fill(Color(hex: stage.colorHex))
                    .frame(width: 10, height: 10)
                Text(stage.name)
                    .font(.subheadline.weight(.semibold))
                Text("\(stage.deals.count)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .background(Theme.subtleFill, in: Capsule())
                Spacer()
                Button {
                    addDeal(to: stage)
                } label: {
                    Image(systemName: "plus")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }

            ScrollView {
                LazyVStack(spacing: Theme.Spacing.md) {
                    ForEach(stage.orderedDeals) { deal in
                        DealCardView(deal: deal)
                            .onTapGesture { selectedDeal = deal }
                            .draggable(DealTransfer(id: deal.id)) {
                                DealCardView(deal: deal)
                                    .frame(width: columnWidth - 40)
                                    .opacity(0.9)
                            }
                    }
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
        .padding(Theme.Spacing.md)
        .background(Theme.cardBackground.opacity(0.5), in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
        .dropDestination(for: DealTransfer.self) { items, _ in
            guard let transfer = items.first else { return false }
            return move(dealID: transfer.id, to: stage)
        }
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
        // Reflect a terminal stage in the deal's status.
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

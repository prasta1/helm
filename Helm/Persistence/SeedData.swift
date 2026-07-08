import Foundation
import SwiftData

/// Seeds the two starter pipelines the app ships with — **Job Search** and
/// **Peregrine Prospects** — plus a small amount of sample content for previews.
enum SeedData {

    /// Creates the default pipelines the first time the app runs (detected by an
    /// empty `Pipeline` table).
    static func seedIfNeeded(_ context: ModelContext, includeSampleContent: Bool = false) {
        let existing = (try? context.fetchCount(FetchDescriptor<Pipeline>())) ?? 0
        guard existing == 0 else { return }

        let jobSearch = makeJobSearchPipeline(sortOrder: 0)
        let prospects = makeProspectsPipeline(sortOrder: 1)
        context.insert(jobSearch)
        context.insert(prospects)

        seedDefaultCustomFields(context, jobSearch: jobSearch, prospects: prospects)

        if includeSampleContent {
            seedSampleContent(context, jobSearch: jobSearch, prospects: prospects)
        }

        try? context.save()
    }

    // MARK: Starter pipelines

    static func makeJobSearchPipeline(sortOrder: Int) -> Pipeline {
        let pipeline = Pipeline(
            name: "Job Search",
            kind: .jobSearch,
            colorHex: "#3B82F6",
            sortOrder: sortOrder
        )
        let stages = [
            ("Researching", "#6B7280", false, false),
            ("Applied", "#3B82F6", false, false),
            ("Phone Screen", "#8B5CF6", false, false),
            ("Interviewing", "#F59E0B", false, false),
            ("Offer", "#10B981", false, false),
            ("Accepted", "#1DB954", true, false),
            ("Passed", "#E23D3D", false, true),
        ]
        pipeline.stages = stages.enumerated().map { index, s in
            Stage(name: s.0, sortOrder: index, colorHex: s.1, isWon: s.2, isLost: s.3)
        }
        return pipeline
    }

    static func makeProspectsPipeline(sortOrder: Int) -> Pipeline {
        let pipeline = Pipeline(
            name: "Peregrine Prospects",
            kind: .prospects,
            colorHex: "#8B5CF6",
            sortOrder: sortOrder
        )
        let stages = [
            ("Lead", "#6B7280", false, false),
            ("Qualified", "#3B82F6", false, false),
            ("Discovery", "#8B5CF6", false, false),
            ("Proposal", "#F59E0B", false, false),
            ("Negotiation", "#F97316", false, false),
            ("Won", "#1DB954", true, false),
            ("Lost", "#E23D3D", false, true),
        ]
        pipeline.stages = stages.enumerated().map { index, s in
            Stage(name: s.0, sortOrder: index, colorHex: s.1, isWon: s.2, isLost: s.3)
        }
        return pipeline
    }

    // MARK: Default custom fields

    private static func seedDefaultCustomFields(_ context: ModelContext, jobSearch: Pipeline, prospects: Pipeline) {
        let fields = [
            CustomFieldDefinition(name: "Job Posting URL", type: .url, entity: .deal, sortOrder: 0, pipeline: jobSearch),
            CustomFieldDefinition(name: "Location", type: .text, entity: .deal, sortOrder: 1, pipeline: jobSearch),
            CustomFieldDefinition(name: "Remote", type: .boolean, entity: .deal, sortOrder: 2, pipeline: jobSearch),
            CustomFieldDefinition(name: "Referred By", type: .text, entity: .deal, sortOrder: 3, pipeline: jobSearch),
            CustomFieldDefinition(
                name: "Priority",
                type: .singleSelect,
                entity: .deal,
                options: ["High", "Medium", "Low"],
                sortOrder: 0,
                pipeline: prospects
            ),
            CustomFieldDefinition(name: "Website", type: .url, entity: .deal, sortOrder: 1, pipeline: prospects),
        ]
        fields.forEach(context.insert)
    }

    // MARK: Sample content (previews / demo)

    private static func seedSampleContent(_ context: ModelContext, jobSearch: Pipeline, prospects: Pipeline) {
        let alex = Contact(name: "Alex Rivera", email: "alex@acme.com", title: "Engineering Manager", company: "Acme Corp")
        let priya = Contact(name: "Priya Shah", email: "priya@peregrine.io", title: "Head of Ops", company: "Peregrine")
        context.insert(alex)
        context.insert(priya)

        let applied = jobSearch.orderedStages.first { $0.name == "Applied" }
        let interviewing = jobSearch.orderedStages.first { $0.name == "Interviewing" }

        let d1 = Deal(title: "Senior iOS Engineer — Acme", details: "Applied via referral.", amount: 195_000, status: .open, sortOrder: 0)
        d1.pipeline = jobSearch
        d1.stage = applied
        d1.contacts = [alex]

        let d2 = Deal(title: "Staff Engineer — Nimbus", details: "Onsite scheduled.", amount: 225_000, status: .open, sortOrder: 0)
        d2.pipeline = jobSearch
        d2.stage = interviewing
        context.insert(d1)
        context.insert(d2)

        let discovery = prospects.orderedStages.first { $0.name == "Discovery" }
        let p1 = Deal(title: "Peregrine — Q3 Engagement", details: "Scoping a data platform build.", amount: 60_000, status: .open, sortOrder: 0)
        p1.pipeline = prospects
        p1.stage = discovery
        p1.contacts = [priya]
        context.insert(p1)
    }
}

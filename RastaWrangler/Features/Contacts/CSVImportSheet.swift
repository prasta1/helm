import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Seeds the database from a CSV file — either people (contacts) or companies
/// (organizations). The user picks a file, reviews the parsed rows with
/// duplicates pre-marked, and imports the selection. Mirrors the Granola
/// import flow so both importers feel the same.
struct CSVImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var existingContacts: [Contact]
    @Query private var existingOrganizations: [Organization]

    /// Which entity type the CSV holds.
    enum Kind: String, CaseIterable {
        case contacts = "People"
        case companies = "Companies"
    }

    @State private var kind: Kind = .contacts
    @State private var showingFilePicker = false
    @State private var table: CSVImporter.Table?
    @State private var contactCandidates: [CSVImporter.ContactCandidate] = []
    @State private var companyCandidates: [CSVImporter.CompanyCandidate] = []
    @State private var selectedIDs: Set<UUID> = []
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if table == nil {
                    filePrompt
                } else {
                    previewList
                }
            }
            .navigationTitle("Import CSV")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import \(selectedIDs.count)") { runImport() }
                        .disabled(selectedIDs.isEmpty)
                }
            }
        }
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.commaSeparatedText, .tabSeparatedText, .plainText]
        ) { result in
            if case .success(let url) = result { load(url) }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 540)
        #endif
    }

    // MARK: File prompt (before a file is chosen)

    private var filePrompt: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Picker("Import", selection: $kind) {
                ForEach(Kind.allCases, id: \.self) { Text($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 280)

            Image(systemName: kind == .contacts ? "person.text.rectangle" : "building.2")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Theme.Palette.brass.gradient)

            Text(kind == .contacts ? "Import People from CSV" : "Import Companies from CSV")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.Palette.textPrimary)

            Text(columnHint)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)

            Button("Choose File…") { showingFilePicker = true }
                .buttonStyle(.borderedProminent)
                .tint(Theme.Palette.brass)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Theme.Spacing.xxl)
    }

    private var columnHint: String {
        switch kind {
        case .contacts:
            "Needs a Name column (or First + Last Name). Email, Phone, Title, Company, and Notes are picked up when present — contacts with a Company are linked to it automatically."
        case .companies:
            "Needs a Name column. Domain (or Website) and Notes are picked up when present."
        }
    }

    // MARK: Preview (after parsing)

    private var previewList: some View {
        List {
            Section {
                switch kind {
                case .contacts:
                    ForEach(contactCandidates) { candidate in
                        candidateRow(
                            id: candidate.id,
                            title: candidate.name,
                            subtitle: [candidate.title, candidate.company, candidate.email]
                                .filter { !$0.isEmpty }
                                .joined(separator: " · "),
                            isDuplicate: candidate.isDuplicate
                        )
                    }
                case .companies:
                    ForEach(companyCandidates) { candidate in
                        candidateRow(
                            id: candidate.id,
                            title: candidate.name,
                            subtitle: candidate.domain,
                            isDuplicate: candidate.isDuplicate
                        )
                    }
                }
            } header: {
                Text("\(newCandidateIDs.count) new · \(duplicateCount) already exist")
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button("Select All New") { selectedIDs = newCandidateIDs }
                    .buttonStyle(.bordered)
                Button("Choose Another File…") { showingFilePicker = true }
                    .buttonStyle(.borderless)
            }
            .padding(.bottom, Theme.Spacing.sm)
        }
    }

    private func candidateRow(id: UUID, title: String, subtitle: String, isDuplicate: Bool) -> some View {
        Button {
            guard !isDuplicate else { return }
            if selectedIDs.contains(id) { selectedIDs.remove(id) } else { selectedIDs.insert(id) }
        } label: {
            HStack(alignment: .top) {
                Image(systemName: selectedIDs.contains(id) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isDuplicate ? .secondary : Theme.Palette.brass)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(.primary)
                    if !subtitle.isEmpty {
                        Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer()
                if isDuplicate {
                    Text("Exists").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isDuplicate)
    }

    private var newCandidateIDs: Set<UUID> {
        switch kind {
        case .contacts: Set(contactCandidates.filter { !$0.isDuplicate }.map(\.id))
        case .companies: Set(companyCandidates.filter { !$0.isDuplicate }.map(\.id))
        }
    }

    private var duplicateCount: Int {
        switch kind {
        case .contacts: contactCandidates.filter(\.isDuplicate).count
        case .companies: companyCandidates.filter(\.isDuplicate).count
        }
    }

    // MARK: Actions

    /// Reads and parses the picked file, then maps it onto candidates for the
    /// current kind. New (non-duplicate) rows start selected.
    private func load(_ url: URL) {
        // Files picked via fileImporter live outside the sandbox; access must be
        // explicitly started (and stopped) or reading fails on device.
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        do {
            let table = try CSVImporter.loadTable(from: url)
            switch kind {
            case .contacts:
                contactCandidates = try CSVImporter.contactCandidates(from: table, existing: existingContacts)
            case .companies:
                companyCandidates = try CSVImporter.companyCandidates(from: table, existing: existingOrganizations)
            }
            self.table = table
            selectedIDs = newCandidateIDs
            errorMessage = nil
        } catch {
            self.table = nil
            errorMessage = error.localizedDescription
        }
    }

    private func runImport() {
        switch kind {
        case .contacts:
            let picked = contactCandidates.filter { selectedIDs.contains($0.id) }
            CSVImporter.importContacts(picked, organizations: existingOrganizations, context: modelContext)
        case .companies:
            let picked = companyCandidates.filter { selectedIDs.contains($0.id) }
            CSVImporter.importCompanies(picked, contacts: existingContacts, context: modelContext)
        }
        try? modelContext.save()
        dismiss()
    }
}

#Preview {
    CSVImportSheet()
        .modelContainer(PersistenceController.makeInMemoryContainer())
}

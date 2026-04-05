import SwiftUI
import WiredPartCore

/// Contractor detail page with contact info, qualifications, ratings (subcontractors only),
/// job history, and notes.
struct IOSContractorDetailPage: View {
    @EnvironmentObject private var appCore: AppCore
    let contractor: PeopleService.ContractorListItem

    // MARK: - State

    @State private var rating: PeopleService.ContractorRating?
    @State private var jobHistory: [PeopleService.ContractorJobSummary] = []
    @State private var notes: [PeopleService.ContractorNote] = []
    @State private var loadError: String?
    @State private var activeSheet: ActiveSheet?

    private enum ActiveSheet: Identifiable {
        case addNote
        case help

        var id: String {
            switch self {
            case .addNote: return "addNote"
            case .help: return "help"
            }
        }
    }

    /// Whether this is a subcontractor (gets ratings) vs GC (notes only).
    private var isSubcontractor: Bool {
        // If contact_type is "contractor" and not "gc", treat as subcontractor
        // ContractorListItem comes from entity_contacts where contact_type = 'contractor'
        true
    }

    var body: some View {
        Group {
            if let error = loadError {
                ErrorStateView(message: error) { loadData() }
            } else {
                detailList
            }
        }
        .navigationTitle("\(contractor.firstName) \(contractor.lastName)")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("Help")
            }
        }
        .refreshable { loadData() }
        .task { loadData() }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .addNote:
                AddContractorNoteSheet(contractorId: contractor.id) { loadData() }
                    .environmentObject(appCore)
            case .help:
                PageHelpSheet(
                    title: "Contractor Detail Help",
                    sections: [
                        ("What This Page Does", "View all details for a single contractor: contact info, qualifications, performance ratings, job history, and notes."),
                        ("Contact Info", "Shows the contractor's name, company, phone (tappable to call), and email (tappable to send). This is the primary point of contact for the sub-contractor."),
                        ("Qualifications", "Track important compliance documents like licenses, insurance certificates, and W-9 forms. Expiration dates are color-coded: green for valid, red for expired."),
                        ("Performance Rating", "Sub-contractors receive ratings for quality, on-time delivery, and reliability on a 1-5 star scale. The overall score is a combined average."),
                        ("Tips", "Pull down to refresh. Use the Add Note button in the Notes section to record interactions, issues, or general feedback about this contractor. Notes include timestamps and who wrote them.")
                    ]
                )
            }
        }
    }

    // MARK: - Detail List

    private var detailList: some View {
        List {
            // Contact Info
            Section {
                detailRow("Name", "\(contractor.firstName) \(contractor.lastName)")
                if let company = contractor.company, !company.isEmpty {
                    detailRow("Company", company)
                }
                if let phone = contractor.phone, !phone.isEmpty {
                    let digits = phone.filter(\.isNumber)
                    HStack {
                        Text("Phone").foregroundStyle(.secondary)
                        Spacer()
                        if let url = URL(string: "tel:\(digits)") {
                            Link(phone, destination: url)
                        } else {
                            Text(phone)
                        }
                    }
                }
                if let email = contractor.email, !email.isEmpty,
                   let encoded = email.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                   let url = URL(string: "mailto:\(encoded)") {
                    HStack {
                        Text("Email").foregroundStyle(.secondary)
                        Spacer()
                        Link(email, destination: url)
                    }
                }
            } header: {
                Text("Contact Info")
            }

            // Qualifications
            Section {
                QualificationRow(label: "License", value: nil, expiry: nil)
                QualificationRow(label: "Insurance", value: nil, expiry: nil)
                QualificationRow(label: "W-9", value: nil, expiry: nil)
            } header: {
                Text("Qualifications")
            } footer: {
                Text("Optional — track licenses and certifications for compliance")
            }

            // Rating (subcontractors only)
            if isSubcontractor {
                Section {
                    if let r = rating {
                        RatingRow(label: "Quality", value: r.qualityScore)
                        RatingRow(label: "On-Time", value: r.onTimeScore)
                        RatingRow(label: "Reliability", value: r.reliabilityScore)
                        HStack {
                            Text("Overall").font(.headline)
                            Spacer()
                            Text(String(format: "%.1f", r.overallScore))
                                .font(.headline)
                                .foregroundStyle(ratingColor(r.overallScore))
                            Image(systemName: "star.fill")
                                .foregroundStyle(ratingColor(r.overallScore))
                                .accessibilityHidden(true)
                        }
                    } else {
                        Text("No ratings yet")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                } header: {
                    Text("Performance Rating")
                }
            }

            // Job History
            Section {
                if jobHistory.isEmpty {
                    Text("No job history")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                } else {
                    ForEach(jobHistory) { job in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(job.name).font(.headline)
                                Text(job.status.capitalized)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let date = job.completedDate, !date.isEmpty {
                                Text(date)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } header: {
                Text("Job History (\(jobHistory.count))")
            }

            // Notes
            Section {
                if notes.isEmpty {
                    Text("No notes yet")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                } else {
                    ForEach(notes) { note in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(note.content)
                            HStack {
                                Text(note.createdBy)
                                Text("•")
                                Text(note.createdAt)
                            }
                            .font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                }
                Button { activeSheet = .addNote } label: {
                    Label("Add Note", systemImage: "square.and.pencil")
                }
            } header: {
                Text("Notes")
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Helpers

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }

    private func ratingColor(_ score: Double) -> Color {
        if score >= 4.0 { return .green }
        if score >= 3.0 { return .yellow }
        return .red
    }

    private func loadData() {
        guard let service = appCore.peopleService else {
            loadError = "Service unavailable"
            return
        }
        loadError = nil
        do {
            rating = try service.getContractorRating(contractorId: contractor.id)
            jobHistory = try service.getContractorJobHistory(contractorId: contractor.id)
            notes = try service.getContractorNotes(contractorId: contractor.id)
        } catch {
            loadError = userFriendlyError(error, context: "load contractor details")
        }
    }
}

// MARK: - Qualification Row

private struct QualificationRow: View {
    let label: String
    let value: String?
    let expiry: String?

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            if let val = value {
                Text(val).foregroundStyle(.secondary)
                if let exp = expiry, !exp.isEmpty {
                    Text(exp)
                        .font(.caption)
                        .foregroundStyle(isExpired(exp) ? .red : .green)
                }
            } else {
                Text("Not provided")
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func isExpired(_ dateStr: String) -> Bool {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: dateStr) else { return false }
        return d < Date()
    }
}

// MARK: - Rating Row

private struct RatingRow: View {
    let label: String
    let value: Double

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            ForEach(1...5, id: \.self) { star in
                Image(systemName: star <= Int(value.rounded()) ? "star.fill" : "star")
                    .foregroundStyle(star <= Int(value.rounded()) ? .yellow : .gray)
                    .font(.caption)
            }
            Text(String(format: "%.1f", value))
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Add Contractor Note Sheet

private struct AddContractorNoteSheet: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    let contractorId: Int64
    let onSave: () -> Void

    @State private var content = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Note") {
                    TextField("Enter note...", text: $content, axis: .vertical)
                        .lineLimit(3...8)
                }
                if let error = errorMessage {
                    Section {
                        Text(error).foregroundStyle(.red).font(.caption)
                    }
                }
            }
            .navigationTitle("Add Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(content.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        guard let service = appCore.peopleService else {
            errorMessage = "Service unavailable"
            return
        }
        do {
            let userId = appCore.currentUser?.id ?? 1
            try service.addContractorNote(
                contractorId: contractorId,
                content: content.trimmingCharacters(in: .whitespaces),
                createdBy: userId
            )
            dismiss()
            onSave()
        } catch {
            errorMessage = userFriendlyError(error, context: "load contractor")
        }
    }
}

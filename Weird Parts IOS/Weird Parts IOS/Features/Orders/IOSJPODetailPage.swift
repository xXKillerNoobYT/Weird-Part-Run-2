import SwiftUI
import WiredPartCore

/// JPO (Job Purchase Order) detail page.
///
/// Shows all JPO info including line items, approval status,
/// and actions to approve or generate a PO.
struct IOSJPODetailPage: View {
    @EnvironmentObject private var appCore: AppCore

    let jpoId: Int64

    @State private var jpo: OrdersService.JPODetail?
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var showAddLineItem = false
    @State private var actionError: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = loadError {
                ErrorStateView(message: error) { loadData() }
            } else if let jpo {
                jpoContent(jpo)
            }
        }
        .navigationTitle("JPO #\(jpoId)")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAddLineItem = true
                } label: {
                    Label("Add Item", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddLineItem) {
            AddJPOLineItemSheet(jpoId: jpoId, onSave: { loadData() })
                .environmentObject(appCore)
        }
        .alert("Error", isPresented: .constant(actionError != nil)) {
            Button("OK") { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
        .task { loadData() }
    }

    @ViewBuilder
    private func jpoContent(_ jpo: OrdersService.JPODetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack(spacing: 8) {
                    StatusBadge(text: jpo.status.capitalized, color: statusColor(jpo.status))
                    StatusBadge(text: jpo.priority.capitalized, color: priorityColor(jpo.priority))
                    Spacer()
                }

                // Info
                DetailField(label: "Job", value: jpo.jobName)
                DetailField(label: "Requested By", value: jpo.requestedByName)
                if let approved = jpo.approvedByName {
                    DetailField(label: "Approved By", value: approved)
                }
                if let notes = jpo.notes, !notes.isEmpty {
                    DetailField(label: "Notes", value: notes)
                }

                // Approve/Reject buttons for pending JPOs
                if jpo.status == "pending" {
                    HStack(spacing: 12) {
                        Button {
                            rejectJPO()
                        } label: {
                            Label("Reject", systemImage: "xmark.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)

                        Button {
                            approveJPO()
                        } label: {
                            Label("Approve", systemImage: "checkmark.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                    }
                    .padding(.vertical, 4)
                }

                // Line Items
                VStack(alignment: .leading, spacing: 8) {
                    Text("Line Items (\(jpo.lines.count))")
                        .font(.headline)

                    if jpo.lines.isEmpty {
                        Text("No line items")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(jpo.lines, id: \.id) { line in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(line.partName ?? "Unknown Part")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    Text("Qty: \(line.quantity)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if let price = line.unitPrice {
                                    Text(formatCurrency(price * Double(line.quantity)))
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                }
                            }
                            .padding(10)
                            .dsCard()
                        }
                    }
                }
            }
            .padding()
        }
    }

    // MARK: - Actions

    private func approveJPO() {
        guard let service = appCore.ordersService else { return }
        do {
            try service.updateJPOStatus(id: jpoId, status: "approved")
            loadData()
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func rejectJPO() {
        guard let service = appCore.ordersService else { return }
        do {
            try service.updateJPOStatus(id: jpoId, status: "rejected")
            loadData()
        } catch {
            actionError = error.localizedDescription
        }
    }

    // MARK: - Helpers

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "pending": .orange
        case "approved": .green
        case "rejected": .red
        case "ordered": .blue
        default: .secondary
        }
    }

    private func priorityColor(_ priority: String) -> Color {
        switch priority {
        case "urgent": .red
        case "high": .orange
        case "normal": .blue
        default: .secondary
        }
    }

    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSNumber(value: value)) ?? "$0.00"
    }

    private func loadData() {
        guard let service = appCore.ordersService else { return }
        isLoading = jpo == nil
        loadError = nil
        do {
            jpo = try service.getJPODetail(id: jpoId)
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - Detail Field

private struct DetailField: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body)
        }
    }
}

// MARK: - Add JPO Line Item Sheet

private struct AddJPOLineItemSheet: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    let jpoId: Int64
    let onSave: () -> Void

    @State private var searchText = ""
    @State private var searchResults: [Part] = []
    @State private var selectedPart: Part?
    @State private var quantity = 1
    @State private var notes = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Part") {
                    TextField("Search parts...", text: $searchText)
                        .onChange(of: searchText) { searchParts() }

                    if let part = selectedPart {
                        HStack {
                            Text(part.name)
                                .fontWeight(.medium)
                            Spacer()
                            Button("Change") { selectedPart = nil }
                                .font(.caption)
                        }
                        .padding(.vertical, 2)
                    } else if !searchResults.isEmpty {
                        ForEach(searchResults, id: \.id) { part in
                            Button {
                                selectedPart = part
                                searchText = part.name
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(part.name)
                                        .fontWeight(.medium)
                                    if let code = part.code, !code.isEmpty {
                                        Text(code)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                }

                Section("Details") {
                    Stepper("Quantity: \(quantity)", value: $quantity, in: 1...9999)
                    TextField("Notes (optional)", text: $notes)
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Add Line Item")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { save() }
                        .disabled(selectedPart == nil)
                }
            }
        }
    }

    private func searchParts() {
        guard let service = appCore.partsService, searchText.count >= 2 else {
            searchResults = []
            return
        }
        do {
            searchResults = try service.searchParts(query: searchText, limit: 10)
        } catch {
            searchResults = []
        }
    }

    private func save() {
        guard let service = appCore.ordersService,
              let part = selectedPart,
              let partId = part.id else {
            errorMessage = "Service unavailable or no part selected"
            return
        }
        do {
            try service.addJPOLineItem(
                jpoId: jpoId,
                partId: partId,
                quantity: quantity,
                notes: notes.isEmpty ? nil : notes
            )
            onSave()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

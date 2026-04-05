import SwiftUI
import WiredPartCore

/// Standalone "Parts-First Setup" flow — works without any floor plan.
///
/// Three simple steps:
/// 1. Parts List — browse catalog, see what needs counting
/// 2. Count Entry — enter physical count for each part
/// 3. Location Assignment — assign free-text location (or pick from floor plan if configured)
///
/// Accessible from Warehouse Dashboard banner and Settings → Warehouse Setup.
struct PartsFlowWizard: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    @State private var currentStep = 1
    @State private var parts: [Part] = []
    @State private var filteredParts: [Part] = []
    @State private var searchQuery = ""
    @State private var partCounts: [Int64: String] = [:]
    @State private var partLocations: [Int64: String] = [:]
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var savedCount = 0

    private let totalSteps = 3
    private let stepLabels = ["Parts List", "Count Entry", "Location Assignment"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                progressBar

                if isLoading {
                    ProgressView("Loading parts...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = loadError {
                    ErrorStateView(message: error) { loadParts() }
                } else {
                    switch currentStep {
                    case 1: step1PartsList
                    case 2: step2CountEntry
                    case 3: step3LocationAssignment
                    default: EmptyView()
                    }
                }

                navigationButtons
            }
            .navigationTitle(stepLabels[currentStep - 1])
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Save & Exit") {
                        saveAllProgress()
                        dismiss()
                    }
                }
            }
            .task { loadParts() }
        }
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                ForEach(1...totalSteps, id: \.self) { step in
                    Circle()
                        .fill(step == currentStep ? .blue :
                              step < currentStep ? .green :
                              .gray.opacity(0.3))
                        .frame(width: 10, height: 10)
                        .onTapGesture {
                            if step <= currentStep {
                                withAnimation { currentStep = step }
                            }
                        }
                }
            }

            HStack {
                Text("Step \(currentStep) of \(totalSteps)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(stepLabels[currentStep - 1])
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.blue)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground))
    }

    // MARK: - Step 1: Parts List

    private var step1PartsList: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "shippingbox.fill")
                    .font(.title)
                    .foregroundStyle(.teal)
                    .accessibilityHidden(true)
                Text("Review your parts catalog. These are the parts you'll count and assign locations to.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()

            // Search
            TextField("Search parts...", text: $searchQuery)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
                .onChange(of: searchQuery) { _, query in
                    filterParts(query)
                }

            // Parts list
            List {
                ForEach(filteredParts, id: \.id) { part in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(part.name)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            if let code = part.code {
                                Text(code)
                                    .font(.caption)
                                    .monospaced()
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if let partId = part.id {
                            if partCounts[partId] != nil || partLocations[partId] != nil {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)

            Text("\(filteredParts.count) parts in catalog")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)
        }
    }

    // MARK: - Step 2: Count Entry

    private var step2CountEntry: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Image(systemName: "number.circle.fill")
                    .font(.title)
                    .foregroundStyle(.purple)
                    .accessibilityHidden(true)
                Text("Enter the physical count for each part. Walk your shop and count what you have.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()

            let counted = partCounts.values.filter { !$0.isEmpty && Int($0) != nil }.count
            HStack {
                Text("\(counted) of \(parts.count) counted")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                ProgressView(value: Double(counted), total: Double(max(parts.count, 1)))
                    .frame(width: 100)
            }
            .padding(.horizontal)

            List {
                ForEach(parts, id: \.id) { part in
                    if let partId = part.id {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(part.name)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                if let code = part.code {
                                    Text(code)
                                        .font(.caption)
                                        .monospaced()
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()

                            TextField("Qty", text: Binding(
                                get: { partCounts[partId] ?? "" },
                                set: { partCounts[partId] = $0 }
                            ))
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.numberPad)
                            .frame(width: 80)

                            if let text = partCounts[partId],
                               !text.isEmpty, Int(text) != nil {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    // MARK: - Step 3: Location Assignment

    private var step3LocationAssignment: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Image(systemName: "mappin.circle.fill")
                    .font(.title)
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                Text("Assign a location for each part. Use free-text descriptions like \"Shelf A\", \"Back wall\", or \"Van #2\".")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()

            let assigned = partLocations.values.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
            HStack {
                Text("\(assigned) of \(parts.count) assigned")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                ProgressView(value: Double(assigned), total: Double(max(parts.count, 1)))
                    .frame(width: 100)
            }
            .padding(.horizontal)

            List {
                ForEach(parts, id: \.id) { part in
                    if let partId = part.id {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(part.name)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Spacer()
                                if let count = partCounts[partId], let qty = Int(count) {
                                    Text("×\(qty)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.secondary.opacity(0.1))
                                        .clipShape(Capsule())
                                }
                            }

                            TextField("Location (e.g., Shelf A, Back wall)", text: Binding(
                                get: { partLocations[partId] ?? "" },
                                set: { partLocations[partId] = $0 }
                            ))
                            .textFieldStyle(.roundedBorder)
                            .font(.subheadline)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .listStyle(.insetGrouped)

            // Save all button
            Button {
                saveAllProgress()
            } label: {
                Label(
                    savedCount > 0 ? "Saved \(savedCount) Parts" : "Save All Locations",
                    systemImage: savedCount > 0 ? "checkmark.circle.fill" : "square.and.arrow.down"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(savedCount > 0 ? .green : .blue)
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
    }

    // MARK: - Navigation Buttons

    private var navigationButtons: some View {
        HStack(spacing: 16) {
            if currentStep > 1 {
                Button {
                    withAnimation { currentStep -= 1 }
                } label: {
                    Label("Back", systemImage: "chevron.left")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            if currentStep < totalSteps {
                Button {
                    withAnimation { currentStep += 1 }
                } label: {
                    Label("Next", systemImage: "chevron.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button {
                    saveAllProgress()
                    dismiss()
                } label: {
                    Label("Finish", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
    }

    // MARK: - Data

    private func loadParts() {
        isLoading = true
        loadError = nil
        do {
            parts = try appCore.partsService?.listParts() ?? []
            filteredParts = parts

            // Restore saved progress from UserDefaults
            if let countData = UserDefaults.standard.data(forKey: "partsFlow_counts"),
               let saved = try? JSONDecoder().decode([String: String].self, from: countData) {
                for (key, value) in saved {
                    if let id = Int64(key) { partCounts[id] = value }
                }
            }
            if let locData = UserDefaults.standard.data(forKey: "partsFlow_locations"),
               let saved = try? JSONDecoder().decode([String: String].self, from: locData) {
                for (key, value) in saved {
                    if let id = Int64(key) { partLocations[id] = value }
                }
            }
        } catch {
            loadError = userFriendlyError(error, context: "load parts")
        }
        isLoading = false
    }

    private func filterParts(_ query: String) {
        if query.isEmpty {
            filteredParts = parts
        } else {
            let q = query.lowercased()
            filteredParts = parts.filter {
                $0.name.lowercased().contains(q) ||
                ($0.code?.lowercased().contains(q) ?? false)
            }
        }
    }

    private func saveAllProgress() {
        // Save counts and locations to UserDefaults for resume
        let countDict = partCounts.reduce(into: [String: String]()) { $0["\($1.key)"] = $1.value }
        let locDict = partLocations.reduce(into: [String: String]()) { $0["\($1.key)"] = $1.value }

        if let data = try? JSONEncoder().encode(countDict) {
            UserDefaults.standard.set(data, forKey: "partsFlow_counts")
        }
        if let data = try? JSONEncoder().encode(locDict) {
            UserDefaults.standard.set(data, forKey: "partsFlow_locations")
        }

        // Write counts to the database as stock adjustments
        savedCount = 0
        for part in parts {
            guard let partId = part.id else { continue }

            // Save location as a free-text note on the part
            if let location = partLocations[partId],
               !location.trimmingCharacters(in: .whitespaces).isEmpty {
                try? appCore.partsService?.updatePart(id: partId, notes: "Location: \(location)")
            }

            // Save stock count
            if let text = partCounts[partId],
               let qty = Int(text) {
                try? appCore.warehouseService?.adjustStock(partId: partId, quantity: qty, reason: "Parts Flow initial count")
                savedCount += 1
            }
        }
    }
}

import SwiftUI
import WiredPartCore

enum PartsFlowDraftStore {
    static let countsKey = "partsFlow_counts"
    static let locationsKey = "partsFlow_locations"

    static func scopedKey(_ baseKey: String, userId: Int64?) -> String {
        guard let userId else { return "\(baseKey)_anonymous" }
        return "\(baseKey)_user_\(userId)"
    }

    static func loadCounts(userId: Int64?) -> [Int64: String] {
        loadDictionary(forKey: scopedKey(countsKey, userId: userId))
    }

    static func loadLocations(userId: Int64?) -> [Int64: String] {
        loadDictionary(forKey: scopedKey(locationsKey, userId: userId))
    }

    static func save(counts: [Int64: String], locations: [Int64: String], userId: Int64?) {
        saveDictionary(counts, forKey: scopedKey(countsKey, userId: userId))
        saveDictionary(locations, forKey: scopedKey(locationsKey, userId: userId))
    }

    static func clear(userId: Int64?) {
        UserDefaults.standard.removeObject(forKey: scopedKey(countsKey, userId: userId))
        UserDefaults.standard.removeObject(forKey: scopedKey(locationsKey, userId: userId))
    }

    private static func loadDictionary(forKey key: String) -> [Int64: String] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let saved = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }

        return saved.reduce(into: [Int64: String]()) { result, pair in
            guard let id = Int64(pair.key) else { return }
            result[id] = pair.value
        }
    }

    private static func saveDictionary(_ dictionary: [Int64: String], forKey key: String) {
        let keyed = dictionary.reduce(into: [String: String]()) { result, pair in
            result["\(pair.key)"] = pair.value
        }
        if let data = try? JSONEncoder().encode(keyed) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

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
    @State private var parts: [PartsService.PartWithDetails] = []
    @State private var filteredParts: [PartsService.PartWithDetails] = []
    @State private var searchQuery = ""
    @State private var partCounts: [Int64: String] = [:]
    @State private var partLocations: [Int64: String] = [:]
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var isSaving = false
    @State private var savedCount = 0
    @State private var saveErrorMessage: String?
    @State private var validationMessage: String?
    @State private var saveSuccessMessage: String?

    private let totalSteps = 3
    private let stepLabels = ["Parts List", "Count Entry", "Location Assignment"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                progressBar

                if let message = saveSuccessMessage {
                    Label(message, systemImage: "checkmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.green)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color.green.opacity(0.12))
                        .accessibilityIdentifier("parts_flow_save_success_message")
                }

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
                        saveAllProgress(clearDraft: false, andDismiss: true)
                    }
                    .disabled(isSaving)
                }
            }
            .interactiveDismissDisabled(isSaving)
            .task { loadParts() }
            .alert("Save Error", isPresented: Binding(
                get: { saveErrorMessage != nil },
                set: { if !$0 { saveErrorMessage = nil } }
            )) {
                Button("OK") { saveErrorMessage = nil }
            } message: {
                if let msg = saveErrorMessage { Text(msg) }
            }
            .alert("Check Your Entries", isPresented: Binding(
                get: { validationMessage != nil },
                set: { if !$0 { validationMessage = nil } }
            )) {
                Button("OK") { validationMessage = nil }
            } message: {
                if let msg = validationMessage { Text(msg) }
            }
        }
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                ForEach(1...totalSteps, id: \.self) { step in
                    WarehouseWizardProgressStepButton(
                        step: step,
                        totalSteps: totalSteps,
                        title: stepLabels[step - 1],
                        isCurrent: step == currentStep,
                        isCompleted: step < currentStep,
                        isEnabled: step <= currentStep
                    ) {
                        withAnimation { currentStep = step }
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
                ForEach(filteredParts, id: \.part.id) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.part.name)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            if let code = item.part.code {
                                Text(code)
                                    .font(.caption)
                                    .monospaced()
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if let partId = item.part.id {
                            if partCounts[partId] != nil || partLocations[partId] != nil {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollDismissesKeyboard(.interactively)

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

            let counted = partCounts.values.filter { Self.validQuantity(from: $0) != nil }.count
            HStack {
                Text("\(counted) of \(parts.count) counted")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                ProgressView(value: Double(counted), total: Double(max(parts.count, 1)))
                    .frame(width: 100)
            }
            .padding(.horizontal)

            if let message = countEntryValidationSummary {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.top, 6)
                    .accessibilityIdentifier("parts_flow_count_validation_message")
            }

            List {
                ForEach(parts, id: \.part.id) { item in
                    if let partId = item.part.id {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.part.name)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                if let code = item.part.code {
                                    Text(code)
                                        .font(.caption)
                                        .monospaced()
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()

                            TextField("Qty", text: Binding(
                                get: { partCounts[partId] ?? "" },
                                set: { newValue in
                                    let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                                    if trimmed.isEmpty {
                                        partCounts.removeValue(forKey: partId)
                                    } else {
                                        partCounts[partId] = trimmed
                                    }
                                }
                            ))
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.numberPad)
                            .frame(width: 80)
                            .accessibilityIdentifier("parts_flow_qty_\(partId)")

                            if isInvalidQuantity(partCounts[partId]) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.red)
                                    .accessibilityLabel("Invalid quantity")
                            } else if let text = partCounts[partId],
                                      !text.isEmpty,
                                      Self.validQuantity(from: text) != nil {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollDismissesKeyboard(.interactively)
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
                ForEach(parts, id: \.part.id) { item in
                    if let partId = item.part.id {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(item.part.name)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Spacer()
                                if let qty = Self.validQuantity(from: partCounts[partId]) {
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
                                set: { newValue in
                                    let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                                    if trimmed.isEmpty {
                                        partLocations.removeValue(forKey: partId)
                                    } else {
                                        partLocations[partId] = trimmed
                                    }
                                }
                            ))
                            .textFieldStyle(.roundedBorder)
                            .font(.subheadline)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollDismissesKeyboard(.interactively)

            // Save all button
            Button {
                saveAllProgress(clearDraft: false, andDismiss: false)
            } label: {
                Label(
                    savedCount > 0 ? "Saved \(savedCount) Parts" : "Save All Locations",
                    systemImage: savedCount > 0 ? "checkmark.circle.fill" : "square.and.arrow.down"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(savedCount > 0 ? .green : .blue)
            .disabled(isSaving)
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
                .disabled(isSaving)
            }

            if currentStep < totalSteps {
                Button {
                    validateBeforeAdvancing()
                } label: {
                    Label("Next", systemImage: "chevron.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSaving)
            } else {
                Button {
                    saveAllProgress(clearDraft: true, andDismiss: true)
                } label: {
                    Label("Finish", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(isSaving)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
    }

    // MARK: - Data

    private func loadParts() {
        isLoading = true
        loadError = nil
        let userId = appCore.currentUser?.id
        partCounts = PartsFlowDraftStore.loadCounts(userId: userId)
        partLocations = PartsFlowDraftStore.loadLocations(userId: userId)

        guard let partsService = appCore.partsService else {
            parts = []
            filteredParts = []
            loadError = "Parts service unavailable. Your saved draft is still on this device."
            isLoading = false
            return
        }

        do {
            parts = try partsService.listParts()
            filterParts(searchQuery)
        } catch {
            parts = []
            filteredParts = []
            loadError = "\(userFriendlyError(error, context: "load parts")) Your saved draft is still on this device."
        }
        isLoading = false
    }

    private func filterParts(_ query: String) {
        if query.isEmpty {
            filteredParts = parts
        } else {
            let q = query.lowercased()
            filteredParts = parts.filter {
                $0.part.name.lowercased().contains(q) ||
                ($0.part.code?.lowercased().contains(q) ?? false)
            }
        }
    }

    private var invalidQuantityEntries: [String] {
        parts.compactMap { item in
            guard let partId = item.part.id, isInvalidQuantity(partCounts[partId]) else { return nil }
            return item.part.name
        }
    }

    private var countEntryValidationSummary: String? {
        let invalidCount = invalidQuantityEntries.count
        guard invalidCount > 0 else { return nil }
        return "\(invalidCount) quantity \(invalidCount == 1 ? "entry" : "entries") must be a whole number greater than zero."
    }

    private var saveableEntryCount: Int {
        parts.reduce(0) { total, item in
            guard let partId = item.part.id else { return total }
            let hasValidCount = Self.validQuantity(from: partCounts[partId]) != nil
            let hasLocation = !(partLocations[partId]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            return total + ((hasValidCount || hasLocation) ? 1 : 0)
        }
    }

    private func isInvalidQuantity(_ text: String?) -> Bool {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return Self.validQuantity(from: text) == nil
    }

    nonisolated private static func validQuantity(from text: String?) -> Int? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let qty = Int(trimmed), qty > 0 else { return nil }
        return qty
    }

    private func validateBeforeAdvancing() {
        // Always allow Step 1 to open Count Entry so invalid restored drafts can be fixed there.
        guard currentStep == 2 else {
            withAnimation { currentStep += 1 }
            return
        }
        guard invalidQuantityEntries.isEmpty else {
            validationMessage = countEntryValidationSummary
            return
        }
        withAnimation { currentStep += 1 }
    }

    private func validateBeforeSaving() -> Bool {
        guard invalidQuantityEntries.isEmpty else {
            validationMessage = countEntryValidationSummary
            return false
        }
        guard saveableEntryCount > 0 else {
            validationMessage = "Enter at least one positive count or non-empty location before saving the parts flow."
            return false
        }
        return true
    }

    private func saveAllProgress(clearDraft: Bool, andDismiss: Bool) {
        guard !isSaving else { return }
        saveSuccessMessage = nil
        saveErrorMessage = nil
        validationMessage = nil

        let userId = appCore.currentUser?.id
        PartsFlowDraftStore.save(counts: partCounts, locations: partLocations, userId: userId)

        guard validateBeforeSaving() else { return }
        isSaving = true

        guard let service = appCore.partsService else {
            isSaving = false
            saveErrorMessage = "Parts service unavailable. Your draft is still saved on this device."
            return
        }

        let snapshot = parts
        let counts = partCounts
        let locations = partLocations

        // DB loop runs in a detached task so synchronous SQLite writes do not block SwiftUI rendering.
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                var savedEntries = 0
                var failedParts: [String] = []
                for item in snapshot {
                    guard let partId = item.part.id else { continue }
                    var notesParts: [String] = []
                    if let location = locations[partId]?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !location.isEmpty {
                        notesParts.append("Location: \(location)")
                    }
                    if let qty = Self.validQuantity(from: counts[partId]) {
                        notesParts.append("Initial count: \(qty)")
                    }
                    if !notesParts.isEmpty {
                        let combined = notesParts.joined(separator: " | ")
                        do {
                            try service.updatePart(id: partId, notes: combined)
                            savedEntries += 1
                        } catch {
                            failedParts.append(item.part.name)
                        }
                    }
                }
                return (savedEntries: savedEntries, failedParts: failedParts)
            }.value

            savedCount = result.savedEntries
            if !result.failedParts.isEmpty {
                PartsFlowDraftStore.save(counts: counts, locations: locations, userId: userId)
                let preview = result.failedParts.prefix(3).joined(separator: ", ")
                let suffix = result.failedParts.count > 3 ? " and \(result.failedParts.count - 3) more" : ""
                saveErrorMessage = "Failed to save \(result.failedParts.count) part(s): \(preview)\(suffix). Your draft is still saved on this device."
            } else if clearDraft {
                PartsFlowDraftStore.clear(userId: userId)
            }
            isSaving = false
            if saveErrorMessage == nil {
                saveSuccessMessage = "Saved \(result.savedEntries) \(result.savedEntries == 1 ? "part" : "parts")."
            }
            if andDismiss && saveErrorMessage == nil {
                try? await Task.sleep(nanoseconds: 500_000_000)
                dismiss()
            }
        }
    }
}

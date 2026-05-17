import SwiftUI
import WiredPartCore

/// Operator-facing queue for independent warehouse audit counts.
///
/// The page intentionally hides the system expected quantity while an operator
/// submits a count so the verification remains unbiased.
struct IOSMyVerificationsPage: View {
    private static let duplicateSubmitMessage = "You've already submitted a count for this part. Each counter can submit once."

    @EnvironmentObject private var appCore: AppCore

    @State private var rows: [VerificationRow] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var selectedRow: VerificationRow?
    @State private var actionError: String?

    var body: some View {
        VStack(spacing: 0) {
            OnboardingBanner(pageId: "warehouse-my-verifications")

            content
        }
        .navigationTitle("My Verifications")
        .accessibilityIdentifier("IOSMyVerificationsPage")
        .refreshable { loadData() }
        .sheet(item: $selectedRow) { row in
            SubmitVerificationCountSheet(row: row) { quantity, notes in
                submit(row: row, quantity: quantity, notes: notes)
            }
        }
        .alert("Verification Error", isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("OK") { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
        .onDisappear {
            NotificationCenter.default.post(name: .warehouseMyVerificationsPageInactive, object: nil)
        }
        .task { loadData() }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView("Loading verifications...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("myVerificationsLoadingState")
        } else if let loadError {
            ErrorStateView(message: loadError) { loadData() }
                .accessibilityIdentifier("myVerificationsErrorState")
        } else if rows.isEmpty {
            EmptyStateView(
                icon: "checkmark.seal",
                title: "No Verifications",
                message: "You do not have any warehouse counts assigned right now."
            )
            .accessibilityIdentifier("myVerificationsEmptyState")
        } else {
            List(rows) { row in
                Button {
                    selectedRow = row
                } label: {
                    VerificationAssignmentRow(row: row)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("myVerificationAssignmentRow_\(row.id)")
            }
            .accessibilityIdentifier("myVerificationsPopulatedState")
        }
    }

    private func loadData() {
        isLoading = true
        loadError = nil

        if let fixtureRows = fixtureRowsIfRequested() {
            rows = fixtureRows
            isLoading = ProcessInfo.processInfo.arguments.contains("-UITestingMyVerificationsLoading")
            if ProcessInfo.processInfo.arguments.contains("-UITestingMyVerificationsError") {
                loadError = "Unable to load verification assignments."
                isLoading = false
            }
            if !isLoading, loadError == nil {
                postActiveContext()
            }
            return
        }

        guard let service = appCore.warehouseService else {
            rows = []
            loadError = "Warehouse service is not available."
            isLoading = false
            return
        }

        guard let userId = appCore.currentUser?.id else {
            rows = []
            loadError = "Sign in to view your verification assignments."
            isLoading = false
            return
        }

        do {
            rows = try service.getMyMultiUserAuditAssignments(userId: userId).compactMap(VerificationRow.init)
            isLoading = false
            postActiveContext()
        } catch {
            rows = []
            loadError = error.localizedDescription
            isLoading = false
        }
    }

    private func submit(row: VerificationRow, quantity: Int, notes: String?) {
        guard quantity >= 0 else {
            actionError = "Quantity counted must be 0 or greater."
            return
        }

        if row.isFixtureDuplicate {
            selectedRow = nil
            actionError = Self.duplicateSubmitMessage
            return
        }

        guard let service = appCore.warehouseService else {
            actionError = "Warehouse service is not available."
            return
        }
        guard let userId = appCore.currentUser?.id else {
            actionError = "Sign in to submit this verification."
            return
        }
        guard let assignmentId = row.assignmentId else {
            actionError = "This verification assignment is missing an ID."
            return
        }

        do {
            try service.submitMultiUserCount(
                assignmentId: assignmentId,
                quantity: quantity,
                userId: userId,
                notes: notes
            )
            selectedRow = nil
            loadData()
        } catch WarehouseService.WarehouseError.sessionAlreadyCompleted {
            selectedRow = nil
            actionError = Self.duplicateSubmitMessage
        } catch WarehouseService.WarehouseError.invalidQuantity {
            actionError = "Quantity counted must be 0 or greater."
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func postActiveContext() {
        NotificationCenter.default.post(
            name: .warehouseMyVerificationsPageActive,
            object: nil,
            userInfo: ["context": "My Verifications: \(rows.count) pending operator count assignments."]
        )
    }

    private func fixtureRowsIfRequested() -> [VerificationRow]? {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("-UITestingMultiUserVerificationFixture") ||
              args.contains("-UITestingMyVerificationsPopulated") ||
              args.contains("-UITestingMyVerificationsEmpty") ||
              args.contains("-UITestingMyVerificationsError") ||
              args.contains("-UITestingMyVerificationsLoading") ||
              args.contains("-UITestingMyVerificationsDuplicate") else {
            return nil
        }

        if args.contains("-UITestingMyVerificationsEmpty") {
            return []
        }

        return [
            VerificationRow(
                id: "fixture-s2",
                assignmentId: nil,
                partId: 92001,
                partName: "S2 Copper Coupling",
                binLocation: "WH-A-02-S2",
                assignedUserName: "UITest Owner",
                auditSessionId: 486,
                createdAt: "Today, 9:15 AM",
                isFixtureDuplicate: false
            ),
            VerificationRow(
                id: "fixture-s3",
                assignmentId: nil,
                partId: 92002,
                partName: "S3 Brass Valve",
                binLocation: "WH-A-03-S3",
                assignedUserName: "UITest Owner",
                auditSessionId: 486,
                createdAt: "Today, 9:30 AM",
                isFixtureDuplicate: args.contains("-UITestingMyVerificationsDuplicate")
            )
        ]
    }
}

private struct VerificationRow: Identifiable, Hashable {
    let id: String
    let assignmentId: Int64?
    let partId: Int64
    let partName: String
    let binLocation: String?
    let assignedUserName: String?
    let auditSessionId: Int64?
    let createdAt: String?
    let isFixtureDuplicate: Bool

    init?(_ assignment: MultiUserAuditAssignment) {
        guard let assignmentId = assignment.id else { return nil }
        self.id = String(assignmentId)
        self.assignmentId = assignmentId
        self.partId = assignment.partId
        self.partName = assignment.partName
        self.binLocation = assignment.binLocation
        self.assignedUserName = assignment.assignedUserName
        self.auditSessionId = assignment.auditSessionId
        self.createdAt = assignment.createdAt
        self.isFixtureDuplicate = false
    }

    init(
        id: String,
        assignmentId: Int64?,
        partId: Int64,
        partName: String,
        binLocation: String?,
        assignedUserName: String?,
        auditSessionId: Int64?,
        createdAt: String?,
        isFixtureDuplicate: Bool
    ) {
        self.id = id
        self.assignmentId = assignmentId
        self.partId = partId
        self.partName = partName
        self.binLocation = binLocation
        self.assignedUserName = assignedUserName
        self.auditSessionId = auditSessionId
        self.createdAt = createdAt
        self.isFixtureDuplicate = isFixtureDuplicate
    }

    var accessibilitySummary: String {
        [
            partName,
            binLocation.map { "Bin \($0)" },
            auditSessionId.map { "Audit session \($0)" },
            "Double tap to submit count"
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
    }
}

private struct VerificationAssignmentRow: View {
    let row: VerificationRow

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(.blue)
                .font(.title2)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(row.partName)
                    .font(.headline)
                    .accessibilityIdentifier("myVerificationPartName_\(row.id)")

                if let binLocation = row.binLocation, !binLocation.isEmpty {
                    Label(binLocation, systemImage: "mappin.and.ellipse")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("myVerificationBin_\(row.id)")
                }

                HStack(spacing: 8) {
                    if let sessionId = row.auditSessionId {
                        Text("Session #\(sessionId)")
                    }
                    if let createdAt = row.createdAt, !createdAt.isEmpty {
                        Text(createdAt)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.accessibilitySummary)
        .accessibilityHint("Opens the submit count sheet. The expected system quantity is hidden.")
        .accessibilitySortPriority(1)
    }
}

private struct SubmitVerificationCountSheet: View {
    let row: VerificationRow
    let onSubmit: (Int, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var quantityText = ""
    @State private var notes = ""
    @FocusState private var quantityFocused: Bool

    private var quantity: Int? {
        Int(quantityText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var isQuantityValid: Bool {
        guard let quantity else { return false }
        return quantity >= 0
    }

    private var quantityValidationMessage: String? {
        guard let quantity else { return nil }
        return quantity < 0 ? "Quantity counted must be 0 or greater." : nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Part") {
                    Text(row.partName)
                        .font(.headline)
                    if let binLocation = row.binLocation, !binLocation.isEmpty {
                        Label(binLocation, systemImage: "mappin.and.ellipse")
                    }
                    Text("System expected quantity is hidden until the verification is resolved.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("expectedQuantityHiddenMessage")
                }

                Section("Count") {
                    TextField("Quantity counted", text: $quantityText)
                        .keyboardType(.numberPad)
                        .focused($quantityFocused)
                        .accessibilityIdentifier("myVerificationQuantityField")
                        .accessibilityLabel("\(row.partName) quantity counted")
                        .accessibilityHint("Enter the physical quantity counted. The expected quantity is not shown.")
                        .accessibilitySortPriority(2)

                    if let quantityValidationMessage {
                        Text(quantityValidationMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("myVerificationQuantityValidation")
                    }

                    TextField("Notes optional", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                        .accessibilityIdentifier("myVerificationNotesField")
                }
            }
            .navigationTitle("Submit Count")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") {
                        guard let quantity else { return }
                        onSubmit(quantity, notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes)
                    }
                    .disabled(!isQuantityValid)
                    .accessibilityIdentifier("myVerificationSubmitButton")
                }
            }
            .onAppear { quantityFocused = true }
        }
    }
}

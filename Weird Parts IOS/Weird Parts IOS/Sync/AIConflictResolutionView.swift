import SwiftUI
import WiredPartCore

/// Model representing an AI-merged conflict resolution with alternatives.
struct AIConflictResolution {
    let original: String?
    let deviceAEdit: String
    let deviceBEdit: String
    let aiMerge: String
    let aiAlternative1: String
    let aiAlternative2: String
    let deviceALabel: String
    let deviceBLabel: String
}

/// AI-assisted conflict resolution view for hard text conflicts.
///
/// Shows the AI-merged version prominently with a purple glow effect,
/// plus expandable alternatives: both original edits, two AI alternatives
/// prioritizing each side, and a manual rewrite option.
struct AIConflictResolutionView: View {
    let resolution: AIConflictResolution
    let onResolve: (String) -> Void

    @State private var showAllOptions = false
    @State private var customText = ""
    @State private var showCustomEditor = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // AI Merged version (with glow)
            VStack(alignment: .leading, spacing: 6) {
                Label("AI Merged", systemImage: "sparkles")
                    .font(.caption.bold())
                    .foregroundStyle(.purple)

                Text(resolution.aiMerge)
                    .font(.callout)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.purple.opacity(0.05))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(.purple.opacity(0.3), lineWidth: 1.5)
                            )
                    )
                    .shadow(color: .purple.opacity(0.2), radius: 8)

                Button("Use AI Merge") { onResolve(resolution.aiMerge) }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                    .controlSize(.small)
            }

            Divider()

            // Expand/collapse for all options
            Button {
                withAnimation { showAllOptions.toggle() }
            } label: {
                HStack {
                    Text("See all options")
                    Spacer()
                    Image(systemName: showAllOptions ? "chevron.up" : "chevron.down")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if showAllOptions {
                // Device A edit
                optionCard(
                    label: resolution.deviceALabel,
                    text: resolution.deviceAEdit,
                    icon: "iphone",
                    color: .blue
                )

                // Device B edit
                optionCard(
                    label: resolution.deviceBLabel,
                    text: resolution.deviceBEdit,
                    icon: "iphone",
                    color: .orange
                )

                // AI Alternative 1 — prioritize Device A
                optionCard(
                    label: "AI: \(resolution.deviceALabel) priority",
                    text: resolution.aiAlternative1,
                    icon: "sparkles",
                    color: .purple.opacity(0.7)
                )

                // AI Alternative 2 — prioritize Device B
                optionCard(
                    label: "AI: \(resolution.deviceBLabel) priority",
                    text: resolution.aiAlternative2,
                    icon: "sparkles",
                    color: .purple.opacity(0.7)
                )

                // Original value
                if let original = resolution.original, !original.isEmpty {
                    optionCard(
                        label: "Original (before edits)",
                        text: original,
                        icon: "clock.arrow.circlepath",
                        color: .secondary
                    )
                }

                // Manual rewrite
                Divider()

                Button {
                    customText = resolution.aiMerge
                    showCustomEditor.toggle()
                } label: {
                    Label("Write my own version", systemImage: "pencil")
                        .font(.caption)
                }

                if showCustomEditor {
                    TextEditor(text: $customText)
                        .font(.callout)
                        .frame(height: 100)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.3))
                        )

                    Button("Use My Version") { onResolve(customText) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
            }
        }
    }

    // MARK: - Option Card

    private func optionCard(label: String, text: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(label, systemImage: icon)
                .font(.caption)
                .foregroundStyle(color)

            Text(text)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(color.opacity(0.05))
                )

            Button("Use This") { onResolve(text) }
                .buttonStyle(.bordered)
                .controlSize(.mini)
        }
    }
}

/// Critical conflict view — financial/stock data that requires human decision.
///
/// Shows both values side-by-side with clear labels. AI cannot auto-resolve
/// these — the user must pick one.
struct CriticalConflictView: View {
    let conflict: ConflictLogEntry
    let onResolveLocal: () -> Void
    let onResolveRemote: () -> Void
    @State private var pendingResolution: PendingResolution?

    private enum PendingResolution: String {
        case local
        case remote
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text("Manual Resolution Required")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }

            Text("This involves financial or inventory data. This screen is review-only for critical records; make the change on the source record if a value needs to be corrected.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 16) {
                // Local
                VStack(spacing: 8) {
                    Text("This Device")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.blue)
                    Text(conflict.localValue ?? "(empty)")
                        .font(.title3.monospaced())
                        .fontWeight(.semibold)
                    Text(formatTS(conflict.localTs))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Button("Mark Reviewed") { pendingResolution = .local }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                        .controlSize(.small)
                }
                .frame(maxWidth: .infinity)

                Divider().frame(height: 100)

                // Remote
                VStack(spacing: 8) {
                    Text("Remote")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.purple)
                    Text(conflict.remoteValue ?? "(empty)")
                        .font(.title3.monospaced())
                        .fontWeight(.semibold)
                    Text(formatTS(conflict.remoteTs))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Button("Mark Reviewed") { pendingResolution = .remote }
                        .buttonStyle(.borderedProminent)
                        .tint(.purple)
                        .controlSize(.small)
                }
                .frame(maxWidth: .infinity)
            }

            Text("Tip: For stock discrepancies, check the physical count.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.red.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.red.opacity(0.2), lineWidth: 1)
                )
        )
        .alert(
            "Confirm Critical Review",
            isPresented: Binding(
                get: { pendingResolution != nil },
                set: { if !$0 { pendingResolution = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) {
                pendingResolution = nil
            }
            Button("Confirm", role: .destructive) {
                guard let pendingResolution else { return }
                switch pendingResolution {
                case .local:
                    onResolveLocal()
                case .remote:
                    onResolveRemote()
                }
                self.pendingResolution = nil
            }
        } message: {
            let selectedLabel = pendingResolution == .local ? "This Device" : "Remote"
            Text(
                "This will only mark the \(selectedLabel) value reviewed for \(conflict.tableName).\(conflict.fieldName). It will not write to critical financial or inventory records."
            )
        }
    }

    private func formatTS(_ ts: String) -> String {
        String(ts.prefix(19).replacingOccurrences(of: "T", with: " "))
    }
}

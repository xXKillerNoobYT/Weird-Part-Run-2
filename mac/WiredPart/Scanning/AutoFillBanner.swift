import SwiftUI
import WiredPartCore

// MARK: - Auto-Fill Banner

/// Banner shown after OCR extraction or QR scan with extracted fields.
///
/// Displays extracted fields grouped by confidence tier (green/yellow/red).
/// Provides "Accept All" and "Clear" actions.
struct AutoFillBanner: View {
    let fields: [ExtractedField]
    let onAccept: ([ExtractedField]) -> Void
    let onDismiss: () -> Void

    @State private var selectedFields: Set<UUID>

    init(
        fields: [ExtractedField],
        onAccept: @escaping ([ExtractedField]) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.fields = fields
        self.onAccept = onAccept
        self.onDismiss = onDismiss
        // Pre-select high-confidence fields
        self._selectedFields = State(initialValue: Set(
            fields.filter(\.isAutoFillReady).map(\.id)
        ))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Image(systemName: "doc.text.magnifyingglass")
                    .foregroundStyle(.blue)
                Text("Extracted Fields")
                    .font(.headline)
                Spacer()
                Button("Clear") {
                    onDismiss()
                }
                .buttonStyle(.borderless)
            }

            // Field list grouped by confidence
            VStack(alignment: .leading, spacing: 4) {
                ForEach(fields) { field in
                    HStack(spacing: 8) {
                        // Selection toggle
                        Image(systemName: selectedFields.contains(field.id)
                              ? "checkmark.circle.fill"
                              : "circle")
                            .foregroundStyle(selectedFields.contains(field.id)
                                             ? .blue : .secondary)
                            .onTapGesture {
                                if selectedFields.contains(field.id) {
                                    selectedFields.remove(field.id)
                                } else {
                                    selectedFields.insert(field.id)
                                }
                            }

                        // Confidence indicator
                        ConfidenceIndicator(confidence: field.confidence)

                        // Field label and value
                        VStack(alignment: .leading, spacing: 1) {
                            Text(field.label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(field.value)
                                .font(.body)
                        }

                        Spacer()
                    }
                    .padding(.vertical, 2)
                }
            }

            // Actions
            HStack {
                Button("Accept Selected") {
                    let accepted = fields.filter { selectedFields.contains($0.id) }
                    onAccept(accepted)
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedFields.isEmpty)

                Button("Accept All") {
                    onAccept(fields)
                }
                .buttonStyle(.bordered)

                Spacer()
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.blue.opacity(0.3))
        )
    }
}

// MARK: - Confidence Indicator

/// Small colored indicator showing OCR/match confidence level.
struct ConfidenceIndicator: View {
    let confidence: Float

    private var tier: ConfidenceTier {
        OCRConfidence.tier(for: confidence)
    }

    private var color: Color {
        switch tier {
        case .high: return .green
        case .medium: return .yellow
        case .low: return .red
        }
    }

    var body: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text("\(Int(confidence * 100))%")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}

// MARK: - QR Auto-Fill Banner

/// Banner shown after QR scan with entity data to populate a form.
struct QRAutoFillBanner: View {
    let result: QRAutoFillResult
    let onAccept: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "qrcode")
                .font(.title2)
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 2) {
                if let entityType = result.entityType {
                    Text(entityType.rawValue.capitalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(result.code)
                    .font(.headline)

                if result.isFound {
                    Text("Found in database")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Text("Not found in database")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Spacer()

            if result.isFound {
                Button("Auto-Fill") {
                    onAccept()
                }
                .buttonStyle(.borderedProminent)
            }

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.blue.opacity(0.3))
        )
    }
}

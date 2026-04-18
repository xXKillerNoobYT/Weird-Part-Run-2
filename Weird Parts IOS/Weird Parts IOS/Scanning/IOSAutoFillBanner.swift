import SwiftUI
import WiredPartCore


// MARK: - iOS Auto-Fill Banner

/// Banner shown after OCR extraction or QR scan with extracted fields (iOS).
///
/// Touch-optimized version with larger tap targets and swipe-to-dismiss.
struct IOSAutoFillBanner: View {
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
        self._selectedFields = State(initialValue: Set(
            fields.filter(\.isAutoFillReady).map(\.id)
        ))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "doc.text.magnifyingglass")
                    .foregroundStyle(.blue)
                Text("Extracted Fields")
                    .font(.headline)
                Spacer()
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Dismiss")
            }

            // Field list
            ForEach(fields) { field in
                HStack(spacing: 12) {
                    Button {
                        if selectedFields.contains(field.id) {
                            selectedFields.remove(field.id)
                        } else {
                            selectedFields.insert(field.id)
                        }
                    } label: {
                        Image(systemName: selectedFields.contains(field.id)
                              ? "checkmark.circle.fill"
                              : "circle")
                            .font(.title3)
                            .foregroundStyle(selectedFields.contains(field.id)
                                             ? .blue : .secondary)
                    }
                    .buttonStyle(.plain)

                    // Confidence dot
                    IOSConfidenceIndicator(confidence: field.confidence)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(field.label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(field.value)
                            .font(.body)
                    }

                    Spacer()
                }
                .padding(.vertical, 4)
            }

            // Actions
            HStack(spacing: 12) {
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
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - iOS Confidence Indicator

/// Colored confidence indicator optimized for iOS touch displays.
struct IOSConfidenceIndicator: View {
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
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
            Text("\(Int(confidence * 100))%")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}

// MARK: - iOS QR Auto-Fill Banner

/// QR scan result banner optimized for iOS.
struct IOSQRAutoFillBanner: View {
    let result: QRAutoFillResult
    let onAccept: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "qrcode")
                .font(.title)
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 3) {
                if let entityType = result.entityType {
                    Text(entityType.rawValue.capitalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(result.code)
                    .font(.headline)

                if result.isFound {
                    Label("Found", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Label("Not found", systemImage: "questionmark.circle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Spacer()

            if result.isFound {
                Button("Fill") {
                    onAccept()
                }
                .buttonStyle(.borderedProminent)
            }

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}


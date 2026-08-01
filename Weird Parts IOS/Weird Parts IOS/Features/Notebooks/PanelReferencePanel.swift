import SwiftUI
import WiredPartCore

/// Reference panel (plan §6) — a learning aid shown beside the builder on
/// regular-width layouts (iPad / wide windows) and omitted on iPhone. Two
/// sections: what each breaker form factor is, and the color-coded type
/// legend from the catalog.
struct PanelReferencePanel: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Reference")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Form factors")
                        .font(.subheadline.bold())
                    referenceRow(
                        symbol: "square.fill",
                        title: "Full",
                        body: "One breaker per space. 2- and 3-pole spans reach down the same side (1+3, 1+3+5)."
                    )
                    referenceRow(
                        symbol: "square.split.1x2",
                        title: "Tandem (twin)",
                        body: "Two half-width circuits in one space, both on that space's leg. CTL panels may limit these to marked slots."
                    )
                    referenceRow(
                        symbol: "square.grid.2x2",
                        title: "Quad",
                        body: "Two spaces, three flavors: four singles, outer singles with a tied 240V center pair, or two independent 2-poles."
                    )
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Breaker types")
                        .font(.subheadline.bold())
                    ForEach(DesignBreakerType.allCases, id: \.self) { type in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color(hex: type.colorHex) ?? .gray)
                                .frame(width: 10, height: 10)
                            Text(type.displayName)
                                .font(.caption.bold())
                            Text(usage(for: type))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 0)
                        }
                        .frame(minHeight: 28)
                        .accessibilityElement(children: .combine)
                    }
                }

                Text("Phases rotate down the panel in rows: (1,2) → A, (3,4) → B, and so on through the panel's legs.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
        }
        .frame(maxWidth: 260)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemGroupedBackground)))
        .accessibilityIdentifier("panelReferencePanel")
    }

    private func referenceRow(symbol: String, title: String, body text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .frame(width: 20)
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption.bold())
                Text(text).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func usage(for type: DesignBreakerType) -> String {
        switch type {
        case .standard: return "general branch circuits"
        case .gfci: return "wet locations"
        case .afci: return "dwelling living areas"
        case .dualFunction: return "arc + ground fault"
        case .gfpe: return "equipment ground fault"
        case .hacr: return "HVAC equipment"
        case .general: return "sub-feeds"
        case .spare: return "reserved / open"
        }
    }
}

#Preview {
    PanelReferencePanel()
}

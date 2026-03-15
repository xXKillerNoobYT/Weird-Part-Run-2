import SwiftUI

/// Security administration page.
///
/// Placeholder — covers company setup, device certificates,
/// cross-company sharing, and key rotation. These features
/// depend on the full security and sync subsystems.
struct SecurityAdminPage: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Security Admin")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                GroupBox("Company Security Setup") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            Image(systemName: "lock.shield.fill")
                                .font(.title2)
                                .foregroundStyle(.blue)
                            VStack(alignment: .leading) {
                                Text("Security Configuration")
                                    .font(.headline)
                                Text("Manage company-wide security policies and encryption settings")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Text("Security configuration will be available when the sync and encryption subsystems are fully deployed.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                GroupBox("Device Certificates") {
                    HStack {
                        Text("Manage trusted device certificates")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("View Certificates") {}
                            .buttonStyle(.bordered)
                            .disabled(true)
                    }
                    .padding(.vertical, 4)
                }

                GroupBox("Cross-Company Sharing") {
                    Text("Configure data sharing policies with other WiredPart companies. This allows controlled exchange of part catalogs, supplier information, and pricing data.")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                }

                GroupBox("Key Rotation") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Scheduled key rotation ensures long-term security. When a key is rotated, all devices receive the new key via sync.")
                            .foregroundStyle(.secondary)
                        HStack {
                            Button("Rotate Company Key") {}
                                .buttonStyle(.bordered)
                                .disabled(true)
                            Text("Last rotated: Never")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

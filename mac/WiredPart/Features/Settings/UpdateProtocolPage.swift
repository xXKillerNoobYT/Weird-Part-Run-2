import SwiftUI

/// Update protocol management page.
///
/// Placeholder — covers version registry, validation pipeline,
/// and fleet update targets. This is used to manage how app
/// updates are distributed across the device fleet.
struct UpdateProtocolPage: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Update Protocol")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                GroupBox("Current Version") {
                    HStack(spacing: 12) {
                        Image(systemName: "app.badge.checkmark")
                            .font(.title2)
                            .foregroundStyle(.green)
                        VStack(alignment: .leading) {
                            Text("WiredPart v1.0.0")
                                .font(.headline)
                            Text("macOS native build")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("Up to date")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(.green.opacity(0.15)))
                            .foregroundStyle(.green)
                    }
                    .padding(.vertical, 4)
                }

                GroupBox("Version Registry") {
                    Text("The version registry tracks all released versions and their validation status. New versions go through a validation pipeline before being deployed to the fleet.")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                }

                GroupBox("Validation Pipeline") {
                    VStack(alignment: .leading, spacing: 8) {
                        pipelineStep(1, "Build Verification", status: "N/A")
                        pipelineStep(2, "Automated Tests", status: "N/A")
                        pipelineStep(3, "Schema Migration Check", status: "N/A")
                        pipelineStep(4, "Fleet Compatibility", status: "N/A")
                    }
                    .padding(.vertical, 4)
                }

                GroupBox("Fleet Targets") {
                    Text("Define which devices receive updates and in what order. Staged rollouts reduce risk by deploying to a subset of devices first.")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                }

                infoCard(
                    "About Update Protocol",
                    text: "The update protocol ensures safe deployment of new versions across all devices in the fleet. Updates are validated, staged, and monitored to prevent disruptions."
                )
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func pipelineStep(_ number: Int, _ label: String, status: String) -> some View {
        HStack {
            Text("\(number).")
                .frame(width: 24)
                .foregroundStyle(.secondary)
            Text(label)
            Spacer()
            Text(status)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private func infoCard(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: "info.circle")
                .font(.headline)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.blue.opacity(0.05)))
    }
}

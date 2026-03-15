import SwiftUI

/// Data export options page.
///
/// Placeholder — will allow exporting database contents in various formats
/// (CSV, JSON, SQLite dump) for external tools and reporting.
struct DataExportPage: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Data Export")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Export your data for use in external tools, spreadsheets, or backup purposes.")
                    .foregroundStyle(.secondary)

                GroupBox("Export Formats") {
                    VStack(alignment: .leading, spacing: 12) {
                        exportOption(
                            icon: "tablecells",
                            title: "CSV Export",
                            description: "Export tables as comma-separated value files for use in Excel or Google Sheets."
                        )
                        Divider()
                        exportOption(
                            icon: "curlybraces",
                            title: "JSON Export",
                            description: "Export data as JSON documents for use in other applications or APIs."
                        )
                        Divider()
                        exportOption(
                            icon: "cylinder",
                            title: "SQLite Dump",
                            description: "Create a complete copy of the database file for archival or migration."
                        )
                    }
                    .padding(.vertical, 4)
                }

                GroupBox("Scheduled Exports") {
                    Text("Configure automatic exports on a schedule. Exported files can be saved to a shared directory or uploaded to cloud storage.")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                }

                infoCard(
                    "Data Export",
                    text: "Data export functionality is coming soon. You will be able to export individual tables or the entire database in multiple formats."
                )
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func exportOption(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Export") {}
                .buttonStyle(.bordered)
                .disabled(true)
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

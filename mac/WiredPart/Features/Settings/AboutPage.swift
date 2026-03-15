import SwiftUI
import GRDB
import WiredPartCore

/// About page showing application info, platform details, and data counts.
struct AboutPage: View {
    @EnvironmentObject private var appCore: AppCore
    @State private var dataCounts: [(label: String, count: Int)] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("About")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                // App Info
                GroupBox("Application") {
                    VStack(alignment: .leading, spacing: 8) {
                        infoRow("Name", value: "WiredPart")
                        infoRow("Version", value: WiredPartCore.version)
                        infoRow("Description", value: "Field service management for electrical contractors")
                    }
                    .padding(.vertical, 4)
                }

                // Platform Info
                GroupBox("Platform") {
                    VStack(alignment: .leading, spacing: 8) {
                        infoRow("Platform", value: "macOS")
                        infoRow("Architecture", value: Self.architecture)
                        infoRow("App Framework", value: "SwiftUI + GRDB")
                        infoRow("Core Package", value: "WiredPartCore \(WiredPartCore.version)")
                    }
                    .padding(.vertical, 4)
                }

                // Data Counts
                if !dataCounts.isEmpty {
                    GroupBox("Database") {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(dataCounts, id: \.label) { item in
                                infoRow(item.label, value: "\(item.count)")
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { loadCounts() }
    }

    private func infoRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 140, alignment: .leading)
            Text(value)
        }
        .font(.callout)
    }

    private static var architecture: String {
        #if arch(arm64)
        return "Apple Silicon (arm64)"
        #elseif arch(x86_64)
        return "Intel (x86_64)"
        #else
        return "Unknown"
        #endif
    }

    private func loadCounts() {
        guard let db = appCore.db else { return }
        let tables: [(label: String, table: String)] = [
            ("Users", "users"),
            ("Parts", "parts"),
            ("Jobs", "jobs"),
            ("Purchase Orders", "purchase_orders"),
            ("Vehicles", "vehicles"),
            ("Notebooks", "notebooks"),
        ]

        var results: [(label: String, count: Int)] = []
        do {
            try db.writer.read { dbConnection in
                for item in tables {
                    let count = try Int.fetchOne(
                        dbConnection,
                        sql: "SELECT COUNT(*) FROM \(item.table) WHERE deleted_at IS NULL"
                    ) ?? 0
                    results.append((item.label, count))
                }
            }
        } catch {
            // Some tables may not exist yet — that's fine
        }
        dataCounts = results
    }
}

import SwiftUI
import GRDB
import WiredPartCore

/// Supplier communication bridge settings page for iOS.
///
/// Shows supplier portal configuration status and connected suppliers.
/// Full portal configuration (API keys, endpoints) is managed on desktop;
/// this page provides a read-only overview of bridge status.
struct IOSSupplierBridgePage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var isLoading = true
    @State private var bridges: [SupplierBridge] = []
    @State private var errorMessage: String?

    // MARK: - Body

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading supplier bridges...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if bridges.isEmpty {
                ContentUnavailableView(
                    "No Supplier Bridges",
                    systemImage: "building.2",
                    description: Text("No supplier communication bridges have been configured. Set these up from the desktop application.")
                )
            } else {
                Form {
                    bridgesSection
                    configInfoSection
                }
            }
        }
        .navigationTitle("Supplier Bridge")
        .task { loadData() }
    }

    // MARK: - Bridges Section

    private var bridgesSection: some View {
        Section("Connected Suppliers (\(bridges.count))") {
            ForEach(bridges) { bridge in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(bridge.supplierName)
                            .font(.body.weight(.medium))
                        Spacer()
                        statusIndicator(bridge.status)
                    }
                    HStack(spacing: 12) {
                        Label(bridge.protocol_, systemImage: "network")
                        if let lastSync = bridge.lastSyncAt {
                            Label(lastSync, systemImage: "clock")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func statusIndicator(_ status: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(status == "connected" ? Color.green : (status == "error" ? Color.red : Color.orange))
                .frame(width: 8, height: 8)
            Text(status.capitalized)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Info Section

    private var configInfoSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Label("Bridge credentials are managed on desktop", systemImage: "desktopcomputer")
                Label("Supplier portals sync orders and pricing data", systemImage: "arrow.triangle.2.circlepath")
                Label("Portal notes are attached to purchase orders", systemImage: "doc.text")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let db = appCore.db else {
            errorMessage = "Database not available."
            isLoading = false
            return
        }
        do {
            bridges = try db.writer.read { db in
                let rows = try Row.fetchAll(db, sql: """
                    SELECT sb.id, sb.status, sb.protocol, sb.last_sync_at,
                           COALESCE(s.name, 'Unknown Supplier') AS supplier_name
                    FROM supplier_bridges sb
                    LEFT JOIN suppliers s ON s.id = sb.supplier_id
                    ORDER BY s.name ASC
                """)
                return rows.map { row in
                    SupplierBridge(
                        id: "\(row["id"] as Int64? ?? 0)",
                        supplierName: row["supplier_name"] as? String ?? "Unknown",
                        status: row["status"] as? String ?? "unknown",
                        protocol_: row["protocol"] as? String ?? "HTTP",
                        lastSyncAt: row["last_sync_at"] as? String
                    )
                }
            }
        } catch {
            if !error.localizedDescription.contains("no such table") {
                errorMessage = "Failed to load: \(error.localizedDescription)"
            }
            bridges = []
        }
        isLoading = false
    }

    // MARK: - Model

    private struct SupplierBridge: Identifiable {
        let id: String
        let supplierName: String
        let status: String
        let protocol_: String
        let lastSyncAt: String?
    }
}

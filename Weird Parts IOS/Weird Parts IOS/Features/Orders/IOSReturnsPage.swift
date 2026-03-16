import SwiftUI
import WiredPartCore

/// Returns list page for iOS.
///
/// Displays a searchable list of part returns with return type, status badge,
/// supplier name, reason, and credit amount. Supports pull-to-refresh
/// and status-based filtering.
struct IOSReturnsPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var returns: [OrdersService.ReturnListItem] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var statusFilter = "all"

    private let statusOptions = ["all", "pending", "requested", "approved", "shipped", "completed", "cancelled"]

    var body: some View {
        VStack(spacing: 0) {
            statusPicker
            returnsList
        }
        .navigationTitle("Returns")
        .searchable(text: $searchText, prompt: "Search returns...")
        .onChange(of: searchText) { loadData() }
        .refreshable { loadData() }
        .task { loadData() }
    }

    // MARK: - Status Picker

    private var statusPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(statusOptions, id: \.self) { status in
                    Button {
                        statusFilter = status
                        loadData()
                    } label: {
                        Text(status == "all" ? "All" : status.capitalized)
                            .font(.caption)
                            .fontWeight(statusFilter == status ? .bold : .regular)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule().fill(statusFilter == status ? Color.accentColor : Color.secondary.opacity(0.2))
                            )
                            .foregroundStyle(statusFilter == status ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Returns List

    @ViewBuilder
    private var returnsList: some View {
        if isLoading {
            ProgressView("Loading returns...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if filteredReturns.isEmpty {
            ContentUnavailableView {
                Label("No Returns", systemImage: "arrow.uturn.left.circle")
            } description: {
                Text("No returns match your criteria.")
            }
        } else {
            List(filteredReturns, id: \.id) { ret in
                returnRow(ret)
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #endif
        }
    }

    private var filteredReturns: [OrdersService.ReturnListItem] {
        guard !searchText.isEmpty else { return returns }
        let query = searchText.lowercased()
        return returns.filter {
            $0.returnType.lowercased().contains(query) ||
            ($0.supplierName?.lowercased().contains(query) ?? false) ||
            ($0.reason?.lowercased().contains(query) ?? false)
        }
    }

    private func returnRow(_ ret: OrdersService.ReturnListItem) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("RET #\(ret.id)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                    typeBadge(ret.returnType)
                }
                if let supplier = ret.supplierName {
                    Text(supplier)
                        .fontWeight(.medium)
                }
                if let reason = ret.reason, !reason.isEmpty {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                statusBadge(ret.status)
                if let credit = ret.creditAmount {
                    Text(String(format: "$%.2f", credit))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.green)
                }
                Label("\(ret.lineCount) items", systemImage: "shippingbox")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Badges

    private func statusBadge(_ status: String) -> some View {
        let color: Color = switch status {
        case "pending", "requested": .orange
        case "approved": .blue
        case "shipped": .purple
        case "completed": .green
        case "cancelled": .red
        default: .secondary
        }
        return Text(status.capitalized)
            .font(.system(.caption2, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }

    private func typeBadge(_ type: String) -> some View {
        Text(type.replacingOccurrences(of: "_", with: " ").capitalized)
            .font(.caption2)
            .foregroundStyle(.purple)
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let service = appCore.ordersService else { return }
        isLoading = returns.isEmpty
        do {
            returns = try service.listReturns(
                status: statusFilter == "all" ? nil : statusFilter
            )
        } catch {
            print("[IOSReturnsPage] Load error: \(error)")
        }
        isLoading = false
    }
}

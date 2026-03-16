import SwiftUI
import WiredPartCore

/// Dispatch board page for iOS.
///
/// Shows the dispatch board for the selected date with rows for each
/// dispatched user showing their job, vehicle, and status.
/// Supports pull-to-refresh and date navigation.
struct IOSDispatchPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var dispatches: [SchedulingService.DispatchRow] = []
    @State private var isLoading = true
    @State private var selectedDate = Date()
    @State private var searchText = ""

    private var dateString: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: selectedDate)
    }

    private var displayDate: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f.string(from: selectedDate)
    }

    var body: some View {
        VStack(spacing: 0) {
            dateNavigator
            dispatchList
        }
        .navigationTitle("Dispatch Board")
        .searchable(text: $searchText, prompt: "Search dispatches...")
        .refreshable { loadData() }
        .task { loadData() }
    }

    // MARK: - Date Navigator

    private var dateNavigator: some View {
        HStack {
            Button {
                selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate)!
                loadData()
            } label: {
                Image(systemName: "chevron.left")
            }

            Spacer()

            Text(displayDate)
                .font(.subheadline)
                .fontWeight(.medium)

            Spacer()

            Button {
                selectedDate = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate)!
                loadData()
            } label: {
                Image(systemName: "chevron.right")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    // MARK: - Dispatch List

    @ViewBuilder
    private var dispatchList: some View {
        if isLoading {
            ProgressView("Loading dispatch board...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if filteredDispatches.isEmpty {
            ContentUnavailableView {
                Label("No Dispatches", systemImage: "person.3.sequence")
            } description: {
                Text("No dispatches for \(displayDate).")
            }
        } else {
            List(filteredDispatches, id: \.id) { dispatch in
                dispatchRow(dispatch)
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #endif
        }
    }

    private var filteredDispatches: [SchedulingService.DispatchRow] {
        guard !searchText.isEmpty else { return dispatches }
        let query = searchText.lowercased()
        return dispatches.filter {
            $0.userName.lowercased().contains(query) ||
            $0.jobName.lowercased().contains(query) ||
            ($0.vehicleName?.lowercased().contains(query) ?? false)
        }
    }

    private func dispatchRow(_ dispatch: SchedulingService.DispatchRow) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "person.circle")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 4) {
                Text(dispatch.userName)
                    .fontWeight(.medium)
                Label(dispatch.jobName, systemImage: "hammer")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let vehicle = dispatch.vehicleName {
                    Label(vehicle, systemImage: "car")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let notes = dispatch.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            statusBadge(dispatch.status)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Badges

    private func statusBadge(_ status: String) -> some View {
        let color: Color = switch status {
        case "pending": .orange
        case "dispatched": .blue
        case "en_route": .purple
        case "on_site": .green
        case "completed": .green
        case "cancelled": .red
        default: .secondary
        }
        return Text(status.replacingOccurrences(of: "_", with: " ").capitalized)
            .font(.system(.caption2, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let service = appCore.schedulingService else { return }
        isLoading = dispatches.isEmpty
        do {
            dispatches = try service.getDispatchBoard(date: dateString)
        } catch {
            print("[IOSDispatchPage] Load error: \(error)")
        }
        isLoading = false
    }
}

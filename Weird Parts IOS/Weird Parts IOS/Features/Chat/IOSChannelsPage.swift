import SwiftUI
import WiredPartCore

/// Chat channels list page for iOS.
///
/// Displays the current user's chat channels with channel name, type badge,
/// job name, member count, and last message time. Supports pull-to-refresh
/// and search filtering.
struct IOSChannelsPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var channels: [ChatService.ChannelListItem] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var loadError: String?
    @State private var activeSheet: ActiveSheet?

    private enum ActiveSheet: Identifiable {
        case createChannel
        case newDM
        case supplierChannel

        var id: String {
            switch self {
            case .createChannel: "createChannel"
            case .newDM: "newDM"
            case .supplierChannel: "supplierChannel"
            }
        }
    }

    var body: some View {
        channelList
            .navigationTitle("Channels")
            .searchable(text: $searchText, prompt: "Search channels...")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            activeSheet = .createChannel
                        } label: {
                            Label("New Channel", systemImage: "number")
                        }
                        Button {
                            activeSheet = .newDM
                        } label: {
                            Label("New Message", systemImage: "envelope")
                        }
                        Button {
                            activeSheet = .supplierChannel
                        } label: {
                            Label("Supplier Channel", systemImage: "shippingbox")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .createChannel:
                    CreateChannelSheet(channelType: "group", onSave: { loadData() })
                        .environmentObject(appCore)
                case .newDM:
                    CreateChannelSheet(channelType: "dm", onSave: { loadData() })
                        .environmentObject(appCore)
                case .supplierChannel:
                    CreateChannelSheet(channelType: "supplier", onSave: { loadData() })
                        .environmentObject(appCore)
                }
            }
            .refreshable { loadData() }
            .task { loadData() }
    }

    // MARK: - Channel List

    @ViewBuilder
    private var channelList: some View {
        if isLoading {
            ProgressView("Loading channels...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = loadError {
            ErrorStateView(message: error) { loadData() }
        } else if filteredChannels.isEmpty {
            EmptyStateView(
                icon: "bubble.left.and.bubble.right",
                title: "No Channels",
                message: "You haven't joined any channels yet."
            )
        } else {
            List(filteredChannels, id: \.id) { channel in
                NavigationLink {
                    IOSMessageThreadView(
                        channelId: channel.id,
                        channelName: channel.name ?? channel.jobName ?? "Chat"
                    )
                    .environmentObject(appCore)
                } label: {
                    channelRow(channel)
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    private var filteredChannels: [ChatService.ChannelListItem] {
        guard !searchText.isEmpty else { return channels }
        let query = searchText.lowercased()
        return channels.filter {
            ($0.name?.lowercased().contains(query) ?? false) ||
            ($0.jobName?.lowercased().contains(query) ?? false) ||
            $0.channelType.lowercased().contains(query)
        }
    }

    private func channelRow(_ channel: ChatService.ChannelListItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: channelIcon(channel.channelType))
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(channel.name ?? channel.jobName ?? "Direct Message")
                        .fontWeight(.medium)
                    channelTypeBadge(channel.channelType)
                }
                if let jobName = channel.jobName, channel.name != nil {
                    Label(jobName, systemImage: channel.channelType == "supplier" ? "building.2" : "hammer")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let lastMessage = channel.lastMessageAt, !lastMessage.isEmpty {
                    Text(lastMessage)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Label("\(channel.memberCount)", systemImage: "person.2")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(channel.name ?? channel.jobName ?? "Direct Message"), \(channel.channelType) channel, \(channel.memberCount) members")
    }

    // MARK: - Helpers

    private func channelIcon(_ type: String) -> String {
        switch type {
        case "job": return "hammer.circle"
        case "dm": return "person.circle"
        case "group": return "person.3"
        case "supplier": return "shippingbox.circle"
        default: return "bubble.left.and.bubble.right"
        }
    }

    private func channelTypeBadge(_ type: String) -> some View {
        let color: Color = switch type {
        case "job": .blue
        case "dm": .purple
        case "group": .green
        case "supplier": .orange
        default: .secondary
        }
        return Text(type.uppercased())
            .font(.system(.caption2, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let service = appCore.chatService else { return }
        guard let userId = appCore.currentUser?.id else { return }
        isLoading = channels.isEmpty
        loadError = nil
        do {
            channels = try service.listChannels(userId: userId)
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }
}

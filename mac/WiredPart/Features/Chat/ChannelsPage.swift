import SwiftUI
import WiredPartCore

/// Chat channels page showing all channels the current user is a member of.
///
/// Displays a list-style layout (not table) showing channel name, type badge,
/// member count, and last activity timestamp. Uses loading/empty/data states.
struct ChannelsPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - Data State

    @State private var channels: [ChatService.ChannelListItem] = []
    @State private var stats: ChatService.ChatStats?
    @State private var isLoading = true
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            channelList
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { loadData() }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Channels")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                if let stats {
                    Text("\(stats.totalChannels) channel\(stats.totalChannels == 1 ? "" : "s") · \(stats.openQuestions) open question\(stats.openQuestions == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            TextField("Search channels...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
                .onChange(of: searchText) { _, _ in }

            Button {
                loadData()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    // MARK: - Channel List

    @ViewBuilder
    private var channelList: some View {
        if isLoading {
            ProgressView("Loading channels...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if filteredChannels.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 40))
                    .foregroundStyle(.tertiary)
                Text("No channels")
                    .font(.headline)
                Text(searchText.isEmpty
                     ? "You are not a member of any channels yet."
                     : "No channels match your search.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(filteredChannels) { channel in
                        channelCard(channel)
                    }
                }
                .padding(24)
            }
        }
    }

    private var filteredChannels: [ChatService.ChannelListItem] {
        guard !searchText.isEmpty else { return channels }
        let term = searchText.lowercased()
        return channels.filter { channel in
            let name = (channel.name ?? "").lowercased()
            let job = (channel.jobName ?? "").lowercased()
            return name.contains(term) || job.contains(term)
        }
    }

    private func channelCard(_ channel: ChatService.ChannelListItem) -> some View {
        GroupBox {
            HStack(spacing: 12) {
                // Channel icon
                Image(systemName: channelIcon(channel.channelType))
                    .font(.title2)
                    .foregroundStyle(channelColor(channel.channelType))
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(channel.name ?? channel.jobName ?? "Unnamed Channel")
                            .font(.headline)

                        typeBadge(channel.channelType)
                    }

                    HStack(spacing: 16) {
                        Label("\(channel.memberCount) member\(channel.memberCount == 1 ? "" : "s")", systemImage: "person.2")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let jobName = channel.jobName {
                            Label(jobName, systemImage: "hammer")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()

                if let lastMsg = channel.lastMessageAt {
                    Text(formatDate(lastMsg))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Helpers

    private func channelIcon(_ type: String) -> String {
        switch type {
        case "group": return "bubble.left.and.bubble.right"
        case "dm": return "person.2"
        case "job": return "hammer"
        case "announcement": return "megaphone"
        default: return "bubble.left"
        }
    }

    private func channelColor(_ type: String) -> Color {
        switch type {
        case "group": .blue
        case "dm": .purple
        case "job": .orange
        case "announcement": .green
        default: .secondary
        }
    }

    private func typeBadge(_ type: String) -> some View {
        Text(type.capitalized)
            .font(.system(size: 9, weight: .bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(channelColor(type).opacity(0.15)))
            .foregroundStyle(channelColor(type))
    }

    nonisolated private func formatDate(_ dateStr: String) -> String {
        if dateStr.count >= 16 {
            return String(dateStr.prefix(16))
        }
        return dateStr
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let db = appCore.db else { return }
        isLoading = true

        let userId = appCore.currentUser?.id ?? 0

        do {
            let service = ChatService(db: db)
            channels = try service.listChannels(userId: userId)
            stats = try service.getChatStats()
        } catch {
            print("[ChannelsPage] Load error: \(error)")
        }

        isLoading = false
    }
}

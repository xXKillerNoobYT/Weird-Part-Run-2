import SwiftUI
import WiredPartCore

/// Unified chat inbox for iOS.
///
/// Shows all channel types (group, DM, job, supplier, Q&A, RFI) in one
/// sorted stream. Unread channels float to the top. Smart card filters
/// let users narrow by type.
struct IOSChannelsPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var inboxItems: [ChatService.InboxItem] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var loadError: String?
    @State private var typeFilter: ChannelTypeFilter = .all
    @State private var activeSheet: ActiveSheet?
    @State private var dateRange: ReportDateRange = .thisMonth
    @State private var customStart: Date = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var customEnd: Date = Date()

    private enum ChannelTypeFilter: String, CaseIterable {
        case all = "All"
        case unread = "Unread"
        case office = "Office"
        case messages = "Messages"
        case dm = "DMs"
        case job = "Job"
        case qa = "Q&A"
        case rfi = "RFI"
        case supplier = "Supplier"

        var matchTypes: [String] {
            switch self {
            case .all, .unread: return []
            case .office: return ["office"]
            case .messages: return ["group", "message", "jpo_hold"]
            case .dm: return ["dm"]
            case .job: return ["job"]
            case .qa: return ["qa", "jpo_qa"]
            case .rfi: return ["rfi"]
            case .supplier: return ["supplier"]
            }
        }
    }

    private enum ActiveSheet: Identifiable {
        case createChannel
        case newDM
        case supplierChannel
        case help

        var id: String {
            switch self {
            case .createChannel: "createChannel"
            case .newDM: "newDM"
            case .supplierChannel: "supplierChannel"
            case .help: "help"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            OnboardingBanner(pageId: "chat-channels")
            SkippedModuleHint(moduleId: "chat")
            StandardFilterBar(selectedRange: $dateRange, customStart: $customStart, customEnd: $customEnd)
            channelList
        }
            .task { appCore.onboardingManager?.markCompleted("chat-view-channels") }
            .navigationTitle("Chat")
            .searchable(text: $searchText, prompt: "Search conversations...")
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
                    .accessibilityLabel("Create new conversation")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { activeSheet = .help } label: {
                        Image(systemName: "questionmark.circle")
                    }
                    .accessibilityLabel("Help")
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
                case .help:
                    PageHelpSheet(
                        title: "Chat Channels Help",
                        sections: [
                            ("What This Page Does", "This is your unified chat inbox. It shows all your conversations in one place -- group channels, direct messages, job chats, supplier threads, and Q&A discussions. Unread messages float to the top so you never miss anything important."),
                            ("How to Use It", "Use the filter cards at the top to narrow by type (Office, Messages, DMs, Job, Q&A, Supplier). Tap any conversation to open it. Use the search bar to find conversations by name, message content, or sender. Pull down to refresh the list."),
                            ("Starting New Conversations", "Tap the + button in the top right to create a new group channel, start a direct message, or open a supplier channel. Group channels are great for team discussions. DMs are for one-on-one conversations."),
                            ("Tips", "Unread counts show as red badges on each conversation. The type icon on the left tells you what kind of channel it is at a glance. Job-linked channels show the job name as a blue tag next to the channel name.")
                        ]
                    )
                }
            }
            .refreshable { loadData() }
            .task { loadData() }
    }

    // MARK: - Smart Card Filters

    private var smartCardFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ChannelTypeFilter.allCases, id: \.self) { filter in
                    let count = countForFilter(filter)
                    smartCard(filter.rawValue, count: count, icon: iconForFilter(filter),
                              isActive: typeFilter == filter, color: colorForFilter(filter)) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            typeFilter = typeFilter == filter ? .all : filter
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private func smartCard(_ label: String, count: Int, icon: String, isActive: Bool,
                           color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: icon)
                        .font(.caption2)
                        .accessibilityHidden(true)
                    Text("\(count)")
                        .font(.system(.title3, weight: .bold))
                        .monospacedDigit()
                }
                Text(label)
                    .font(.caption2)
            }
            .frame(minWidth: 70)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isActive ? color.opacity(0.15) : Color(.systemGray6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isActive ? color : Color.clear, lineWidth: 1.5)
            )
            .foregroundStyle(isActive ? color : .primary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private func countForFilter(_ filter: ChannelTypeFilter) -> Int {
        let items = dateFilteredItems
        if filter == .all { return items.count }
        if filter == .unread { return items.filter { $0.unreadCount > 0 }.count }
        return items.filter { filter.matchTypes.contains($0.channelType) }.count
    }

    private func iconForFilter(_ filter: ChannelTypeFilter) -> String {
        switch filter {
        case .all: return "tray.full"
        case .unread: return "envelope.badge"
        case .office: return "building.columns"
        case .messages: return "bubble.left"
        case .dm: return "person.2"
        case .job: return "wrench.and.screwdriver"
        case .qa: return "questionmark.circle"
        case .rfi: return "doc.text.magnifyingglass"
        case .supplier: return "building.2"
        }
    }

    private func colorForFilter(_ filter: ChannelTypeFilter) -> Color {
        switch filter {
        case .all: return .accentColor
        case .unread: return .red
        case .office: return .purple
        case .messages: return .green
        case .dm: return .purple
        case .job: return .blue
        case .qa: return .orange
        case .rfi: return .indigo
        case .supplier: return .teal
        }
    }

    // MARK: - Filtered Items

    private var filteredItems: [ChatService.InboxItem] {
        var items = dateFilteredItems

        // Type filter
        if typeFilter == .unread {
            items = items.filter { $0.unreadCount > 0 }
        } else if typeFilter != .all {
            items = items.filter { typeFilter.matchTypes.contains($0.channelType) }
        }

        // Search filter
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            items = items.filter {
                $0.channelName.lowercased().contains(query) ||
                $0.lastMessagePreview.lowercased().contains(query) ||
                ($0.jobName?.lowercased().contains(query) ?? false) ||
                ($0.lastMessageBy?.lowercased().contains(query) ?? false)
            }
        }

        return items
    }

    private var dateFilteredItems: [ChatService.InboxItem] {
        inboxItems.filter {
            StandardFilterBarDateFilter.contains(
                $0.lastMessageDate,
                selectedRange: dateRange,
                customStart: customStart,
                customEnd: customEnd
            )
        }
    }

    // MARK: - Channel List

    @ViewBuilder
    private var channelList: some View {
        if isLoading {
            ProgressView("Loading channels...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = loadError {
            ErrorStateView(message: error) { loadData() }
        } else if filteredItems.isEmpty {
            EmptyStateView(
                icon: "bubble.left.and.bubble.right",
                title: "No Channels",
                message: emptyChannelsMessage,
                actionLabel: typeFilter == .all && searchText.isEmpty ? "New Channel" : nil,
                helpLabel: "Learn how channels work",
                helpAction: { activeSheet = .help }
            ) {
                activeSheet = .createChannel
            }
        } else {
            List {
                Section {
                    smartCardFilters
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                ForEach(filteredItems) { item in
                    NavigationLink {
                        IOSMessageThreadView(
                            channelId: item.id,
                            channelName: item.channelName
                        )
                        .environmentObject(appCore)
                    } label: {
                        inboxRow(item)
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    private var emptyChannelsMessage: String {
        if typeFilter == .all && searchText.isEmpty {
            return "Create a channel or direct message to start team conversations."
        }
        return "No conversations match your current search, date range, or filter."
    }

    // MARK: - Inbox Row

    private func inboxRow(_ item: ChatService.InboxItem) -> some View {
        HStack(spacing: 12) {
            // Type icon with optional office badge
            ZStack(alignment: .topTrailing) {
                Image(systemName: iconForChannelType(item.channelType))
                    .font(.title2)
                    .foregroundStyle(colorForChannelType(item.channelType))
                    .frame(width: 36)
                    .accessibilityHidden(true)

                if item.channelType == "office" {
                    Text("Office")
                        .font(.caption2).bold()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(.purple)
                        .clipShape(Capsule())
                        .offset(x: 6, y: -4)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.channelName)
                        .font(.body)
                        .fontWeight(item.unreadCount > 0 ? .bold : .regular)
                        .lineLimit(1)

                    if item.hasPinnedMessages {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                            .accessibilityLabel("Pinned")
                    }

                    if ["rfi", "jpo_hold"].contains(item.channelType) {
                        Text(item.channelType == "rfi" ? "RFI" : "HOLD")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(item.channelType == "rfi" ? .blue : .orange)
                            .clipShape(Capsule())
                    }

                    Text(labelForChannelType(item.channelType))
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(colorForChannelType(item.channelType))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(colorForChannelType(item.channelType).opacity(0.12))
                        .clipShape(Capsule())
                        .lineLimit(1)

                    if let jobName = item.jobName, !jobName.isEmpty, item.channelType != "job" {
                        Text(jobName)
                            .font(.caption2)
                            .foregroundStyle(.blue)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.blue.opacity(0.1))
                            .clipShape(Capsule())
                            .lineLimit(1)
                    }
                }

                HStack(spacing: 4) {
                    if let sender = item.lastMessageBy {
                        Text("\(sender):")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fontWeight(.medium)
                    }
                    Text(item.lastMessagePreview)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                if let dateStr = item.lastMessageDate, !dateStr.isEmpty {
                    Text(formatRelativeDate(dateStr))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if item.unreadCount > 0 {
                    Text("\(item.unreadCount)")
                        .font(.caption2).bold()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.red)
                        .clipShape(Capsule())
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Helpers

    private func iconForChannelType(_ type: String) -> String {
        switch type {
        case "office": return "building.columns.fill"
        case "dm": return "person.circle"
        case "job": return "hammer.circle"
        case "group", "message": return "person.3"
        case "supplier": return "shippingbox.circle"
        case "qa": return "questionmark.circle"
        case "rfi": return "doc.text.magnifyingglass"
        case "jpo_hold": return "pause.circle.fill"
        case "jpo_qa": return "questionmark.bubble"
        default: return "bubble.left.and.bubble.right"
        }
    }

    private func labelForChannelType(_ type: String) -> String {
        switch type {
        case "office": return "Office"
        case "dm": return "DM"
        case "job": return "Job"
        case "group", "message": return "Message"
        case "supplier": return "Supplier"
        case "qa": return "Q&A"
        case "rfi": return "RFI"
        case "jpo_hold": return "JPO Hold"
        case "jpo_qa": return "JPO Q&A"
        default: return type.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private func colorForChannelType(_ type: String) -> Color {
        switch type {
        case "office": return .purple
        case "dm": return .purple
        case "job": return .blue
        case "group", "message": return .green
        case "supplier": return .teal
        case "qa": return .orange
        case "rfi": return .indigo
        case "jpo_hold": return .orange
        case "jpo_qa": return .orange
        default: return .accentColor
        }
    }

    private func formatRelativeDate(_ iso: String) -> String {
        // Simplified: show time if today, date if older
        guard iso.count >= 16 else { return iso }
        let todayPrefix = String(Formatters.iso8601Basic.string(from: Date()).prefix(10))
        if iso.hasPrefix(todayPrefix) {
            let start = iso.index(iso.startIndex, offsetBy: 11)
            let end = iso.index(iso.startIndex, offsetBy: 16)
            return String(iso[start..<end])
        } else if iso.count >= 10 {
            return String(iso.prefix(10))
        }
        return iso
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let service = appCore.chatService else {
            loadError = "Chat service unavailable"
            isLoading = false
            return
        }
        guard let userId = appCore.currentUser?.id else {
            loadError = "Not logged in"
            isLoading = false
            return
        }
        isLoading = inboxItems.isEmpty
        loadError = nil
        do {
            inboxItems = try service.getUnifiedInbox(userId: userId)
        } catch {
            loadError = userFriendlyError(error, context: "load channels")
        }
        isLoading = false
    }
}

import SwiftUI
import WiredPartCore

/// Full message thread view for a chat channel.
///
/// Displays messages in a scrollable list with send capability.
/// Messages are shown in a bubble-style layout with sender name and timestamp.
/// Includes an expandable info panel showing source context, people, and quick actions.
/// Supports photo, file, and reference attachments.
struct IOSMessageThreadView: View {
    @EnvironmentObject private var appCore: AppCore

    let channelId: Int64
    let channelName: String

    @State private var messages: [ChatService.MessageRow] = []
    @State private var messageAttachments: [Int64: [ChatService.MessageAttachment]] = [:]
    @State private var isLoading = true
    @State private var messageText = ""
    @State private var isSending = false
    @State private var loadError: String?
    @State private var actionError: String?

    // Thread info panel
    @State private var showInfoPanel = false
    @State private var threadInfo: ChatService.ThreadInfo?

    // Attachments
    @State private var pendingAttachments: [ChatService.PendingAttachment] = []
    @State private var showPhotoPicker = false
    @State private var showReferencePicker = false
    @State private var activeSheet: ActiveSheet?

    private enum ActiveSheet: Identifiable {
        case help
        var id: String { "help" }
    }

    private enum ReferenceType: String {
        case part = "part_ref"
        case po = "po_ref"
        case job = "job_ref"
    }
    @State private var selectedReferenceType: ReferenceType?

    // Toast
    @State private var showComingSoon = false

    var body: some View {
        VStack(spacing: 0) {
            // Expandable header + info panel
            threadHeader

            // Messages
            messageList

            Divider()

            // Pending attachments preview
            if !pendingAttachments.isEmpty {
                pendingAttachmentsBar
            }

            // Attachment buttons + composer
            attachmentBar
            messageComposer
        }
        .navigationTitle(channelName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
            }
        }
        .sheet(item: $activeSheet) { _ in
            PageHelpSheet(
                title: "Message Thread Help",
                sections: [
                    ("What This Page Does", "This is a live conversation thread. You can read messages, send replies, and attach photos, files, or references to parts, POs, and jobs. The info panel at the top shows who is in the conversation and what it is linked to."),
                    ("How to Use It", "Type your message in the text field at the bottom and tap the send button. Messages appear in bubbles -- yours on the right (blue), others on the left (gray). Scroll up to see older messages."),
                    ("Attachments", "Use the icons below the message list to attach a photo, a file, or a reference link. Reference links can point to a specific part, purchase order, or job so everyone in the thread can jump to that item."),
                    ("Info Panel", "Tap the channel name header at the top to expand the info panel. It shows the source context (which job, PO, or supplier the thread is linked to), the people in the conversation, and quick action buttons like Escalate or Resolve."),
                    ("Tips", "Pending attachments show as blue chips above the composer before you send. Tap the X on any chip to remove it. Photos and file attachments are automatically saved to the linked job's notebook for future reference.")
                ]
            )
        }
        .task {
            loadMessages()
            loadThreadInfo()
        }
        .alert("Send Failed", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
            Button("OK") { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
        .overlay(alignment: .bottom) {
            if showComingSoon {
                Text("File attachments coming in a future update")
                    .font(.subheadline)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
                    .cornerRadius(8)
                    .padding(.bottom, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            withAnimation { showComingSoon = false }
                        }
                    }
            }
        }
    }

    // MARK: - Thread Header + Info Panel

    private var threadHeader: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    showInfoPanel.toggle()
                }
            } label: {
                HStack {
                    Text(channelName).font(.headline)
                    Spacer()
                    Image(systemName: showInfoPanel ? "chevron.up" : "info.circle")
                        .foregroundStyle(.blue)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)

            if showInfoPanel, let info = threadInfo {
                ThreadInfoPanel(info: info, onAction: handleAction)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            Divider()
        }
    }

    // MARK: - Message List

    @ViewBuilder
    private var messageList: some View {
        if isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = loadError {
            ErrorStateView(message: error) { loadMessages() }
        } else if messages.isEmpty {
            EmptyStateView(
                icon: "bubble.left.and.bubble.right",
                title: "No Messages",
                message: "Start the conversation by sending a message below."
            )
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(messages) { message in
                            VStack(alignment: message.senderId == appCore.currentUser?.id ? .trailing : .leading, spacing: 4) {
                                IOSMessageBubble(
                                    message: message,
                                    isCurrentUser: message.senderId == appCore.currentUser?.id
                                )

                                // Display attachments for this message
                                if let attachments = messageAttachments[message.id], !attachments.isEmpty {
                                    ForEach(attachments) { attachment in
                                        AttachmentDisplay(attachment: attachment)
                                    }
                                }
                            }
                            .id(message.id)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
                .onChange(of: messages.count) {
                    if let last = messages.last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Attachment Bar

    private var attachmentBar: some View {
        HStack(spacing: 16) {
            // Photo button
            Button { showPhotoPicker = true } label: {
                Image(systemName: "photo")
                    .foregroundStyle(.blue)
            }

            // File button
            Button { withAnimation { showComingSoon = true } } label: {
                Image(systemName: "doc")
                    .foregroundStyle(.blue)
            }

            // Reference button (part/PO/job)
            Menu {
                Button {
                    selectedReferenceType = .part
                    showReferencePicker = true
                } label: {
                    Label("Part Reference", systemImage: "shippingbox")
                }
                Button {
                    selectedReferenceType = .po
                    showReferencePicker = true
                } label: {
                    Label("PO Reference", systemImage: "doc.text")
                }
                Button {
                    selectedReferenceType = .job
                    showReferencePicker = true
                } label: {
                    Label("Job Reference", systemImage: "wrench.and.screwdriver")
                }
            } label: {
                Image(systemName: "link")
                    .foregroundStyle(.blue)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
    }

    // MARK: - Pending Attachments Preview

    private var pendingAttachmentsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(pendingAttachments.enumerated()), id: \.offset) { idx, att in
                    HStack(spacing: 4) {
                        Image(systemName: iconForAttachmentType(att.type))
                            .font(.caption)
                        Text(att.referenceLabel ?? att.fileName ?? att.type)
                            .font(.caption)
                            .lineLimit(1)
                        Button {
                            pendingAttachments.remove(at: idx)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.1))
                    .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
    }

    // MARK: - Composer

    private var messageComposer: some View {
        HStack(spacing: 8) {
            TextField("Message...", text: $messageText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
                .onSubmit { sendMessage() }

            Button {
                sendMessage()
            } label: {
                if isSending {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                }
            }
            .disabled(messageText.trimmingCharacters(in: .whitespaces).isEmpty && pendingAttachments.isEmpty || isSending)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground))
    }

    // MARK: - Actions

    private func loadMessages() {
        guard let service = appCore.chatService else {
            loadError = "Chat service unavailable"
            isLoading = false
            return
        }
        isLoading = messages.isEmpty
        loadError = nil
        do {
            messages = try service.getMessages(channelId: channelId)

            // Batch-load attachments for all messages
            let ids = messages.map(\.id)
            messageAttachments = try service.getAttachmentsForMessages(messageIds: ids)
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    private func loadThreadInfo() {
        guard let service = appCore.chatService else {
            loadError = "Chat service not available"
            isLoading = false
            return
        }
        do {
            threadInfo = try service.getThreadInfo(channelId: channelId)
        } catch {
            // Non-fatal — panel just won't show content
        }
    }

    private func sendMessage() {
        guard let service = appCore.chatService,
              let userId = appCore.currentUser?.id else {
            actionError = "Chat service unavailable"
            return
        }
        let text = messageText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty || !pendingAttachments.isEmpty else { return }

        isSending = true
        do {
            if pendingAttachments.isEmpty {
                _ = try service.sendMessage(channelId: channelId, senderId: userId, content: text)
            } else {
                let msgId = try service.sendMessageWithAttachments(
                    channelId: channelId,
                    content: text,
                    userId: userId,
                    attachments: pendingAttachments
                )

                // Auto-save photo/file attachments to job notebook (best effort)
                for att in pendingAttachments where att.type == "photo" || att.type == "file" {
                    if let attachments = try? service.getMessageAttachments(messageId: msgId),
                       let saved = attachments.first(where: { $0.attachmentType == att.type }) {
                        try? service.autoSaveToJobNotebook(channelId: channelId, attachment: saved)
                    }
                }
            }
            messageText = ""
            pendingAttachments = []
            loadMessages()
        } catch {
            actionError = error.localizedDescription
        }
        isSending = false
    }

    private func handleAction(_ action: ChatService.ThreadAction) {
        guard let service = appCore.chatService,
              let userId = appCore.currentUser?.id else {
            actionError = "Chat service unavailable"
            return
        }

        switch action {
        case .markResolved:
            do {
                let threads = try service.listQAThreads()
                if let thread = threads.first(where: { _ in true }) {
                    try service.resolveQAThread(threadId: thread.id, resolvedBy: userId)
                    loadThreadInfo()
                }
            } catch {
                actionError = error.localizedDescription
            }
        case .addPeople, .escalate, .pushBack, .approve, .reject:
            break // Wired in later prompts (42D)
        }
    }

    private func iconForAttachmentType(_ type: String) -> String {
        switch type {
        case "photo": return "photo"
        case "file": return "doc"
        case "part_ref": return "shippingbox.fill"
        case "po_ref": return "doc.text.fill"
        case "job_ref": return "wrench.and.screwdriver"
        case "jpo_ref": return "doc.plaintext.fill"
        default: return "paperclip"
        }
    }
}

// MARK: - Attachment Display in Bubbles

/// Renders a single attachment inline in a message bubble.
struct AttachmentDisplay: View {
    let attachment: ChatService.MessageAttachment

    var body: some View {
        switch attachment.attachmentType {
        case "part_ref":
            HStack {
                Image(systemName: "shippingbox.fill")
                    .foregroundStyle(.blue)
                Text(attachment.referenceLabel ?? "Part")
                    .foregroundStyle(.blue)
                    .underline()
            }
            .font(.caption)
            .padding(6)
            .background(.blue.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 6))

        case "photo":
            if let path = attachment.filePath {
                AsyncImage(url: URL(fileURLWithPath: path)) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                        .frame(maxWidth: 200, maxHeight: 150)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } placeholder: {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 100, height: 75)
                        .overlay {
                            Image(systemName: "photo")
                                .foregroundStyle(.secondary)
                        }
                }
            }

        case "po_ref", "job_ref", "jpo_ref":
            HStack {
                Image(systemName: iconForRefType(attachment.attachmentType))
                    .foregroundStyle(.orange)
                Text(attachment.referenceLabel ?? "Reference")
                    .font(.caption)
            }
            .padding(6)
            .background(.orange.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 6))

        default:
            // File attachment
            HStack {
                Image(systemName: "doc")
                Text(attachment.fileName ?? "File")
                    .font(.caption)
            }
            .padding(6)
            .background(Color(.tertiarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private func iconForRefType(_ type: String) -> String {
        switch type {
        case "po_ref": return "doc.text"
        case "job_ref": return "wrench.and.screwdriver"
        case "jpo_ref": return "doc.plaintext"
        default: return "link"
        }
    }
}

// MARK: - Thread Info Panel

/// Expandable inline panel showing thread context, people, and quick actions.
struct ThreadInfoPanel: View {
    let info: ChatService.ThreadInfo
    let onAction: (ChatService.ThreadAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Source Context
            if let sourceName = info.sourceName, let sourceType = info.sourceType {
                HStack {
                    Image(systemName: sourceIcon(sourceType))
                        .foregroundStyle(.blue)
                    VStack(alignment: .leading) {
                        Text(sourceLabel(sourceType))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(sourceName)
                            .font(.subheadline)
                    }
                }
                .padding(.horizontal)
            }

            // Escalation level (Q&A/RFI only)
            if let level = info.escalationLevel {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.up.arrow.down.circle")
                        .foregroundStyle(.orange)
                    Text("Escalation Level:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(level.capitalized)
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    if info.canEscalate {
                        Image(systemName: "arrow.up.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    }
                    if info.canPushBack {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundStyle(.orange)
                            .font(.caption)
                    }
                }
                .padding(.horizontal)
            }

            // People
            VStack(alignment: .leading, spacing: 4) {
                Text("People (\(info.members.count))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                ForEach(info.members) { member in
                    HStack {
                        Text(member.name)
                            .font(.subheadline)
                        Spacer()
                        Text(member.role ?? "Member")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                }
            }

            // Quick Actions
            if !info.availableActions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(info.availableActions) { action in
                            Button {
                                onAction(action)
                            } label: {
                                Label(actionLabel(action), systemImage: actionIcon(action))
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .tint(actionColor(action))
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    private func sourceIcon(_ type: String) -> String {
        switch type {
        case "jpo": return "doc.plaintext"
        case "po": return "shippingbox"
        case "job": return "wrench.and.screwdriver"
        case "supplier": return "building.2"
        default: return "bubble.left"
        }
    }

    private func sourceLabel(_ type: String) -> String {
        switch type {
        case "jpo": return "Job Parts Order"
        case "po": return "Purchase Order"
        case "job": return "Job"
        case "supplier": return "Supplier"
        default: return "Source"
        }
    }

    private func actionLabel(_ action: ChatService.ThreadAction) -> String {
        switch action {
        case .approve: return "Approve"
        case .reject: return "Reject"
        case .escalate: return "Escalate"
        case .pushBack: return "Push Back"
        case .markResolved: return "Resolve"
        case .addPeople: return "Add People"
        }
    }

    private func actionIcon(_ action: ChatService.ThreadAction) -> String {
        switch action {
        case .approve: return "checkmark.circle"
        case .reject: return "xmark.circle"
        case .escalate: return "arrow.up.circle"
        case .pushBack: return "arrow.down.circle"
        case .markResolved: return "checkmark.seal"
        case .addPeople: return "person.badge.plus"
        }
    }

    private func actionColor(_ action: ChatService.ThreadAction) -> Color {
        switch action {
        case .approve: return .green
        case .reject: return .red
        case .escalate: return .blue
        case .pushBack: return .orange
        case .markResolved: return .green
        case .addPeople: return .blue
        }
    }
}

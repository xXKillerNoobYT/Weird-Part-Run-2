import SwiftUI
import WiredPartCore

/// Full message thread view for a chat channel.
///
/// Displays messages in a scrollable list with send capability.
/// Messages are shown in a bubble-style layout with sender name and timestamp.
struct IOSMessageThreadView: View {
    @EnvironmentObject private var appCore: AppCore

    let channelId: Int64
    let channelName: String

    @State private var messages: [ChatService.MessageRow] = []
    @State private var isLoading = true
    @State private var messageText = ""
    @State private var isSending = false
    @State private var loadError: String?
    @State private var actionError: String?

    var body: some View {
        VStack(spacing: 0) {
            // Messages
            messageList

            Divider()

            // Composer
            messageComposer
        }
        .navigationTitle(channelName)
        .navigationBarTitleDisplayMode(.inline)
        .task { loadMessages() }
        .alert("Send Failed", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
            Button("OK") { actionError = nil }
        } message: {
            Text(actionError ?? "")
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
                            IOSMessageBubble(
                                message: message,
                                isCurrentUser: message.senderId == appCore.currentUser?.id
                            )
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
            .disabled(messageText.trimmingCharacters(in: .whitespaces).isEmpty || isSending)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground))
    }

    // MARK: - Actions

    private func loadMessages() {
        guard let service = appCore.chatService else { return }
        isLoading = messages.isEmpty
        loadError = nil
        do {
            messages = try service.getMessages(channelId: channelId)
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    private func sendMessage() {
        guard let service = appCore.chatService,
              let userId = appCore.currentUser?.id else { return }
        let text = messageText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }

        isSending = true
        do {
            _ = try service.sendMessage(channelId: channelId, senderId: userId, content: text)
            messageText = ""
            loadMessages()
        } catch {
            actionError = error.localizedDescription
        }
        isSending = false
    }
}

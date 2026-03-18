import SwiftUI
import WiredPartCore

/// Single message bubble in a chat thread.
///
/// Shows sender name, message content, and timestamp.
/// Current user's messages are right-aligned with accent color;
/// others are left-aligned with secondary background.
struct IOSMessageBubble: View {
    let message: ChatService.MessageRow
    let isCurrentUser: Bool

    var body: some View {
        HStack {
            if isCurrentUser { Spacer(minLength: 60) }

            VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: 4) {
                if !isCurrentUser {
                    Text(message.senderName)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                }

                Text(message.content)
                    .font(.body)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(isCurrentUser ? Color.accentColor : Color.secondary.opacity(0.15))
                    )
                    .foregroundStyle(isCurrentUser ? .white : .primary)

                if let time = message.createdAt, !time.isEmpty {
                    Text(formatTime(time))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            if !isCurrentUser { Spacer(minLength: 60) }
        }
    }

    private func formatTime(_ dateString: String) -> String {
        // Simple time extraction from ISO date string
        if dateString.count >= 16 {
            let start = dateString.index(dateString.startIndex, offsetBy: 11)
            let end = dateString.index(start, offsetBy: 5)
            return String(dateString[start..<end])
        }
        return dateString
    }
}

import SwiftUI
import WiredPartCore

/// Visual timeline showing the escalation chain for a Q&A thread.
///
/// Displays each escalation level with who was asked, when, and
/// whether they answered or escalated further.
struct IOSEscalationTimeline: View {
    let thread: ChatService.QAThreadRow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Question
            TimelineNode(
                icon: "questionmark.circle.fill",
                color: .blue,
                title: "Question Asked",
                subtitle: thread.askedByName,
                detail: thread.question,
                isFirst: true,
                isLast: false
            )

            // Current Level
            TimelineNode(
                icon: levelIcon(thread.currentLevel),
                color: levelColor(thread.currentLevel),
                title: "Level: \(thread.currentLevel.capitalized)",
                subtitle: "Status: \(thread.status.capitalized)",
                detail: nil,
                isFirst: false,
                isLast: thread.answer == nil
            )

            // Answer (if exists)
            if let answer = thread.answer {
                TimelineNode(
                    icon: "checkmark.circle.fill",
                    color: .green,
                    title: "Answered",
                    subtitle: thread.answeredByName ?? "Unknown",
                    detail: answer,
                    isFirst: false,
                    isLast: true
                )
            }
        }
        .padding()
    }

    private func levelIcon(_ level: String) -> String {
        switch level {
        case "lead": return "person.fill"
        case "foreman": return "person.badge.shield.checkmark.fill"
        case "pm": return "person.crop.circle.badge.checkmark"
        case "office": return "building.2.fill"
        default: return "arrow.up.circle.fill"
        }
    }

    private func levelColor(_ level: String) -> Color {
        switch level {
        case "lead": .blue
        case "foreman": .orange
        case "pm": .purple
        case "office": .red
        default: .secondary
        }
    }
}

// MARK: - Timeline Node

private struct TimelineNode: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String
    let detail: String?
    let isFirst: Bool
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Timeline line + dot
            VStack(spacing: 0) {
                if !isFirst {
                    Rectangle()
                        .fill(color.opacity(0.3))
                        .frame(width: 2, height: 16)
                }
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(color)
                    .frame(width: 24, height: 24)
                if !isLast {
                    Rectangle()
                        .fill(color.opacity(0.3))
                        .frame(width: 2, height: 16)
                }
            }
            .frame(width: 24)

            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.secondary.opacity(0.1))
                        )
                }
            }
            .padding(.vertical, 4)
        }
    }
}

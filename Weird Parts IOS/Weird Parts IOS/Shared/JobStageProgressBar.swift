import SwiftUI
import WiredPartCore

/// A visual progression bar showing job stages (Rough-in, Prep/Makeup, Trim-out).
///
/// Displays connected circles with status colors and optional labels.
/// Use `compact: true` for list rows, `compact: false` for detail views.
struct JobStageProgressBar: View {
    let stages: [JobsService.JobStageStatus]
    var compact: Bool = false

    var body: some View {
        if stages.isEmpty {
            // No stages configured — show nothing
            EmptyView()
        } else {
            HStack(spacing: 0) {
                ForEach(Array(stages.enumerated()), id: \.element.id) { index, stage in
                    stageNode(stage, index: index)

                    if index < stages.count - 1 {
                        connector(completed: stage.status == "completed")
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityDescription)
        }
    }

    // MARK: - Stage Node

    private func stageNode(_ stage: JobsService.JobStageStatus, index: Int) -> some View {
        VStack(spacing: compact ? 2 : 4) {
            ZStack {
                Circle()
                    .fill(stageColor(stage))
                    .frame(
                        width: compact ? 12 : 20,
                        height: compact ? 12 : 20
                    )

                if stage.status == "completed" {
                    Image(systemName: "checkmark")
                        .font(.system(size: compact ? 6 : 10, weight: .bold))
                        .foregroundStyle(.white)
                } else if stage.status == "in_progress" {
                    Circle()
                        .fill(.white)
                        .frame(
                            width: compact ? 4 : 6,
                            height: compact ? 4 : 6
                        )
                }
            }

            if !compact {
                Text(stage.name)
                    .font(.system(size: 9, weight: stage.status == "in_progress" ? .semibold : .regular))
                    .foregroundStyle(stage.status == "pending" ? .tertiary : .secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
    }

    // MARK: - Connector

    private func connector(completed: Bool) -> some View {
        Rectangle()
            .fill(completed ? Color.green : Color.secondary.opacity(0.25))
            .frame(height: compact ? 2 : 3)
            .frame(maxWidth: compact ? 10 : .infinity)
            .offset(y: compact ? 0 : (stageHasLabels ? -10 : 0))
    }

    private var stageHasLabels: Bool { !compact }

    // MARK: - Colors

    private func stageColor(_ stage: JobsService.JobStageStatus) -> Color {
        switch stage.status {
        case "completed":
            return .green
        case "in_progress":
            return .blue
        default:
            return Color.secondary.opacity(0.25)
        }
    }

    // MARK: - Accessibility

    private var accessibilityDescription: String {
        let completed = stages.filter { $0.status == "completed" }.count
        let total = stages.count
        let current = stages.first(where: { $0.status == "in_progress" })?.name
        if let current {
            return "Stage \(completed + 1) of \(total): \(current) in progress"
        } else if completed == total {
            return "All \(total) stages completed"
        } else {
            return "\(completed) of \(total) stages completed"
        }
    }
}

// MARK: - Preview

#Preview("Full") {
    VStack(spacing: 20) {
        JobStageProgressBar(
            stages: [
                .init(id: 1, name: "Rough-in", sortOrder: 1, status: "completed"),
                .init(id: 2, name: "Prep/Makeup", sortOrder: 2, status: "in_progress"),
                .init(id: 3, name: "Trim-out", sortOrder: 3, status: "pending"),
            ],
            compact: false
        )

        JobStageProgressBar(
            stages: [
                .init(id: 1, name: "Rough-in", sortOrder: 1, status: "completed"),
                .init(id: 2, name: "Prep/Makeup", sortOrder: 2, status: "completed"),
                .init(id: 3, name: "Trim-out", sortOrder: 3, status: "completed"),
            ],
            compact: false
        )

        JobStageProgressBar(
            stages: [
                .init(id: 1, name: "Rough-in", sortOrder: 1, status: "pending"),
                .init(id: 2, name: "Prep/Makeup", sortOrder: 2, status: "pending"),
                .init(id: 3, name: "Trim-out", sortOrder: 3, status: "pending"),
            ],
            compact: false
        )
    }
    .padding()
}

#Preview("Compact") {
    VStack(spacing: 12) {
        JobStageProgressBar(
            stages: [
                .init(id: 1, name: "Rough-in", sortOrder: 1, status: "completed"),
                .init(id: 2, name: "Prep/Makeup", sortOrder: 2, status: "in_progress"),
                .init(id: 3, name: "Trim-out", sortOrder: 3, status: "pending"),
            ],
            compact: true
        )

        JobStageProgressBar(
            stages: [
                .init(id: 1, name: "Rough-in", sortOrder: 1, status: "completed"),
                .init(id: 2, name: "Prep/Makeup", sortOrder: 2, status: "completed"),
                .init(id: 3, name: "Trim-out", sortOrder: 3, status: "completed"),
            ],
            compact: true
        )
    }
    .padding()
}

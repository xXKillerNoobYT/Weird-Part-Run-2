import SwiftUI
import WiredPartCore

/// A visual progression bar showing the ordered stages assigned to a job.
///
/// Handles one, two, default three-stage, five-stage, and many-stage templates.
/// Detail mode labels up to five stages; larger workflows use compact chips to
/// avoid unreadable overlap while preserving an accessible combined summary.
struct JobStageProgressBar: View {
    let stages: [JobsService.JobStageStatus]
    var compact: Bool = false

    var body: some View {
        if stages.isEmpty {
            // No stages configured — show nothing
            EmptyView()
        } else if compact || stages.count <= 5 {
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
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(stages.enumerated()), id: \.element.id) { index, stage in
                        manyStageChip(stage, index: index)
                    }
                }
                .padding(.vertical, 2)
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
                        .font(compact ? .system(.caption2, weight: .bold) : .system(.caption, weight: .bold))
                        .minimumScaleFactor(0.5)
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
                    .font(.caption).fontWeight(stage.status == "in_progress" ? .semibold : .regular)
                    .foregroundStyle(stage.status == "pending" ? .tertiary : .secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
    }

    // MARK: - Many Stage Chip

    private func manyStageChip(_ stage: JobsService.JobStageStatus, index: Int) -> some View {
        HStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(stageColor(stage))
                    .frame(width: 18, height: 18)
                if stage.status == "completed" {
                    Image(systemName: "checkmark")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                } else {
                    Text("\(index + 1)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(stage.status == "in_progress" ? Color.white : Color.secondary)
                }
            }
            Text(stage.name)
                .font(.caption)
                .fontWeight(stage.status == "in_progress" ? .semibold : .regular)
                .foregroundStyle(stage.status == "pending" ? .secondary : .primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(stage.status == "in_progress" ? Color.blue.opacity(0.12) : Color.secondary.opacity(0.08), in: Capsule())
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

        JobStageProgressBar(
            stages: [
                .init(id: 1, name: "Visit", sortOrder: 1, status: "in_progress"),
            ],
            compact: false
        )

        JobStageProgressBar(
            stages: [
                .init(id: 1, name: "Rough-in", sortOrder: 1, status: "completed"),
                .init(id: 2, name: "Inspection", sortOrder: 2, status: "completed"),
                .init(id: 3, name: "Makeup", sortOrder: 3, status: "in_progress"),
                .init(id: 4, name: "Trim-out", sortOrder: 4, status: "pending"),
                .init(id: 5, name: "Punch List", sortOrder: 5, status: "pending"),
            ],
            compact: false
        )

        JobStageProgressBar(
            stages: [
                .init(id: 1, name: "Underground", sortOrder: 1, status: "completed"),
                .init(id: 2, name: "Rough-in", sortOrder: 2, status: "completed"),
                .init(id: 3, name: "Inspection", sortOrder: 3, status: "completed"),
                .init(id: 4, name: "Makeup", sortOrder: 4, status: "in_progress"),
                .init(id: 5, name: "Above Ceiling", sortOrder: 5, status: "pending"),
                .init(id: 6, name: "Trim", sortOrder: 6, status: "pending"),
                .init(id: 7, name: "Commission", sortOrder: 7, status: "pending"),
                .init(id: 8, name: "Closeout", sortOrder: 8, status: "pending"),
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

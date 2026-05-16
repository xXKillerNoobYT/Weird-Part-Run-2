import SwiftUI

/// Per-page onboarding banner showing guided tasks.
/// Only visible when the onboarding tour is active and the page has incomplete tasks.
struct OnboardingBanner: View {
    let pageId: String
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if let onboardingManager = appCore.onboardingManager {
            let permissions = appCore.permissions
            let tasks = onboardingManager.tasksForPage(pageId, permissions: permissions)
            let incomplete = tasks.filter { !onboardingManager.isCompleted($0.id) }

            if onboardingManager.isOnboardingActive && !tasks.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "graduationcap.fill")
                        .foregroundStyle(.blue)
                    Text("Try This")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Spacer()
                    Text("\(tasks.count - incomplete.count)/\(tasks.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Show incomplete tasks first
                ForEach(incomplete) { task in
                    HStack(spacing: 8) {
                        Image(systemName: task.isRequired ? "circle" : "circle.dashed")
                            .font(.caption)
                            .foregroundStyle(task.isRequired ? .blue : .secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(task.title)
                                .font(.caption)
                                .fontWeight(.medium)
                                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(task.description)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                // Show completed tasks with checkmarks
                let completed = tasks.filter { onboardingManager.isCompleted($0.id) }
                if !completed.isEmpty {
                    ForEach(completed) { task in
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                            Text(task.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .strikethrough()
                                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(12)
            .background(Color.blue.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal)
            }
        }
    }
}

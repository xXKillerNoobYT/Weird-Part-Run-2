import SwiftUI

/// Per-page onboarding banner showing guided tasks.
/// Only visible when the onboarding tour is active and the page has incomplete tasks.
struct OnboardingBanner: View {
    let pageId: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var appCore: AppCore

    var body: some View {
        if let onboardingManager = appCore.onboardingManager {
            let permissions = appCore.permissions
            let tasks = onboardingManager.tasksForPage(pageId, permissions: permissions)
            let incomplete = tasks.filter { !onboardingManager.isCompleted($0.id) }

            if onboardingManager.isOnboardingActive && !tasks.isEmpty {
                let requiredTasks = tasks.filter { $0.isRequired }
                let requiredComplete = !requiredTasks.isEmpty && requiredTasks.allSatisfy { onboardingManager.isCompleted($0.id) }
                let completed = tasks.filter { onboardingManager.isCompleted($0.id) }

                if requiredComplete {
                    HStack(alignment: dynamicTypeSize.isAccessibilitySize ? .top : .center, spacing: 10) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Required tour steps complete")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("\(completed.count)/\(tasks.count) tour steps done")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                    }
                    .padding(12)
                    .background(Color.green.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Required tour steps complete, \(completed.count) of \(tasks.count) tour steps done")
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: dynamicTypeSize.isAccessibilitySize ? .top : .center) {
                            Image(systemName: "graduationcap.fill")
                                .foregroundStyle(.blue)
                                .accessibilityHidden(true)
                            Text("Try This")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer()
                            Text("\(completed.count)/\(tasks.count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        // Show incomplete tasks first
                        ForEach(incomplete) { task in
                            HStack(alignment: dynamicTypeSize.isAccessibilitySize ? .top : .center, spacing: 8) {
                                Image(systemName: task.isRequired ? "circle" : "circle.dashed")
                                    .font(.caption)
                                    .foregroundStyle(task.isRequired ? .blue : .secondary)
                                    .padding(.top, dynamicTypeSize.isAccessibilitySize ? 4 : 0)
                                    .accessibilityHidden(true)
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
                                Spacer(minLength: 0)
                            }
                        }

                        // Show completed tasks with checkmarks
                        if !completed.isEmpty {
                            ForEach(completed) { task in
                                HStack(alignment: dynamicTypeSize.isAccessibilitySize ? .top : .center, spacing: 8) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(.green)
                                        .padding(.top, dynamicTypeSize.isAccessibilitySize ? 4 : 0)
                                        .accessibilityHidden(true)
                                    Text(task.title)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .strikethrough()
                                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Spacer(minLength: 0)
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
}

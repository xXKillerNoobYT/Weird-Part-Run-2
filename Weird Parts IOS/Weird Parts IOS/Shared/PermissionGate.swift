import SwiftUI

/// ViewModifier-based permission enforcement for inline UI gating.
///
/// Usage:
///   Button("Delete") { ... }
///       .requiresPermission("manage_jobs")     // Grays out + disabled if no permission
///
///   Button("Edit") { ... }
///       .hideWithoutPermission("edit_parts")    // Completely hidden if no permission
///
/// Works by reading the current user's permissions from `AppCore` via
/// the environment. Module/tab-level gating is handled by `NavigationConfig`;
/// these modifiers are for inline elements within pages.

// MARK: - Requires Permission (disable + gray out)

private struct RequiresPermissionModifier: ViewModifier {
    @EnvironmentObject private var appCore: AppCore

    let permissionKey: String
    let showLockIcon: Bool

    private var hasPermission: Bool {
        appCore.hasPermission(permissionKey)
    }

    func body(content: Content) -> some View {
        if showLockIcon && !hasPermission {
            HStack(spacing: 4) {
                content
                Image(systemName: "lock.fill")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .disabled(true)
            .opacity(0.5)
        } else {
            content
                .disabled(!hasPermission)
                .opacity(hasPermission ? 1.0 : 0.5)
        }
    }
}

// MARK: - Hide Without Permission (completely removed)

private struct HideWithoutPermissionModifier: ViewModifier {
    @EnvironmentObject private var appCore: AppCore

    let permissionKey: String

    private var hasPermission: Bool {
        appCore.hasPermission(permissionKey)
    }

    func body(content: Content) -> some View {
        if hasPermission {
            content
        }
    }
}

// MARK: - View Extensions

extension View {
    /// Disables and dims the view if the user lacks the given permission.
    /// Optionally shows a lock icon next to the content.
    func requiresPermission(_ key: String, showLock: Bool = false) -> some View {
        modifier(RequiresPermissionModifier(permissionKey: key, showLockIcon: showLock))
    }

    /// Completely hides the view if the user lacks the given permission.
    func hideWithoutPermission(_ key: String) -> some View {
        modifier(HideWithoutPermissionModifier(permissionKey: key))
    }
}

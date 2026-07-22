import Combine
import Foundation
import SwiftUI

/// Central registry for AI-activated filters across all pages.
///
/// Pages register their available filters on appear and deregister on disappear.
/// The AI can activate a filter by page ID, and the page picks it up via its
/// registered closure. If the target page is not currently active, the request
/// is queued as a pending filter and applied automatically when the page appears.
///
/// Usage from a page:
/// ```swift
/// .onAppear {
///     appCore.aiFilterRegistry.register(
///         pageId: "purchase-orders",
///         filterName: "PO Status",
///         options: statusOptions,
///         activate: { value in statusFilter = value }
///     )
///     appCore.aiFilterRegistry.applyPendingFilter(pageId: "purchase-orders")
/// }
/// .onDisappear {
///     appCore.aiFilterRegistry.deregister(pageId: "purchase-orders")
/// }
/// ```
@MainActor
class AIFilterRegistry: ObservableObject {
    static let shared = AIFilterRegistry()

    // MARK: - Types

    struct FilterRegistration {
        let pageId: String
        let filterName: String
        let options: [String]
        let activate: (String) -> Void
    }

    // MARK: - State

    /// Currently registered page filters, keyed by page ID.
    @Published private(set) var registrations: [String: FilterRegistration] = [:]

    /// A pending filter request for a page that wasn't active when the AI made the request.
    /// Consumed automatically when the target page calls `applyPendingFilter`.
    @Published var pendingFilter: (pageId: String, value: String)?

    // MARK: - Registration

    /// Register a page's filter so the AI can activate it.
    /// - Parameters:
    ///   - pageId: Unique identifier for the page (e.g. "purchase-orders").
    ///   - filterName: Human-readable name of the filter (e.g. "PO Status").
    ///   - options: The available filter values (e.g. ["all", "draft", "submitted", ...]).
    ///   - activate: Closure that applies the filter value to the page's state.
    func register(pageId: String, filterName: String, options: [String], activate: @escaping (String) -> Void) {
        registrations[pageId] = FilterRegistration(
            pageId: pageId,
            filterName: filterName,
            options: options,
            activate: activate
        )
    }

    /// Remove a page's filter registration (typically called in onDisappear).
    func deregister(pageId: String) {
        registrations.removeValue(forKey: pageId)
    }

    // MARK: - Activation

    /// Activate a filter on a specific page. Returns `true` if the page was active
    /// and the filter was applied immediately, `false` if it was queued as pending.
    @discardableResult
    func activateFilter(pageId: String, value: String) -> Bool {
        if let reg = registrations[pageId] {
            reg.activate(value)
            return true
        } else {
            // Page not currently active — queue for when it appears
            pendingFilter = (pageId: pageId, value: value)
            return false
        }
    }

    /// Activates an already-authorized assistant command only while its exact
    /// page/value registration is still active. Unlike `activateFilter`, this
    /// never creates a deferred request after a confirmation dialog is shown.
    @discardableResult
    func activateCurrentlyRegisteredFilter(pageId: String, value: String) -> Bool {
        guard let registration = registrations[pageId],
              registration.options.contains(where: {
                  $0.compare(value, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
              })
        else {
            return false
        }

        registration.activate(value)
        return true
    }

    /// Called by a page in its onAppear to consume any pending filter request.
    func applyPendingFilter(pageId: String) {
        guard let pending = pendingFilter, pending.pageId == pageId else { return }
        if let reg = registrations[pageId] {
            reg.activate(pending.value)
        }
        pendingFilter = nil
    }

    // MARK: - Introspection

    /// Returns all currently registered filters for AI context building.
    func getAvailableFilters() -> [(pageId: String, filterName: String, options: [String])] {
        registrations.values.map { ($0.pageId, $0.filterName, $0.options) }
    }
}

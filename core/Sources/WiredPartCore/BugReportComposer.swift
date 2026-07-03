import Foundation

/// Composes an in-app beta bug report into a shareable plain-text summary and a
/// pre-filled GitHub "new issue" URL.
///
/// Pure Swift with no UIKit/SwiftUI dependencies so the composition logic can be
/// unit-tested in `WiredPartCore`. The app layer gathers the live device,
/// version, page, and recent-error context and hands it to `compose` — no
/// tokens or secrets are ever embedded (the GitHub URL only pre-fills the
/// public issue form, which the user submits while signed in to GitHub).
public enum BugReportComposer {
    /// A single captured error the reporter can attach for context.
    ///
    /// `timestamp` is optional so callers that only retain a message (the
    /// "last shown error" fallback) can still contribute an entry.
    public struct ErrorEntry: Equatable {
        public let message: String
        public let timestamp: Date?

        public init(message: String, timestamp: Date? = nil) {
            self.message = message
            self.timestamp = timestamp
        }
    }

    /// Everything gathered about the running app for a report.
    public struct Context: Equatable {
        /// User-facing device model, e.g. "iPhone 15 Pro".
        public let deviceModel: String
        /// OS name + version, e.g. "iOS 18.2".
        public let systemVersion: String
        /// Marketing app version, e.g. "1.4.0".
        public let appVersion: String
        /// App build number, e.g. "128". Empty when unavailable.
        public let appBuild: String
        /// Core package semantic version.
        public let coreVersion: String
        /// The page/module the user was on, e.g. "Settings > About".
        /// `nil` when the current module could not be determined.
        public let currentModule: String?
        /// Recent user-facing errors, most-recent first. May be empty.
        public let recentErrors: [ErrorEntry]

        public init(
            deviceModel: String,
            systemVersion: String,
            appVersion: String,
            appBuild: String,
            coreVersion: String,
            currentModule: String?,
            recentErrors: [ErrorEntry]
        ) {
            self.deviceModel = deviceModel
            self.systemVersion = systemVersion
            self.appVersion = appVersion
            self.appBuild = appBuild
            self.coreVersion = coreVersion
            self.currentModule = currentModule
            self.recentErrors = recentErrors
        }
    }

    /// GitHub repository the issue form belongs to.
    public static let repositorySlug = "xXKillerNoobYT/Weird-Part-Run-2"

    /// Maximum number of recent errors rendered into the report body. Keeps the
    /// GitHub URL comfortably under length limits and the summary readable.
    public static let maxRenderedErrors = 5

    /// Placeholder shown to the user in the editable summary where they should
    /// describe what happened. Kept as a constant so tests and the UI agree.
    public static let descriptionPlaceholder =
        "Describe what you were doing and what went wrong."

    /// Builds the default editable title for a report.
    ///
    /// - Parameter userTitle: A trimmed, non-empty title typed by the user, or
    ///   `nil`/empty to fall back to a module-derived default.
    public static func title(userTitle: String?, context: Context) -> String {
        let trimmed = userTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty {
            return trimmed
        }
        if let module = normalizedModule(context.currentModule) {
            return "[Beta] Bug in \(module)"
        }
        return "[Beta] Bug report"
    }

    /// Renders the human-readable report body (Markdown-friendly plain text).
    ///
    /// - Parameters:
    ///   - description: The user's free-text description. When blank, the
    ///     placeholder is inserted so the GitHub issue makes the gap obvious.
    ///   - context: Gathered app/device context.
    public static func body(description: String?, context: Context) -> String {
        let trimmedDescription = description?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let descriptionSection = trimmedDescription.isEmpty
            ? descriptionPlaceholder
            : trimmedDescription

        var lines: [String] = []
        lines.append("### What happened")
        lines.append("")
        lines.append(descriptionSection)
        lines.append("")
        lines.append("### Environment")
        lines.append("")
        lines.append("- App version: \(displayVersion(context))")
        lines.append("- Core version: \(context.coreVersion)")
        lines.append("- Device: \(context.deviceModel)")
        lines.append("- OS: \(context.systemVersion)")
        lines.append("- Page/module: \(normalizedModule(context.currentModule) ?? "Unknown")")

        let errors = renderedErrors(context.recentErrors)
        if !errors.isEmpty {
            lines.append("")
            lines.append("### Recent errors")
            lines.append("")
            for entry in errors {
                lines.append("- \(renderError(entry))")
            }
        }

        return lines.joined(separator: "\n")
    }

    /// Builds the pre-filled GitHub "new issue" URL.
    ///
    /// Returns `nil` only if the composed components cannot be percent-encoded
    /// or assembled into a valid URL (not expected in practice).
    public static func githubIssueURL(
        userTitle: String?,
        description: String?,
        context: Context
    ) -> URL? {
        let resolvedTitle = title(userTitle: userTitle, context: context)
        let resolvedBody = body(description: description, context: context)

        var components = URLComponents()
        components.scheme = "https"
        components.host = "github.com"
        components.path = "/\(repositorySlug)/issues/new"
        components.queryItems = [
            URLQueryItem(name: "title", value: resolvedTitle),
            URLQueryItem(name: "body", value: resolvedBody),
        ]

        // URLComponents leaves "+" unescaped in query values, but GitHub (like
        // most form decoders) reads "+" as a space, which would mangle the body.
        // Percent-encode it explicitly so text round-trips faithfully.
        components.percentEncodedQuery = components.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")

        return components.url
    }

    // MARK: - Helpers

    /// Trims and normalizes a raw module string, returning `nil` when it is
    /// missing or blank so callers can present a stable "Unknown".
    static func normalizedModule(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func displayVersion(_ context: Context) -> String {
        let build = context.appBuild.trimmingCharacters(in: .whitespacesAndNewlines)
        if build.isEmpty {
            return context.appVersion
        }
        return "\(context.appVersion) (\(build))"
    }

    /// Filters blank messages and caps the list at `maxRenderedErrors`.
    static func renderedErrors(_ errors: [ErrorEntry]) -> [ErrorEntry] {
        errors
            .filter { !$0.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .prefix(maxRenderedErrors)
            .map { $0 }
    }

    private static func renderError(_ entry: ErrorEntry) -> String {
        let message = entry.message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let timestamp = entry.timestamp else {
            return message
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return "\(formatter.string(from: timestamp)) — \(message)"
    }
}

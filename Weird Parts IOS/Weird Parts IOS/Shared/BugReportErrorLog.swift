import Foundation
import Combine
import WiredPartCore

/// A small in-app ring buffer of recent user-facing errors, kept so the beta
/// bug reporter can attach the last things that went wrong.
///
/// The app has no central error store, so this is intentionally lightweight:
/// callers `record(_:)` a user-facing message when they surface an error, and
/// the bug report screen reads `entries` (most-recent first). The buffer
/// is bounded so it can never grow without limit.
@MainActor
final class BugReportErrorLog: ObservableObject {
    /// Shared instance the app records into and the reporter reads from.
    static let shared = BugReportErrorLog()

    /// Maximum retained entries. Older entries are evicted first.
    static let capacity = 25

    struct Entry: Identifiable, Equatable {
        let id = UUID()
        let message: String
        let context: String?
        let timestamp: Date
    }

    /// Recent entries, most-recent first.
    @Published private(set) var entries: [Entry] = []

    init() {}

    /// Records a user-facing error message. Blank messages are ignored so an
    /// empty `loadError` reset never pollutes the log. Consecutive identical
    /// messages are de-duplicated to avoid a retry loop flooding the buffer.
    func record(_ message: String?, context: String? = nil) {
        guard let message else { return }
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let last = entries.first, last.message == trimmed, last.context == context {
            return
        }

        entries.insert(
            Entry(message: trimmed, context: context, timestamp: Date()),
            at: 0
        )
        if entries.count > Self.capacity {
            entries.removeLast(entries.count - Self.capacity)
        }
    }

    /// Clears all recorded entries.
    func clear() {
        entries.removeAll()
    }

    /// Maps recorded entries into composer error entries for report bodies.
    /// Already ordered most-recent first; the composer caps the count.
    func composerEntries() -> [BugReportComposer.ErrorEntry] {
        entries.map { entry in
            let message: String
            if let context = entry.context, !context.isEmpty {
                message = "\(entry.message) (\(context))"
            } else {
                message = entry.message
            }
            return BugReportComposer.ErrorEntry(message: message, timestamp: entry.timestamp)
        }
    }
}

import Foundation
import WiredPartCore

/// App-wide access point for the replicated diagnostic log (#1745).
///
/// `DeviceLogService` lives in `WiredPartCore` and is built by `AppCore` once
/// the database is open. The types that most need to log — `IOSSyncManager`,
/// pairing, bootstrap — are constructed before that, or hold no reference to
/// `AppCore` at all, so threading the service through every initialiser would
/// mean touching a dozen call chains for a logger.
///
/// This is that indirection, kept deliberately small:
///
/// - **Fails silent, never throws.** Before `install(_:)` runs, every call is a
///   no-op. A diagnostic channel must never be able to break the operation it
///   is describing.
/// - **Writes only.** Reading is done through `AppCore.deviceLogService` by the
///   viewer, so this cannot become a back door into fleet data.
///
/// Verbose (`debug`/`trace`) calls are dropped inside the service when the
/// developer toggle is off, so leaving them in hot paths costs one branch.
enum DiagnosticLog {
    /// Set once by `AppCore` after the database opens.
    nonisolated(unsafe) private static var service: DeviceLogService?
    private static let lock = NSLock()

    static func install(_ service: DeviceLogService?) {
        lock.lock(); defer { lock.unlock() }
        Self.service = service
    }

    private static var current: DeviceLogService? {
        lock.lock(); defer { lock.unlock() }
        return service
    }

    static func critical(_ category: String, _ message: String, detail: String? = nil) {
        current?.critical(category, message, detail: detail)
    }

    static func error(_ category: String, _ message: String, detail: String? = nil) {
        current?.error(category, message, detail: detail)
    }

    static func warn(_ category: String, _ message: String, detail: String? = nil) {
        current?.warn(category, message, detail: detail)
    }

    static func info(_ category: String, _ message: String, detail: String? = nil) {
        current?.info(category, message, detail: detail)
    }

    static func debug(_ category: String, _ message: String, detail: String? = nil) {
        current?.debug(category, message, detail: detail)
    }

    static func trace(_ category: String, _ message: String, detail: String? = nil) {
        current?.trace(category, message, detail: detail)
    }

    /// Categories, as constants so the viewer's filter list and the emit sites
    /// cannot drift apart into near-duplicates ("sync" vs "Sync").
    enum Category {
        static let sync = "sync"
        static let pairing = "pairing"
        static let startup = "startup"
        static let auth = "auth"
        static let database = "database"
    }
}

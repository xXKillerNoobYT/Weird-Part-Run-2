/// WiredPartCore — shared data layer for the WiredPart application.
///
/// This package provides:
/// - Database management (GRDB + SQLite)
/// - Data models (Codable + GRDB record protocols)
/// - Business services (auth, settings, etc.)
/// - Sync infrastructure (change tracking, conflict resolution)
/// - Cryptographic operations (Ed25519 via CryptoKit)
///
/// Pure Swift with no UIKit/SwiftUI dependencies. Consumed by
/// macOS and iOS app targets.
public enum WiredPartCore {
    /// Semantic version of the core package.
    public static let version = "1.0.0"
}

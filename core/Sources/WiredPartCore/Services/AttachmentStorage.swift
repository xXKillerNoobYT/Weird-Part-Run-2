import Foundation

/// Durable on-disk storage for chat message attachments (photos + files).
///
/// # Why this exists (#1371)
/// Attachments used to be copied into `FileManager.temporaryDirectory` with the
/// **absolute** path stored verbatim in `message_attachments.file_path`. That is
/// unsafe in two ways:
/// 1. iOS purges `tmp/` under storage pressure — the bubble keeps a path that no
///    longer resolves and the file is gone.
/// 2. The sandbox container path changes across app updates, so a stored absolute
///    path dangles even when the bytes still exist under a new container UUID.
///
/// This type moves attachment bytes into an **Application Support** subdirectory
/// (`ChatAttachments/`), excludes that directory from iCloud/iTunes backup (bulk
/// user media has no business inflating backups), and hands back a **relative**
/// path that is stored in the DB. Resolution to an absolute URL happens at render
/// time against the *current* container, so paths survive container moves.
///
/// The base directory is injectable so tests can round-trip store → resolve
/// without touching the real Application Support directory.
public struct AttachmentStorage: Sendable {
    /// Subdirectory (relative to the base directory) that holds attachment bytes.
    public static let subdirectoryName = "ChatAttachments"

    /// Absolute URL of the directory that contains the `ChatAttachments` folder.
    /// Defaults to the user's Application Support directory.
    private let baseDirectory: URL

    /// The `ChatAttachments` directory itself (created lazily by `ensureDirectory`).
    public var attachmentsDirectory: URL {
        baseDirectory.appendingPathComponent(Self.subdirectoryName, isDirectory: true)
    }

    // MARK: - Init

    /// Create a storage rooted at an explicit base directory (tests, previews).
    public init(baseDirectory: URL) {
        self.baseDirectory = baseDirectory
    }

    /// Create a storage rooted at the process's Application Support directory.
    ///
    /// Throws if Application Support cannot be located — callers should surface
    /// this rather than silently falling back to `tmp/`, which is the exact
    /// failure mode #1371 is fixing.
    public init() throws {
        guard let support = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first else {
            throw AttachmentStorageError.applicationSupportUnavailable
        }
        self.baseDirectory = support
    }

    // MARK: - Directory management

    /// Ensure the `ChatAttachments` directory exists and is excluded from backup.
    /// Idempotent — safe to call before every write.
    @discardableResult
    public func ensureDirectory() throws -> URL {
        let dir = attachmentsDirectory
        let fm = FileManager.default
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        // Exclude from iCloud/iTunes backup. This flag lives on the directory
        // and is inherited conceptually by contents; re-applying is cheap and
        // self-heals if a restore ever clears it.
        try excludeFromBackup(dir)
        return dir
    }

    /// Apply `isExcludedFromBackup` to a URL. Best-effort per file — the
    /// directory-level flag is what matters, but we also tag written files so a
    /// partially-migrated tree stays fully excluded.
    private func excludeFromBackup(_ url: URL) throws {
        var mutable = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try mutable.setResourceValues(values)
    }

    // MARK: - Store

    /// Persist raw `data` under a generated relative filename and return the
    /// **relative** path to store in the DB.
    ///
    /// - Parameter preferredName: original display name; its extension is
    ///   preserved so QuickLook / share sheets pick the right handler. The stored
    ///   filename is uniquified with a UUID so two attachments named `photo.jpg`
    ///   never collide.
    public func store(data: Data, preferredName: String?) throws -> String {
        try ensureDirectory()
        let relative = Self.uniqueRelativePath(preferredName: preferredName)
        let dest = baseDirectory.appendingPathComponent(relative)
        try data.write(to: dest, options: .atomic)
        try? excludeFromBackup(dest)
        return relative
    }

    /// Copy an existing file (e.g. a security-scoped document-picker URL) into
    /// storage and return the **relative** path to store in the DB.
    public func store(copyingFrom source: URL, preferredName: String?) throws -> String {
        try ensureDirectory()
        let relative = Self.uniqueRelativePath(preferredName: preferredName ?? source.lastPathComponent)
        let dest = baseDirectory.appendingPathComponent(relative)
        let fm = FileManager.default
        // Overwrite defensively — the UUID prefix makes a real collision
        // astronomically unlikely, but a stale byte-for-byte identical file left
        // by a crashed prior write should never block the copy.
        if fm.fileExists(atPath: dest.path) {
            try fm.removeItem(at: dest)
        }
        try fm.copyItem(at: source, to: dest)
        try? excludeFromBackup(dest)
        return relative
    }

    // MARK: - Resolve

    /// Resolve a stored **relative** path to an absolute URL against the current
    /// container, or `nil` if the file no longer exists on disk.
    ///
    /// Returning `nil` (rather than a dangling URL) is what lets the UI render an
    /// explicit "file unavailable" state instead of a broken preview (#1372).
    public func resolveURL(relativePath: String) -> URL? {
        let url = baseDirectory.appendingPathComponent(relativePath)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Whether a stored relative path currently resolves to an on-disk file.
    public func fileExists(relativePath: String) -> Bool {
        resolveURL(relativePath: relativePath) != nil
    }

    // MARK: - Helpers

    /// Build a unique relative path (`ChatAttachments/<uuid>.<ext>`), preserving
    /// the original extension when present so type-based handlers keep working.
    static func uniqueRelativePath(preferredName: String?) -> String {
        let ext = preferredName.flatMap { name -> String? in
            let e = (name as NSString).pathExtension
            return e.isEmpty ? nil : e
        }
        let uuid = UUID().uuidString
        let file = ext.map { "\(uuid).\($0)" } ?? uuid
        return "\(subdirectoryName)/\(file)"
    }

    /// Whether a stored `file_path` is an absolute filesystem path (legacy rows)
    /// as opposed to a relative `ChatAttachments/...` path.
    static func isAbsolutePath(_ path: String) -> Bool {
        path.hasPrefix("/")
    }
}

// MARK: - Errors

public enum AttachmentStorageError: Error, Sendable, Equatable {
    /// The process's Application Support directory could not be located.
    case applicationSupportUnavailable
}

extension AttachmentStorageError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .applicationSupportUnavailable:
            return "Could not locate the app's storage directory for attachments."
        }
    }
}

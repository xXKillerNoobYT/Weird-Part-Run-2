import Foundation

// MARK: - Sync Priority Queue

/// Priority queue for sync operations that ensures records always
/// sync before images, and critical operations take precedence.
///
/// 5 priority levels:
/// - 0 (critical): Schema changes, auth tokens, device registry
/// - 1 (high): Record inserts/updates/deletes
/// - 2 (normal): Conflict resolution results
/// - 3 (low): Image thumbnails, small attachments
/// - 4 (background): Full-size images, bulk transfers
///
/// Records (priority 0–2) always complete before images (3–4).
/// Image sync is user-initiated over Bluetooth, automatic over LAN.
public actor SyncPriorityQueue {

    private var queues: [Int: [SyncQueueItem]] = [
        0: [], 1: [], 2: [], 3: [], 4: []
    ]

    /// Total items across all priority levels.
    public var totalCount: Int {
        queues.values.reduce(0) { $0 + $1.count }
    }

    /// Count of record items (priority 0–2).
    public var recordCount: Int {
        (queues[0]?.count ?? 0) + (queues[1]?.count ?? 0) + (queues[2]?.count ?? 0)
    }

    /// Count of binary/image items (priority 3–4).
    public var binaryCount: Int {
        (queues[3]?.count ?? 0) + (queues[4]?.count ?? 0)
    }

    /// Whether there are any record-priority items pending.
    public var hasRecordItems: Bool { recordCount > 0 }

    /// Whether there are any binary items pending.
    public var hasBinaryItems: Bool { binaryCount > 0 }

    // MARK: - Enqueue

    /// Add an item to the queue at the specified priority.
    public func enqueue(_ item: SyncQueueItem) {
        let priority = min(max(item.priority, 0), 4)
        queues[priority, default: []].append(item)
    }

    /// Add multiple items at once.
    public func enqueueAll(_ items: [SyncQueueItem]) {
        for item in items {
            enqueue(item)
        }
    }

    // MARK: - Dequeue

    /// Dequeue the next highest-priority item.
    ///
    /// Returns nil if the queue is empty.
    /// Items are dequeued in FIFO order within the same priority level.
    public func dequeue() -> SyncQueueItem? {
        for priority in 0...4 {
            if var queue = queues[priority], !queue.isEmpty {
                let item = queue.removeFirst()
                queues[priority] = queue
                return item
            }
        }
        return nil
    }

    /// Dequeue up to `count` items, respecting priority order.
    public func dequeueBatch(count: Int) -> [SyncQueueItem] {
        var batch: [SyncQueueItem] = []
        while batch.count < count, let item = dequeue() {
            batch.append(item)
        }
        return batch
    }

    /// Dequeue only record-priority items (0–2).
    public func dequeueRecords(count: Int = 50) -> [SyncQueueItem] {
        var batch: [SyncQueueItem] = []
        for priority in 0...2 {
            while batch.count < count,
                  var queue = queues[priority], !queue.isEmpty {
                let item = queue.removeFirst()
                queues[priority] = queue
                batch.append(item)
            }
        }
        return batch
    }

    /// Dequeue only binary items (3–4).
    public func dequeueBinary(count: Int = 10) -> [SyncQueueItem] {
        var batch: [SyncQueueItem] = []
        for priority in 3...4 {
            while batch.count < count,
                  var queue = queues[priority], !queue.isEmpty {
                let item = queue.removeFirst()
                queues[priority] = queue
                batch.append(item)
            }
        }
        return batch
    }

    // MARK: - Queue Management

    /// Remove all items from all queues.
    public func clear() {
        for priority in 0...4 {
            queues[priority] = []
        }
    }

    /// Remove a specific item by its transfer ID.
    public func remove(transferId: UUID) {
        for priority in 0...4 {
            queues[priority]?.removeAll { $0.transferId == transferId }
        }
    }

    /// Get the current queue status snapshot.
    public func status() -> SyncQueueStatus {
        SyncQueueStatus(
            criticalCount: queues[0]?.count ?? 0,
            highCount: queues[1]?.count ?? 0,
            normalCount: queues[2]?.count ?? 0,
            lowCount: queues[3]?.count ?? 0,
            backgroundCount: queues[4]?.count ?? 0
        )
    }
}

// MARK: - Sync Queue Item

/// An item in the sync priority queue.
public struct SyncQueueItem: Sendable, Identifiable {
    public let id: UUID
    public let transferId: UUID
    public let priority: Int
    public let type: SyncItemType
    public let tableName: String?
    public let recordId: Int64?
    public let data: Data?
    public let metadata: [String: String]
    public let createdAt: Date

    public init(
        priority: Int,
        type: SyncItemType,
        tableName: String? = nil,
        recordId: Int64? = nil,
        data: Data? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = UUID()
        self.transferId = UUID()
        self.priority = priority
        self.type = type
        self.tableName = tableName
        self.recordId = recordId
        self.data = data
        self.metadata = metadata
        self.createdAt = Date()
    }

    /// Estimated size in bytes for bandwidth planning.
    public var estimatedSize: Int {
        data?.count ?? 0
    }
}

// MARK: - Sync Item Type

/// Type of sync queue item.
public enum SyncItemType: String, Sendable {
    case record          // Database record change
    case conflictResult  // Conflict resolution outcome
    case imageThumbnail  // Thumbnail image (small)
    case imageFullSize   // Full-size image (large)
    case document        // Scanned document page
    case attachment      // Generic file attachment
}

// MARK: - Sync Queue Status

/// Snapshot of the sync queue state for UI display.
public struct SyncQueueStatus: Sendable {
    public let criticalCount: Int
    public let highCount: Int
    public let normalCount: Int
    public let lowCount: Int
    public let backgroundCount: Int

    public var totalRecords: Int { criticalCount + highCount + normalCount }
    public var totalBinary: Int { lowCount + backgroundCount }
    public var totalCount: Int { totalRecords + totalBinary }
    public var isEmpty: Bool { totalCount == 0 }
}

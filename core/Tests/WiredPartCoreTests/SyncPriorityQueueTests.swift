import Testing
import Foundation
@testable import WiredPartCore

@Suite("Sync Priority Queue Tests")
struct SyncPriorityQueueTests {

    // MARK: - Enqueue / Dequeue Tests

    @Test("Enqueue and dequeue respects priority order")
    func testPriorityOrder() async {
        let queue = SyncPriorityQueue()

        // Enqueue items in reverse priority order
        await queue.enqueue(SyncQueueItem(priority: 4, type: .imageFullSize))
        await queue.enqueue(SyncQueueItem(priority: 2, type: .conflictResult))
        await queue.enqueue(SyncQueueItem(priority: 0, type: .record, tableName: "users"))
        await queue.enqueue(SyncQueueItem(priority: 1, type: .record, tableName: "parts"))

        // Dequeue should return in priority order: 0, 1, 2, 4
        let first = await queue.dequeue()
        #expect(first?.priority == 0)

        let second = await queue.dequeue()
        #expect(second?.priority == 1)

        let third = await queue.dequeue()
        #expect(third?.priority == 2)

        let fourth = await queue.dequeue()
        #expect(fourth?.priority == 4)
    }

    @Test("Dequeue from empty queue returns nil")
    func testDequeueEmpty() async {
        let queue = SyncPriorityQueue()
        let item = await queue.dequeue()
        #expect(item == nil)
    }

    @Test("Total count is accurate")
    func testTotalCount() async {
        let queue = SyncPriorityQueue()

        await queue.enqueue(SyncQueueItem(priority: 0, type: .record))
        await queue.enqueue(SyncQueueItem(priority: 1, type: .record))
        await queue.enqueue(SyncQueueItem(priority: 3, type: .imageThumbnail))

        let total = await queue.totalCount
        #expect(total == 3)
    }

    // MARK: - Record vs Binary Count

    @Test("Record and binary counts are separate")
    func testRecordBinaryCounts() async {
        let queue = SyncPriorityQueue()

        await queue.enqueue(SyncQueueItem(priority: 0, type: .record))
        await queue.enqueue(SyncQueueItem(priority: 1, type: .record))
        await queue.enqueue(SyncQueueItem(priority: 3, type: .imageThumbnail))
        await queue.enqueue(SyncQueueItem(priority: 4, type: .imageFullSize))

        let recordCount = await queue.recordCount
        let binaryCount = await queue.binaryCount

        #expect(recordCount == 2)
        #expect(binaryCount == 2)
    }

    // MARK: - Batch Operations

    @Test("Dequeue records only returns priority 0-2")
    func testDequeueRecordsOnly() async {
        let queue = SyncPriorityQueue()

        await queue.enqueue(SyncQueueItem(priority: 0, type: .record))
        await queue.enqueue(SyncQueueItem(priority: 1, type: .record))
        await queue.enqueue(SyncQueueItem(priority: 3, type: .imageThumbnail))
        await queue.enqueue(SyncQueueItem(priority: 4, type: .imageFullSize))

        let records = await queue.dequeueRecords(count: 10)
        #expect(records.count == 2)
        #expect(records.allSatisfy { $0.priority <= 2 })
    }

    @Test("Dequeue binary only returns priority 3-4")
    func testDequeueBinaryOnly() async {
        let queue = SyncPriorityQueue()

        await queue.enqueue(SyncQueueItem(priority: 0, type: .record))
        await queue.enqueue(SyncQueueItem(priority: 3, type: .imageThumbnail))
        await queue.enqueue(SyncQueueItem(priority: 4, type: .imageFullSize))

        let binary = await queue.dequeueBinary(count: 10)
        #expect(binary.count == 2)
        #expect(binary.allSatisfy { $0.priority >= 3 })
    }

    @Test("Batch dequeue respects count limit")
    func testBatchLimit() async {
        let queue = SyncPriorityQueue()

        for i in 0..<10 {
            await queue.enqueue(SyncQueueItem(priority: 1, type: .record, tableName: "t\(i)"))
        }

        let batch = await queue.dequeueBatch(count: 3)
        #expect(batch.count == 3)

        let remaining = await queue.totalCount
        #expect(remaining == 7)
    }

    // MARK: - Clear and Remove

    @Test("Clear removes all items")
    func testClear() async {
        let queue = SyncPriorityQueue()

        await queue.enqueue(SyncQueueItem(priority: 0, type: .record))
        await queue.enqueue(SyncQueueItem(priority: 3, type: .imageThumbnail))

        await queue.clear()

        let total = await queue.totalCount
        #expect(total == 0)
    }

    @Test("Remove specific item by transfer ID")
    func testRemoveByTransferId() async {
        let queue = SyncPriorityQueue()

        let item1 = SyncQueueItem(priority: 1, type: .record)
        let item2 = SyncQueueItem(priority: 1, type: .record)

        await queue.enqueue(item1)
        await queue.enqueue(item2)

        await queue.remove(transferId: item1.transferId)

        let total = await queue.totalCount
        #expect(total == 1)
    }

    // MARK: - Status

    @Test("Queue status snapshot is accurate")
    func testQueueStatus() async {
        let queue = SyncPriorityQueue()

        await queue.enqueue(SyncQueueItem(priority: 0, type: .record))
        await queue.enqueue(SyncQueueItem(priority: 1, type: .record))
        await queue.enqueue(SyncQueueItem(priority: 1, type: .record))
        await queue.enqueue(SyncQueueItem(priority: 3, type: .imageThumbnail))
        await queue.enqueue(SyncQueueItem(priority: 4, type: .imageFullSize))

        let status = await queue.status()

        #expect(status.criticalCount == 1)
        #expect(status.highCount == 2)
        #expect(status.normalCount == 0)
        #expect(status.lowCount == 1)
        #expect(status.backgroundCount == 1)
        #expect(status.totalRecords == 3)
        #expect(status.totalBinary == 2)
        #expect(status.totalCount == 5)
        #expect(!status.isEmpty)
    }
}

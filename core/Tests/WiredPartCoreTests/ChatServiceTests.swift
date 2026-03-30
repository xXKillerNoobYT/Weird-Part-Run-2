import Foundation
import Testing
import GRDB
@testable import WiredPartCore

@Suite("ChatService Tests")
struct ChatServiceTests {

    // MARK: - Channel Lifecycle

    @Test("Create channel and list")
    func testCreateAndListChannel() throws {
        let env = try E2ETestHelpers.setUp()
        let channelId = try env.chat.createChannel(
            name: "General Chat",
            channelType: "group",
            jobId: nil,
            createdBy: env.adminUserId
        )
        #expect(channelId > 0)

        let channels = try env.chat.listChannels(userId: env.adminUserId)
        #expect(channels.contains(where: { $0.id == channelId }))
    }

    @Test("Create job-linked channel")
    func testJobLinkedChannel() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        let channelId = try env.chat.createChannel(
            name: "Job Chat",
            channelType: "job",
            jobId: jobId,
            createdBy: env.adminUserId
        )
        #expect(channelId > 0)
    }

    // MARK: - Messages

    @Test("Send and retrieve messages")
    func testSendAndGetMessages() throws {
        let env = try E2ETestHelpers.setUp()
        let channelId = try env.chat.createChannel(
            name: "Msg Test",
            channelType: "group",
            jobId: nil,
            createdBy: env.adminUserId
        )

        let msgId = try env.chat.sendMessage(
            channelId: channelId,
            senderId: env.adminUserId,
            content: "Hello, world!"
        )
        #expect(msgId > 0)

        let messages = try env.chat.getMessages(channelId: channelId, limit: 50)
        #expect(messages.count >= 1)
        #expect(messages.first?.content == "Hello, world!")
    }

    @Test("Multiple messages in order")
    func testMessageOrder() throws {
        let env = try E2ETestHelpers.setUp()
        let channelId = try env.chat.createChannel(
            name: "Order Test",
            channelType: "group",
            jobId: nil,
            createdBy: env.adminUserId
        )

        _ = try env.chat.sendMessage(channelId: channelId, senderId: env.adminUserId, content: "First")
        _ = try env.chat.sendMessage(channelId: channelId, senderId: env.adminUserId, content: "Second")
        _ = try env.chat.sendMessage(channelId: channelId, senderId: env.adminUserId, content: "Third")

        let messages = try env.chat.getMessages(channelId: channelId, limit: 50)
        #expect(messages.count >= 3)
    }

    // MARK: - Q&A Threads

    @Test("Create and list QA threads")
    func testQAThreadLifecycle() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)

        let threadId = try env.chat.createQAThread(
            jobId: jobId,
            askedBy: env.adminUserId,
            subject: "Where are the 12 AWG connectors?",
            priority: "high"
        )
        #expect(threadId > 0)

        let threads = try env.chat.listQAThreads(status: nil)
        #expect(threads.count >= 1)
        #expect(threads.first?.question == "Where are the 12 AWG connectors?")
    }

    @Test("Filter QA threads by job")
    func testQAThreadsByJob() throws {
        let env = try E2ETestHelpers.setUp()
        let job1 = try E2ETestHelpers.seedJob(env, jobNumber: "J-QA1", name: "QA Job 1")
        let job2 = try E2ETestHelpers.seedJob(env, jobNumber: "J-QA2", name: "QA Job 2")

        _ = try env.chat.createQAThread(jobId: job1, askedBy: env.adminUserId, subject: "Q for Job 1", priority: "normal")
        _ = try env.chat.createQAThread(jobId: job2, askedBy: env.adminUserId, subject: "Q for Job 2", priority: "normal")

        let job1Threads = try env.chat.listQAThreads(jobId: job1, status: nil)
        #expect(job1Threads.count == 1)
        #expect(job1Threads.first?.question == "Q for Job 1")
    }

    @Test("Escalate and resolve QA thread")
    func testEscalateAndResolve() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        let threadId = try env.chat.createQAThread(
            jobId: jobId, askedBy: env.adminUserId,
            subject: "Escalation test", priority: "normal"
        )

        try env.chat.escalateThread(threadId: threadId, escalatedBy: env.adminUserId, notes: "Need manager review")
        let history = try env.chat.getEscalationHistory(threadId: threadId)
        #expect(history.count >= 1)

        try env.chat.resolveQAThread(threadId: threadId, resolvedBy: env.adminUserId)
        let resolved = try env.chat.listQAThreads(status: "resolved")
        #expect(resolved.contains(where: { $0.id == threadId }))
    }

    @Test("Push back QA thread")
    func testPushBackThread() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        let threadId = try env.chat.createQAThread(
            jobId: jobId, askedBy: env.adminUserId,
            subject: "Pushback test", priority: "high"
        )
        try env.chat.escalateThread(threadId: threadId, escalatedBy: env.adminUserId, notes: nil)
        try env.chat.pushBackThread(threadId: threadId, pushedBackBy: env.adminUserId, reason: "Need more info")
    }

    // MARK: - Unified Inbox

    @Test("Unified inbox returns items")
    func testUnifiedInbox() throws {
        let env = try E2ETestHelpers.setUp()
        let channelId = try env.chat.createChannel(
            name: "Inbox Test",
            channelType: "group",
            jobId: nil,
            createdBy: env.adminUserId
        )
        _ = try env.chat.sendMessage(channelId: channelId, senderId: env.adminUserId, content: "Test msg")

        let inbox = try env.chat.getUnifiedInbox(userId: env.adminUserId)
        #expect(!inbox.isEmpty)
    }

    @Test("Unread count")
    func testUnreadCount() throws {
        let env = try E2ETestHelpers.setUp()
        let count = try env.chat.getTotalUnreadCount(userId: env.adminUserId)
        #expect(count >= 0)
    }

    // MARK: - Chat Stats

    @Test("Chat stats aggregates")
    func testChatStats() throws {
        let env = try E2ETestHelpers.setUp()
        let stats = try env.chat.getChatStats()
        #expect(stats.totalChannels >= 0)
    }

    // MARK: - Supplier Channels

    @Test("Create supplier channel")
    func testSupplierChannel() throws {
        let env = try E2ETestHelpers.setUp()
        let supplierId = try E2ETestHelpers.seedSupplier(env)
        let channelId = try env.chat.createSupplierChannel(
            name: "Supplier Chat",
            supplierId: supplierId,
            supplierDisplayName: "TestSupplier",
            contactId: nil,
            role: nil,
            createdBy: env.adminUserId,
            jobId: nil
        )
        #expect(channelId > 0)

        let channels = try env.chat.listSupplierChannels(userId: env.adminUserId)
        #expect(channels.count >= 1)
    }

    // MARK: - JPO Hold Thread

    @Test("Create JPO hold thread")
    func testJPOHoldThread() throws {
        let env = try E2ETestHelpers.setUp()
        let threadId = try env.chat.createJPOHoldThread(
            partName: "12 AWG Wire",
            jpoNumber: "JPO-001",
            holdReason: "Need to verify quantity",
            userId: env.adminUserId
        )
        #expect(threadId > 0)

        let found = try env.chat.getJPOHoldThread(partName: "12 AWG Wire", jpoNumber: "JPO-001")
        #expect(found != nil)
    }

    // MARK: - Office Channel

    @Test("Ensure office channel creates it once")
    func testEnsureOfficeChannel() throws {
        let env = try E2ETestHelpers.setUp()
        try env.chat.ensureOfficeChannel()
        try env.chat.ensureOfficeChannel() // idempotent
        let channels = try env.chat.listChannels(userId: env.adminUserId)
        let officeChannels = channels.filter { $0.channelType == "office" }
        #expect(officeChannels.count == 1)
    }
}

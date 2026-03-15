#if canImport(MultipeerConnectivity)
import Testing
import Foundation
@testable import WiredPartCore

@Suite("MultipeerManager Tests")
struct MultipeerTests {

    @Test("MultipeerPeerInfo stores all fields")
    func testPeerInfoInit() {
        let info = MultipeerPeerInfo(
            deviceId: "dev-123",
            deviceName: "iPad Pro",
            companyId: "company-abc",
            state: .found
        )
        #expect(info.deviceId == "dev-123")
        #expect(info.deviceName == "iPad Pro")
        #expect(info.companyId == "company-abc")
        #expect(info.state == .found)
        #expect(!info.discoveredAt.isEmpty)
    }

    @Test("ReceivedMultipeerMessage stores data correctly")
    func testReceivedMessage() {
        let payload = "Hello peer".data(using: .utf8)!
        let msg = ReceivedMultipeerMessage(
            fromDeviceId: "dev-456",
            data: payload
        )
        #expect(msg.fromDeviceId == "dev-456")
        #expect(msg.data == payload)
        #expect(!msg.receivedAt.isEmpty)
    }

    @Test("MultipeerManager initializes without crashing")
    func testManagerInit() {
        let manager = MultipeerManager(
            deviceId: "dev-001",
            deviceName: "Test Mac",
            companyId: "company-abc"
        )
        let peers = manager.getPeers()
        #expect(peers.isEmpty)
        #expect(manager.receiveQueueCount == 0)
    }

    @Test("send to unknown peer returns false")
    func testSendToUnknown() {
        let manager = MultipeerManager(
            deviceId: "dev-001",
            deviceName: "Test Mac",
            companyId: "company-abc"
        )
        let result = manager.send(
            data: "test".data(using: .utf8)!,
            toPeer: "nonexistent-device"
        )
        #expect(result == false)
    }

    @Test("popReceivedMessage returns nil when empty")
    func testPopEmpty() {
        let manager = MultipeerManager(
            deviceId: "dev-001",
            deviceName: "Test Mac",
            companyId: "company-abc"
        )
        let msg = manager.popReceivedMessage()
        #expect(msg == nil)
    }
}
#endif

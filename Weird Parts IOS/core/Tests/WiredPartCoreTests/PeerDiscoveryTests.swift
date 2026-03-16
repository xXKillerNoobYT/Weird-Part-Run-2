import Testing
import Foundation
@testable import WiredPartCore

@Suite("PeerDiscovery Tests")
struct PeerDiscoveryTests {

    @Test("DiscoveredPeer stores all fields correctly")
    func testDiscoveredPeerInit() {
        let peer = DiscoveredPeer(
            deviceId: "dev-123",
            deviceName: "Office Mac",
            companyId: "company-abc",
            host: "192.168.1.50",
            port: 8080,
            version: "1.0.0",
            transport: "lan"
        )
        #expect(peer.id == "dev-123")
        #expect(peer.deviceId == "dev-123")
        #expect(peer.deviceName == "Office Mac")
        #expect(peer.companyId == "company-abc")
        #expect(peer.host == "192.168.1.50")
        #expect(peer.port == 8080)
        #expect(peer.version == "1.0.0")
        #expect(peer.transport == "lan")
        #expect(peer.multipeerState == nil)
        #expect(!peer.discoveredAt.isEmpty)
    }

    @Test("PeerDiscovery initializes without crashing")
    func testPeerDiscoveryInit() {
        let discovery = PeerDiscovery(
            deviceId: "dev-001",
            companyId: "company-abc",
            deviceName: "Test Device",
            port: 9090
        )
        // Should start with empty peer list
        let peers = discovery.getPeers()
        #expect(peers.isEmpty)
    }

    @Test("PeerDiscovery start and stop lifecycle")
    func testStartStop() {
        let discovery = PeerDiscovery(
            deviceId: "dev-001",
            companyId: "company-abc",
            deviceName: "Test Device",
            port: 9090
        )
        // Start and stop should not crash
        discovery.start()
        // Give a moment for the queue to process
        Thread.sleep(forTimeInterval: 0.1)
        discovery.stop()
        Thread.sleep(forTimeInterval: 0.1)
        let peers = discovery.getPeers()
        #expect(peers.isEmpty)
    }
}

//
//  Weird_Parts_IOSTests.swift
//  Weird Parts IOSTests
//
//  Created by Isaac Aznoe on 3/15/26.
//

import Foundation
import Testing
import WiredPartCore
@testable import Weird_Parts


struct Weird_Parts_IOSTests {

    struct LANPeerDiscoveryStartupError: Error, LocalizedError {
        var errorDescription: String? { "port unavailable" }
    }

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    }

    @MainActor
    @Test func qaResolvedStatusBucketIncludesServiceResolvedStatus() async throws {
        #expect(QAThreadStatusBuckets.isResolved("resolved"))
        #expect(QAThreadStatusBuckets.isResolved("answered"))
        #expect(QAThreadStatusBuckets.isResolved("closed"))
        #expect(!QAThreadStatusBuckets.isResolved("open"))
        #expect(!QAThreadStatusBuckets.isResolved("escalated"))
    }

    @MainActor
    @Test func lanPeerDiscoveryStartupFailureSurfacesErrorAndStopsLanOnlyScan() async throws {
        let manager = IOSSyncManager()
        manager.isScanning = true

        manager.handleLanPeerDiscoveryStartupFailure(
            LANPeerDiscoveryStartupError(),
            hasActiveMultipeerDiscovery: false
        )

        #expect(manager.syncStatus == .error)
        #expect(manager.errorMessage == "LAN peer discovery failed: port unavailable")
        #expect(!manager.isScanning)
    }

    @MainActor
    @Test func lanPeerDiscoveryStartupFailureKeepsBluetoothScanTruthful() async throws {
        let manager = IOSSyncManager()
        manager.isScanning = true

        manager.handleLanPeerDiscoveryStartupFailure(
            LANPeerDiscoveryStartupError(),
            hasActiveMultipeerDiscovery: true
        )

        #expect(manager.syncStatus == .error)
        #expect(manager.errorMessage == "LAN peer discovery failed: port unavailable")
        #expect(manager.isScanning)
    }
}

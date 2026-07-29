import XCTest
import WiredPartCore
@testable import Weird_Parts

final class SyncManagerFailureSurfacingRegressionTests: XCTestCase {
    func testShopPairingDependencyFailuresClearProgressAndSurfaceError() throws {
        let source = try Self.readSyncManagerSource()
        let pairWithShopBody = try TestSourceSlicer.braceBalancedBody(
            after: "func pairWithShop(shopAddress: String, pairingCode: String) async throws",
            in: source
        )

        XCTAssertTrue(
            pairWithShopBody.contains(
                """
                guard let db, let pm = peerManager else {
                            syncStatus = .error
                            syncProgressMessage = nil
                            errorMessage = SyncError.noDatabaseAvailable.localizedDescription
                            throw SyncError.noDatabaseAvailable
                        }
                """
            ),
            "A missing database or peer manager must leave shop pairing in the same visible error state."
        )
        XCTAssertFalse(
            pairWithShopBody.contains(
                """
                guard let pm = peerManager else {
                            throw SyncError.noDatabaseAvailable
                        }
                """
            ),
            "The peer-manager failure path must not throw while leaving stale syncing progress visible."
        )
    }

    func testShopPairingInvalidServerKeyClearsProgressAndSurfacesError() throws {
        let source = try Self.readSyncManagerSource()
        let pairWithShopBody = try TestSourceSlicer.braceBalancedBody(
            after: "func pairWithShop(shopAddress: String, pairingCode: String) async throws",
            in: source
        )

        XCTAssertTrue(
            pairWithShopBody.contains(
                """
                guard let serverKey = pairResponse.serverKeyAgreementPublicKey,
                              Data(base64Encoded: serverKey)?.count == 32 else {
                            let error = SyncError.pairingVerificationFailed("The shop did not provide a trusted LAN key.")
                            syncStatus = .error
                            syncProgressMessage = nil
                            errorMessage = error.localizedDescription
                            throw error
                        }
                """
            ),
            "A missing or malformed shop key must clear stale pairing progress and expose the verification failure."
        )
    }

    @MainActor
    func testShopPairingFailureTransitionClearsProgressAndSurfacesUsefulErrors() {
        let manager = IOSSyncManager()
        manager.syncStatus = .syncing
        manager.syncProgressMessage = "Connecting to shop..."

        manager.surfaceShopPairingFailure(SyncIdentityStoreError.keychainWriteFailed(-50))

        XCTAssertEqual(manager.syncStatus, .error)
        XCTAssertNil(manager.syncProgressMessage)
        XCTAssertEqual(
            manager.errorMessage,
            "Couldn't securely load this device's sync identity. Pairing stopped; try again."
        )

        manager.syncStatus = .syncing
        manager.syncProgressMessage = "Connecting to shop..."
        let rejection = IOSSyncManager.SyncError.pairingVerificationFailed("Pairing was not accepted by the shop.")

        manager.surfaceShopPairingFailure(rejection)

        XCTAssertEqual(manager.syncStatus, .error)
        XCTAssertNil(manager.syncProgressMessage)
        XCTAssertEqual(manager.errorMessage, "Pairing was not accepted by the shop.")
    }

    func testShopPairingIdentityAndEncryptedResponseFailuresShareFailClosedCatch() throws {
        let source = try Self.readSyncManagerSource()
        let pairWithShopBody = try TestSourceSlicer.braceBalancedBody(
            after: "func pairWithShop(shopAddress: String, pairingCode: String) async throws",
            in: source
        )
        let normalized = pairWithShopBody.split(whereSeparator: \.isWhitespace).joined(separator: " ")

        XCTAssertTrue(
            normalized.contains(
                "do { pairingIdentity = try await pm.localSyncIdentity(deviceId: deviceId) pairResponse = try await verifyPairingCodeWithShop("
            ),
            "Identity acquisition and the entire encrypted response pipeline must share one visible failure boundary."
        )
        XCTAssertTrue(
            normalized.contains("} catch { surfaceShopPairingFailure(error) throw error }"),
            "Pairing failures must publish the non-stuck error state and rethrow the original fail-closed error."
        )
    }

    @MainActor
    func testBluetoothPairingHostKeyRequiresValid32ByteX25519Material() throws {
        let validKey = Data(repeating: 0xA5, count: 32).base64EncodedString()

        XCTAssertEqual(try IOSSyncManager.validatedBluetoothHostKey(validKey), validKey)

        for invalidKey in [nil, "not-base64", Data(repeating: 0xA5, count: 31).base64EncodedString()] {
            XCTAssertThrowsError(try IOSSyncManager.validatedBluetoothHostKey(invalidKey)) { error in
                XCTAssertEqual(
                    error.localizedDescription,
                    "The Bluetooth host did not provide a valid 32-byte X25519 public key."
                )
            }
        }
    }

    @MainActor
    func testBluetoothPairingHostKeyFailureClearsProgressAndSurfacesError() {
        let manager = IOSSyncManager()
        manager.syncStatus = .syncing
        manager.syncProgressMessage = "Connecting over Bluetooth…"
        manager.syncProgressPercent = 0.3
        let error = IOSSyncManager.SyncError.pairingVerificationFailed(
            "The Bluetooth host did not provide a valid 32-byte X25519 public key."
        )

        manager.surfaceBluetoothPairingFailure(error)

        XCTAssertEqual(manager.syncStatus, .error)
        XCTAssertNil(manager.syncProgressMessage)
        XCTAssertEqual(manager.syncProgressPercent, 0)
        XCTAssertEqual(manager.errorMessage, error.localizedDescription)
    }

    func testBluetoothPairingValidatesHostKeyBeforeTrustPersistence() throws {
        let source = try Self.readSyncManagerSource()
        let pairingBody = try TestSourceSlicer.braceBalancedBody(
            after: "func pairWithPeerOverBluetooth(hostDeviceId: String, hostName: String, pairingCode: String) async throws",
            in: source
        )

        let validation = try XCTUnwrap(pairingBody.range(of: "validatedBluetoothHostKey"))
        let registration = try XCTUnwrap(pairingBody.range(of: "ChangeTracker.registerPeerDevice"))
        let settingsPersistence = try XCTUnwrap(pairingBody.range(of: "upsertSettingsMap"))
        let pairedFlag = try XCTUnwrap(pairingBody.range(of: "device_paired"))

        XCTAssertLessThan(validation.lowerBound, registration.lowerBound)
        XCTAssertLessThan(validation.lowerBound, settingsPersistence.lowerBound)
        XCTAssertLessThan(validation.lowerBound, pairedFlag.lowerBound)
        XCTAssertTrue(pairingBody.contains("keyAgreementPublicKey: hostKey"))
        XCTAssertTrue(pairingBody.contains("surfaceBluetoothPairingFailure(error)"))
    }

    func testBluetoothPairingResponseValidationSharesVisibleFailureBoundary() throws {
        let source = try Self.readSyncManagerSource()
        let pairingBody = try TestSourceSlicer.braceBalancedBody(
            after: "func pairWithPeerOverBluetooth(hostDeviceId: String, hostName: String, pairingCode: String) async throws",
            in: source
        )

        let pairCall = try XCTUnwrap(pairingBody.range(of: "try await pm.pairViaMultipeer"))
        let validation = try XCTUnwrap(pairingBody.range(of: "validatedBluetoothHostKey"))
        let failureCatch = try XCTUnwrap(
            pairingBody.range(of: "} catch {", range: validation.upperBound..<pairingBody.endIndex)
        )
        let failureBody = pairingBody[failureCatch.lowerBound...]
        let sharedDo = pairingBody[..<pairCall.lowerBound].range(of: "do {", options: .backwards)

        XCTAssertNotNil(
            sharedDo,
            "Multipeer response verification can throw before returning; the transport call must share the visible failure boundary."
        )
        XCTAssertLessThan(pairCall.lowerBound, validation.lowerBound)
        XCTAssertLessThan(validation.lowerBound, failureCatch.lowerBound)
        XCTAssertTrue(failureBody.contains("surfaceBluetoothPairingFailure(error)"))
        XCTAssertTrue(failureBody.contains("throw error"))
    }


    private static func repoRoot(file: StaticString = #filePath) -> URL {
        URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static func readSyncManagerSource(file: StaticString = #filePath) throws -> String {
        let sourceURL = repoRoot(file: file)
            .appendingPathComponent("Weird Parts IOS")
            .appendingPathComponent("Sync")
            .appendingPathComponent("IOSSyncManager.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }


}

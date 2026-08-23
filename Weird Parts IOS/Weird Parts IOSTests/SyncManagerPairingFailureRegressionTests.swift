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

    func testSuccessfulInitialDownloadTransitionsOutOfTemporaryOnboardingDiscovery() throws {
        let source = try Self.readSyncManagerSource()
        let initialSyncBody = try TestSourceSlicer.braceBalancedBody(
            after: "func performInitialSync() async throws",
            in: source
        )

        let activation = try XCTUnwrap(
            initialSyncBody.range(of: "activateOngoingSyncAfterInitialDownload()")
        )
        let errorExit = try XCTUnwrap(
            initialSyncBody.range(of: "throw SyncError.noServerConfigured", options: .backwards)
        )
        let refresh = try XCTUnwrap(initialSyncBody.range(of: "refreshPendingCount()", options: .backwards))

        XCTAssertGreaterThan(activation.lowerBound, errorExit.lowerBound)
        XCTAssertLessThan(activation.lowerBound, refresh.lowerBound)
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

    // MARK: - #1580 — the Sync Error screen must show the REAL reason

    /// Behavioural, not a source scan: it calls the production decision
    /// directly, so it fails if the behaviour regresses even when the source
    /// still *looks* right.
    ///
    /// Build 63 showed the owner "Couldn't sync data. Pull down to retry." on a
    /// failure the app had already diagnosed. `performInitialSync` composes a
    /// transport-specific reason with `initialSyncFailureMessage`, but the view
    /// handed the thrown error to `userFriendlyError`, which matches against a
    /// substring list and falls back to that generic template when none hit —
    /// discarding the good message.
    func testComposedSyncFailureIsPreferredOverTheGenericFallback() {
        let composed = IOSSyncManager.initialSyncFailureMessage(
            wifiFailure: nil,
            bluetoothError: MultipeerPairingError.rejected
        )

        let shown = IOSSyncManager.displayableSyncFailure(
            composed: composed,
            thrown: IOSSyncManager.SyncError.syncFailed(composed)
        )

        XCTAssertEqual(shown, composed, "the composed reason must reach the screen verbatim")
        XCTAssertFalse(
            shown.contains("Pull down to retry"),
            "the generic fallback replaced a reason the app had already worked out"
        )
        XCTAssertTrue(
            shown.contains("NEW code"),
            "a rejected pairing must tell the user to generate a new code — that is the actionable part"
        )
    }

    // MARK: - #1699 — a deferred peer is waiting, not failing

    /// Behavioural. A deferred result carries `success == false`, so any caller
    /// that tests `!success` alone reports a healthy onboarding transfer as a
    /// failure. This pins the shared decision both sync entry points consult.
    func testDeferredPeerIsNotCountedAsASyncFailure() {
        let deferred = PeerSyncResult(
            peerDeviceId: "joiner-1",
            peerName: "Shop iPad",
            success: false,
            deferred: true
        )
        let broken = PeerSyncResult(
            peerDeviceId: "joiner-2",
            peerName: "Van iPhone",
            success: false,
            error: "Bluetooth transfer aborted",
            deferred: false
        )

        XCTAssertTrue(
            IOSSyncManager.peerSyncFailures(in: [deferred]).isEmpty,
            "a peer waiting for its first download is not a failure the user must act on"
        )
        XCTAssertEqual(
            IOSSyncManager.peerSyncFailures(in: [deferred, broken]).map(\.peerDeviceId),
            ["joiner-2"],
            "a real failure alongside a deferral must still surface, and only it"
        )
        XCTAssertEqual(
            IOSSyncManager.waitingForFirstDownloadMessage(for: [deferred]),
            "Waiting for Shop iPad's first download to finish…"
        )
        XCTAssertNil(
            IOSSyncManager.waitingForFirstDownloadMessage(for: [broken]),
            "nobody is downloading, so there is nothing to wait for"
        )
    }

    // MARK: - #1693 sibling — the fan-out must say WHY, not just how many

    /// Behavioural. `syncWithPeer` has always rendered the real reason; the
    /// all-peers fan-out rendered only a count, so every cause collapsed into
    /// "Sync failed with 1 peer(s)". Field-confirmed on build 68 (2026-08-20):
    /// a peer still forming its session reported a hard failure with no reason,
    /// while the row behind the alert visibly said "Connecting".
    func testFanOutFailureMessageCarriesTheReasonNotJustACount() {
        let stillConnecting = PeerSyncResult(
            peerDeviceId: "mac-1",
            peerName: "crystals-mac-studio",
            success: false,
            error: "Still connecting to crystals-mac-studio over Bluetooth — try again in a moment.",
            deferred: false
        )

        let message = IOSSyncManager.peerSyncFailureMessage(for: [stillConnecting])

        XCTAssertEqual(
            message,
            "Still connecting to crystals-mac-studio over Bluetooth — try again in a moment. for crystals-mac-studio",
            "the fan-out must surface PeerSyncResult.error verbatim, as the row-level path already does"
        )
        XCTAssertFalse(
            message?.contains("peer(s)") ?? true,
            "a bare count tells the user nothing actionable — that is the defect being pinned"
        )
    }

    /// Two peers failing for DIFFERENT causes is exactly when a single-reason
    /// summary misleads, so every reason must survive.
    func testFanOutFailureMessageReportsEveryDistinctReason() {
        let a = PeerSyncResult(
            peerDeviceId: "mac-1",
            peerName: "Shop Mac",
            success: false,
            error: "Sync server not running",
            deferred: false
        )
        let b = PeerSyncResult(
            peerDeviceId: "ipad-1",
            peerName: "Van iPad",
            success: false,
            error: "Bluetooth transfer aborted",
            deferred: false
        )

        let message = IOSSyncManager.peerSyncFailureMessage(for: [a, b]) ?? ""

        XCTAssertTrue(message.contains("Sync server not running for Shop Mac"))
        XCTAssertTrue(
            message.contains("Bluetooth transfer aborted for Van iPad"),
            "the second peer's distinct cause must not be swallowed by the first"
        )
        XCTAssertNil(
            IOSSyncManager.peerSyncFailureMessage(for: []),
            "no failures means no error message — the caller guards on nil"
        )
    }

    /// Structural. The behavioural tests above still pass if `syncNow` stops
    /// calling the helper and re-derives its own count string, which is exactly
    /// the mutation that produced this bug: the row-level path was repaired for
    /// #1693 and its fan-out twin was left alone.
    func testFanOutRoutesItsFailureMessageThroughTheSharedHelper() throws {
        let source = try Self.readSyncManagerSource()
        let body = try TestSourceSlicer.braceBalancedBody(
            after: "func syncNow() async",
            in: source
        )

        XCTAssertTrue(
            body.contains("Self.peerSyncFailureMessage(for: failed)"),
            "the fan-out must reuse the shared wording, not re-derive one"
        )
        XCTAssertFalse(
            body.contains("peer(s)"),
            "a re-introduced bare count would hide the reason the app already holds"
        )
    }

    /// Structural, and deliberately so: the helper test above still passes if a
    /// call site stops calling the helper. This one fails on exactly that
    /// mutation. The row-level Nearby Devices tap regressed this way once —
    /// #1625 fixed the all-peers fan-out and left the single-peer path testing
    /// `!result.success` on its own, which #1719 then widened from a sub-second
    /// window to the entire multi-minute Bluetooth download.
    func testRowLevelSyncRoutesFailureDecisionThroughTheSharedPredicate() throws {
        let source = try Self.readSyncManagerSource()
        let body = try TestSourceSlicer.braceBalancedBody(
            after: "func syncWithPeer(peerDeviceId: String) async",
            in: source
        )

        XCTAssertTrue(
            body.contains("Self.peerSyncFailures(in: [result])"),
            "the row-level path must reuse the shared failure decision, not re-derive one"
        )
        XCTAssertFalse(
            body.contains("if !result.success {"),
            "treating every unsuccessful result as an error reports a healthy deferral as Sync Error"
        )
        XCTAssertTrue(
            body.contains("Self.waitingForFirstDownloadMessage(for: [result])"),
            "a deferred single-peer sync must explain what it is waiting for"
        )
    }

    /// The fallback still has to work for errors nobody has explained, and an
    /// empty or whitespace-only message must not count as "composed".
    func testGenericFallbackStillUsedWhenNothingWasComposed() {
        struct Unexplained: Error {}

        for empty in [nil, "", "   \n"] as [String?] {
            let shown = IOSSyncManager.displayableSyncFailure(
                composed: empty,
                thrown: Unexplained()
            )
            XCTAssertTrue(
                shown.contains("Pull down to retry"),
                "with no composed reason (\(String(describing: empty))) the generic fallback must still appear"
            )
        }
    }

    // MARK: - #1725 — the phone must never blame distance for an error it can name

    /// Mirrors GRDB's `DatabaseError` conformance EXACTLY: `CustomNSError`,
    /// deliberately NOT `LocalizedError`, with the real message living in
    /// `errorUserInfo[NSLocalizedDescriptionKey]`
    /// (GRDB/Core/DatabaseError.swift:593-608).
    ///
    /// The precise conformance is the whole point. The bug was that
    /// `(error as? LocalizedError)?.errorDescription` returns nil for this
    /// shape while `localizedDescription` carries the full SQL, so a stand-in
    /// that conformed to `LocalizedError` would pass every assertion below
    /// while the shipped app still showed the canned distance message.
    private struct DatabaseErrorLike: Error, CustomNSError {
        static let message = """
            SQLite error 21: wrong number of statement arguments: 8 - while executing \
            `UPDATE "clock_out_questions" SET "answer_type" = ?, "updated_at" = ? WHERE id = ?`
            """

        static var errorDomain: String { "GRDB.DatabaseError" }
        var errorCode: Int { 21 }
        var errorUserInfo: [String: Any] { [NSLocalizedDescriptionKey: Self.message] }
    }

    /// The build-66 field failure, pinned.
    ///
    /// The owner's phone showed "Bluetooth transfer failed — keep both devices
    /// close and retry" for what was actually `SQLite error 21` (#1723).
    /// Distance was never going to fix a database bug, and the one message that
    /// could have diagnosed it was discarded by a failed protocol cast. Only
    /// the Mac, which surfaced the raw text, made the cause findable at all.
    func testDatabaseErrorIsNamedOnScreenInsteadOfBlamingDistance() {
        let report = IOSSyncManager.initialSyncFailureReport(
            wifiFailure: nil,
            bluetoothError: DatabaseErrorLike()
        )

        XCTAssertFalse(
            report.headline.contains("keep both devices close"),
            "the canned distance advice came back for an error we can name — this is exactly the build-66 bug (#1725)"
        )
        XCTAssertTrue(
            report.headline.contains("SQLite error 21"),
            "the cause must be legible on the screen itself: device logs replicate over the very sync that is broken, so a photograph of this screen is the only diagnostic channel that survives"
        )
        XCTAssertEqual(
            report.detail?.contains(#"UPDATE "clock_out_questions""#), true,
            "the untruncated failing statement must survive into the copyable detail"
        )
        XCTAssertTrue(
            report.code.hasPrefix("BT-"),
            "\(report.code) breaks the shipped BT-* convention"
        )
        XCTAssertNotEqual(
            report.code, "BT-SYNC-FAILED",
            "a code that names nothing is no better than no code at all"
        )
    }

    /// The owner asked for the full error on the clipboard, so one tap has to
    /// produce something a bug report can be built from without paraphrase.
    func testCopyableTextCarriesCodeHeadlineAndUntruncatedDetail() {
        let report = IOSSyncManager.initialSyncFailureReport(
            wifiFailure: nil,
            bluetoothError: DatabaseErrorLike()
        )
        let copied = report.copyableText

        XCTAssertTrue(copied.contains(report.code), "the code is what makes a report greppable")
        XCTAssertTrue(copied.contains(report.headline), "the plain-English headline gives the detail context")
        XCTAssertTrue(
            copied.contains("clock_out_questions"),
            "the failing table must be copyable — naming it is what identified #1723"
        )
        XCTAssertTrue(
            copied.contains("wrong number of statement arguments"),
            "the copied text must be the whole cause, not the headline's truncated summary"
        )
    }

    /// The other half of the rule: when nobody ever wrote a message, generic
    /// advice really is the most useful headline. It must not be replaced by
    /// Foundation's "The operation couldn't be completed." boilerplate — but
    /// the concrete type is still the only lead available, so it has to reach
    /// the bug report through the detail.
    func testOpaqueErrorKeepsActionableAdviceButStillNamesItsTypeInTheDetail() {
        struct Unexplained: Error {}

        let report = IOSSyncManager.initialSyncFailureReport(
            wifiFailure: nil,
            bluetoothError: Unexplained()
        )

        XCTAssertTrue(
            report.headline.contains("keep both devices close"),
            "with no message written anywhere, generic advice is genuinely the best headline available"
        )
        XCTAssertFalse(
            report.headline.contains("couldn't be completed"),
            "Foundation boilerplate is not a diagnosis and must not displace actionable advice"
        )
        XCTAssertEqual(
            report.detail?.contains("Unexplained"), true,
            "the concrete type is all an unexplained error offers — it must still reach the bug report"
        )
    }

    /// Every pairing cause must arrive on screen with its own code. Driven off
    /// `CaseIterable` so a newly added case fails here instead of shipping
    /// code-less, matching the core-side rule from #1693.
    func testEveryPairingFailureReachesTheScreenWithItsOwnCode() {
        for pairing in MultipeerPairingError.allCases {
            let report = IOSSyncManager.initialSyncFailureReport(
                wifiFailure: nil,
                bluetoothError: pairing
            )

            XCTAssertEqual(
                report.code, pairing.code,
                "the screen must show the pairing error's own stable code, not a re-derived one"
            )
            XCTAssertFalse(
                report.headline.contains(pairing.code),
                "the code is rendered as its own field now — repeating it inside the sentence shows it to the user twice"
            )
            XCTAssertFalse(
                report.headline.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "\(pairing.code) reached the screen with no explanation"
            )
        }
    }

    /// The #1580 rule, restated for the structured form: a reason the app
    /// already worked out always beats the substring-matching generic.
    func testComposedReportIsPreferredOverTheGenericFallback() {
        let composed = IOSSyncManager.initialSyncFailureReport(
            wifiFailure: nil,
            bluetoothError: MultipeerPairingError.rejected
        )

        let shown = IOSSyncManager.displayableSyncFailureReport(
            composed: composed,
            thrown: IOSSyncManager.SyncError.syncFailed(composed.headline)
        )

        XCTAssertEqual(shown, composed, "the composed report must reach the screen intact")
        XCTAssertTrue(shown.headline.contains("NEW code"), "the actionable part must survive")
    }

    /// The path that most needs the detail is the one nobody composed a
    /// sentence for: an error with no written explanation is precisely the
    /// error whose raw text is the only evidence there is.
    func testFallbackReportStillCarriesACodeAndTheCauseWhenNothingWasComposed() {
        let report = IOSSyncManager.displayableSyncFailureReport(
            composed: nil,
            thrown: DatabaseErrorLike()
        )

        XCTAssertTrue(
            report.headline.contains("Pull down to retry"),
            "with nothing composed the generic headline is still the right one"
        )
        XCTAssertEqual(
            report.detail?.contains("SQLite error 21"), true,
            "the cause must no longer be dropped on the floor on the fallback path"
        )
        XCTAssertTrue(report.code.hasPrefix("BT-"), "even the fallback carries a code")
    }

    /// Structural, and deliberately so. `errorMessage` is already cleared here
    /// because a retry inheriting the previous attempt's advice reads as a
    /// confirmed diagnosis rather than a leftover (#1693). The structured
    /// report is the richer copy of that same diagnosis and goes stale
    /// identically, so omitting it reintroduces exactly the bug that comment
    /// was written to prevent.
    func testRetryDoesNotInheritThePreviousAttemptsReport() throws {
        let source = try Self.readSyncManagerSource()
        let body = try TestSourceSlicer.braceBalancedBody(
            after: "func performInitialSync() async throws",
            in: source
        )

        XCTAssertTrue(
            body.contains("lastFailureReport = nil"),
            "a second attempt failing for a new reason must not redisplay the first attempt's technical detail"
        )
    }
}

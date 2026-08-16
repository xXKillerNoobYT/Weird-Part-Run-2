import Foundation
import Testing
import GRDB
@testable import WiredPartCore

/// #1684 — Bluetooth sync was one-directional per tap.
///
/// `syncWithPeer`'s multipeer branch sent our pending changes and never asked
/// for the peer's, so `pulled` was **structurally** always 0 and a two-way
/// exchange required a Sync tap on both devices. Field-confirmed on builds
/// 67/47: a user created on the phone never reached the Mac, while data that
/// rode the initial snapshot did.
///
/// Owner directive: any device syncs with any device.
///
/// These tests cover the wire contract that makes the reply safe in a mixed
/// fleet. The end-to-end exchange needs two real Multipeer sessions and is
/// covered by the on-device verification script, not here.
@Suite("Sync reciprocity")
struct SyncReciprocityTests {

    /// The flag must be optional in BOTH directions, per the same reasoning
    /// `transferId` carries: an old build must be able to decode a new build's
    /// frame, and vice versa. Version skew is a live failure mode on this
    /// project, not a hypothetical — a peer running an older build is the
    /// normal case during a staged rollout.
    @Test("A new build decodes an OLD peer's frame, which has no reciprocal key")
    func decodesLegacyEnvelope() throws {
        // Exactly what a pre-#1684 build emits: no `reciprocal` key at all.
        let legacy = #"{"type":"changes","payload":"e30="}"#.data(using: .utf8)!
        let env = try JSONDecoder().decode(MPEnvelope.self, from: legacy)
        #expect(env.type == "changes")
        #expect(
            env.reciprocal == nil,
            "a missing key must read as nil, not fail to decode — otherwise an old peer's push is rejected outright"
        )
    }

    /// And the reverse: an old build must not choke on the new key. Swift's
    /// `JSONDecoder` ignores unknown keys, so this asserts the property the
    /// old decoder relies on rather than the old decoder itself.
    @Test("An OLD build's decoder tolerates the new reciprocal key")
    func legacyDecoderTolerapesNewKey() throws {
        /// Stand-in for the pre-#1684 shape — no `reciprocal` field.
        struct LegacyEnvelope: Codable {
            let type: String
            let payload: Data
            let transferId: String?
            let sha256: String?
        }
        let modern = MPEnvelope(type: "changes", payload: Data("{}".utf8), reciprocal: true)
        let encoded = try JSONEncoder().encode(modern)
        let decoded = try JSONDecoder().decode(LegacyEnvelope.self, from: encoded)
        #expect(
            decoded.type == "changes",
            "an old peer must still read the frame and apply the changes — a mixed fleet degrades to one-way sync, it does not break"
        )
    }

    @Test("A reply is marked so it cannot provoke another reply")
    func replyIsMarked() throws {
        let reply = MPEnvelope(type: "changes", payload: Data("{}".utf8), reciprocal: true)
        let roundTripped = try JSONDecoder().decode(
            MPEnvelope.self, from: JSONEncoder().encode(reply)
        )
        #expect(
            roundTripped.reciprocal == true,
            "the flag must survive the wire — it is what bounds the exchange to one round trip"
        )
    }

    /// A normal push must NOT be marked, or the peer will never reply to it and
    /// the defect is reintroduced in the other direction.
    @Test("An ordinary push is not marked as a reply")
    func ordinaryPushIsNotMarked() throws {
        let push = MPEnvelope(type: "changes", payload: Data("{}".utf8))
        let roundTripped = try JSONDecoder().decode(
            MPEnvelope.self, from: JSONEncoder().encode(push)
        )
        #expect(roundTripped.reciprocal == nil)
        #expect(
            roundTripped.reciprocal != true,
            "an unmarked push must provoke a reply — that is the whole fix"
        )
    }

    /// The reply reuses `getChangesForPeer`, which selects strictly
    /// `sequence > last_sent_sequence`. That is what makes the exchange
    /// terminate on **data** as well as on the flag: once the watermark has
    /// advanced there is nothing left to send, so a fleet at rest stays silent
    /// rather than trading empty frames.
    ///
    /// Note a fresh database is NOT empty here — the migrations themselves
    /// backfill several hundred `_change_log` rows (break policies, job stages,
    /// settings). That is why the reply is gated on "nothing pending" rather
    /// than on "never synced": a brand-new device genuinely does have data to
    /// offer its first peer.
    @Test("Once the watermark has advanced there is nothing left to reply with")
    func advancedWatermarkMeansNothingSent() throws {
        let db = try AppDatabase.openInMemoryDatabase()
        let peer = "peer-A"

        let initial = try ChangeTracker.getChangesForPeer(db: db, peerId: peer)
        #expect(
            !initial.isEmpty,
            "a fresh device carries its migration backfill — this is the data a first sync legitimately offers"
        )

        // Exactly what `recordDelivery` does after a successful send.
        try ChangeTracker.markSynced(
            db: db, ids: initial.compactMap { $0.id }, batchId: "test-batch"
        )
        if let maxSequence = initial.compactMap({ $0.sequence }).max() {
            try ChangeTracker.advanceSendWatermark(
                db: db, peerId: peer, lastSequence: Int64(maxSequence)
            )
        }

        let afterDelivery = try ChangeTracker.getChangesForPeer(db: db, peerId: peer)
        #expect(
            afterDelivery.isEmpty,
            "with the watermark advanced the reply finds nothing, which is what terminates the exchange on data"
        )
    }
}

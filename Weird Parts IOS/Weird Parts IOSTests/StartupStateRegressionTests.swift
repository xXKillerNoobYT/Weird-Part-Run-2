import XCTest
@testable import Weird_Parts

/// #1739 — a device that had already joined a company was offered
/// "Create New Business" again on its next launch.
///
/// Reported on build 67: *"it's showing the company sat set up when this device
/// is joining a company it's not a new company"*, in the same session as *"only
/// some of the info is sycing … the user them selves did not sync"*. Those are
/// one event, not two.
///
/// The decision rested entirely on **synced** data — the user roster and the
/// business profile — and that is exactly what fails to arrive when sync is
/// partial. So the app asked "am I a new device?" and answered it with data
/// that comes over the network.
///
/// The consequence is worse than a wrong screen: accepting "Create New
/// Business" on a joined device seeds a second admin and a second set of
/// built-in hats, putting divergent ids for the same natural keys onto the
/// mesh — the collision class #1737 exists to contain.
/// `AppCore` is `@MainActor`, and `startupState` is not `nonisolated` (unlike the
/// 14 sibling pure statics in that file), so every call below is a MainActor
/// call. Annotating the class is correct whether or not the test target
/// defaults to MainActor isolation, and matches `AIFilterCommandAuthorizationTests`.
@MainActor
final class StartupStateRegressionTests: XCTestCase {

    /// The regression. Paired, but nothing replicated yet.
    func testPairedDeviceWithNoRosterIsNotTreatedAsNew() {
        let state = AppCore.startupState(
            hasUsers: false,
            hasProfile: false,
            hasPairedPeer: true
        )
        XCTAssertEqual(
            state, .joinedAwaitingRoster,
            "A device that has paired has joined a company. Offering it the create-company path seeds a second admin and a second set of hats."
        )
        XCTAssertNotEqual(state, .newDevice)
    }

    /// Pairing outranks the business profile too: a joined device whose profile
    /// arrived but whose users did not must not be pushed through first-admin
    /// seeding, which would create the same divergence.
    func testPairedDeviceWithProfileButNoUsersDoesNotSeedAnAdmin() {
        let state = AppCore.startupState(
            hasUsers: false,
            hasProfile: true,
            hasPairedPeer: true
        )
        XCTAssertEqual(state, .joinedAwaitingRoster)
        XCTAssertNotEqual(
            state, .needsFirstAdmin,
            "Seeding a first admin on a joined device is the same defect by another route."
        )
    }

    /// The genuinely new device must still get onboarding — the fix must not
    /// strand a first-run user.
    func testTrulyNewDeviceStillGetsOnboarding() {
        XCTAssertEqual(
            AppCore.startupState(hasUsers: false, hasProfile: false, hasPairedPeer: false),
            .newDevice
        )
    }

    /// The pre-existing edge case is preserved: profile present, no admin yet,
    /// never paired.
    func testProfileWithoutUsersOrPairingStillNeedsFirstAdmin() {
        XCTAssertEqual(
            AppCore.startupState(hasUsers: false, hasProfile: true, hasPairedPeer: false),
            .needsFirstAdmin
        )
    }

    /// Any device holding users is simply ready, however it got them.
    func testDeviceWithUsersIsReady() {
        for hasProfile in [true, false] {
            for hasPairedPeer in [true, false] {
                XCTAssertEqual(
                    AppCore.startupState(
                        hasUsers: true,
                        hasProfile: hasProfile,
                        hasPairedPeer: hasPairedPeer
                    ),
                    .ready,
                    "users present should always mean ready (profile=\(hasProfile) paired=\(hasPairedPeer))"
                )
            }
        }
    }

    /// Exhaustive: the create-company path is reachable from exactly one of the
    /// eight input combinations. This is the property that matters — a future
    /// edit that widens `.newDevice` reopens #1739.
    func testOnlyOneCombinationOffersTheCreateCompanyPath() {
        var newDeviceCombinations = 0
        for hasUsers in [true, false] {
            for hasProfile in [true, false] {
                for hasPairedPeer in [true, false] {
                    if AppCore.startupState(
                        hasUsers: hasUsers,
                        hasProfile: hasProfile,
                        hasPairedPeer: hasPairedPeer
                    ) == .newDevice {
                        newDeviceCombinations += 1
                        XCTAssertFalse(hasUsers)
                        XCTAssertFalse(hasProfile)
                        XCTAssertFalse(hasPairedPeer)
                    }
                }
            }
        }
        XCTAssertEqual(
            newDeviceCombinations, 1,
            "Only a device with no users, no profile and no pairing may be offered the create-company path."
        )
    }
}

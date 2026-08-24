import XCTest
@testable import Weird_Parts

/// #1739 — a device that had already joined a company was offered
/// "Create New Business" again on its next launch.
///
/// Reported on build 67: *"it's showing the company setup when this device
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

    func testOnlyVerifiedJoinerSettingsSignalAJoinedDevice() {
        XCTAssertTrue(
            AppCore.hasVerifiedJoinerPairing(syncSettings: [
                "paired_shop_device_id": "host-device",
                "device_pairing_verified_at": "2026-08-23T14:00:00Z",
            ])
        )
        XCTAssertFalse(
            AppCore.hasVerifiedJoinerPairing(syncSettings: [
                "paired_shop_device_id": "host-device",
            ])
        )
        XCTAssertFalse(
            AppCore.hasVerifiedJoinerPairing(syncSettings: [
                "device_pairing_verified_at": "2026-08-23T14:00:00Z",
            ])
        )
        XCTAssertFalse(AppCore.hasVerifiedJoinerPairing(syncSettings: [:]))
    }

    /// The regression. Verified joiner pairing, but nothing replicated yet.
    func testJoinedDeviceWithNoRosterIsNotTreatedAsNew() {
        let state = AppCore.startupState(
            hasUsers: false,
            hasProfile: false,
            hasVerifiedJoinerPairing: true
        )
        XCTAssertEqual(
            state, .joinedAwaitingRoster,
            "A device that has completed verified pairing has joined a company. Offering it the create-company path seeds a second admin and a second set of hats."
        )
        XCTAssertNotEqual(state, .newDevice)
    }

    /// Verified joiner pairing outranks the business profile too: a joined device
    /// whose profile arrived but whose users did not must not be pushed through
    /// first-admin seeding, which would create the same divergence.
    func testJoinedDeviceWithProfileButNoUsersDoesNotSeedAnAdmin() {
        let state = AppCore.startupState(
            hasUsers: false,
            hasProfile: true,
            hasVerifiedJoinerPairing: true
        )
        XCTAssertEqual(state, .joinedAwaitingRoster)
        XCTAssertNotEqual(
            state, .needsFirstAdmin,
            "Seeding a first admin on a joined device is the same defect by another route."
        )
    }

    /// A joined device with no roster must remain on the retryable full-sync
    /// path. Login's incremental sync cannot fetch pre-pairing records.
    func testJoinedAwaitingRosterIsDistinctFromTheLoginReadyState() {
        XCTAssertEqual(
            AppCore.startupState(
                hasUsers: false,
                hasProfile: false,
                hasVerifiedJoinerPairing: true
            ),
            .joinedAwaitingRoster
        )
    }

    /// The company-setup wizard creates first-device rows. A joined admin with
    /// a false local completion flag must not be routed there after login.
    func testJoinedAdminSkipsCompanySetupWizard() {
        XCTAssertFalse(
            WiredPartIOSApp.shouldShowCompanySetup(
                isAdmin: true,
                hasCompletedCompanySetup: false,
                joinedExistingBusiness: true
            )
        )
    }

    /// A host gains trusted peers when others join it, but it does not acquire
    /// the joiner-only verified-pairing settings. It must retain company setup
    /// when the local completion flag is still false.
    func testHostWithTrustedPeersRetainsCompanySetupBehavior() {
        let hostState = AppCore.startupState(
            hasUsers: true,
            hasProfile: true,
            hasVerifiedJoinerPairing: false
        )
        XCTAssertEqual(hostState, .ready)
        XCTAssertTrue(
            WiredPartIOSApp.shouldShowCompanySetup(
                isAdmin: true,
                hasCompletedCompanySetup: false,
                joinedExistingBusiness: false
            )
        )
    }

    /// The genuinely new device must still get onboarding — the fix must not
    /// strand a first-run user.
    func testTrulyNewDeviceStillGetsOnboarding() {
        XCTAssertEqual(
            AppCore.startupState(
                hasUsers: false,
                hasProfile: false,
                hasVerifiedJoinerPairing: false
            ),
            .newDevice
        )
    }

    /// The pre-existing edge case is preserved: profile present, no admin yet,
    /// never paired.
    func testProfileWithoutUsersOrPairingStillNeedsFirstAdmin() {
        XCTAssertEqual(
            AppCore.startupState(
                hasUsers: false,
                hasProfile: true,
                hasVerifiedJoinerPairing: false
            ),
            .needsFirstAdmin
        )
    }

    /// Any device holding users is simply ready, however it got them.
    func testDeviceWithUsersIsReady() {
        for hasProfile in [true, false] {
            for hasVerifiedJoinerPairing in [true, false] {
                XCTAssertEqual(
                    AppCore.startupState(
                        hasUsers: true,
                        hasProfile: hasProfile,
                        hasVerifiedJoinerPairing: hasVerifiedJoinerPairing
                    ),
                    .ready,
                    "users present should always mean ready (profile=\(hasProfile) joined=\(hasVerifiedJoinerPairing))"
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
                for hasVerifiedJoinerPairing in [true, false] {
                    if AppCore.startupState(
                        hasUsers: hasUsers,
                        hasProfile: hasProfile,
                        hasVerifiedJoinerPairing: hasVerifiedJoinerPairing
                    ) == .newDevice {
                        newDeviceCombinations += 1
                        XCTAssertFalse(hasUsers)
                        XCTAssertFalse(hasProfile)
                        XCTAssertFalse(hasVerifiedJoinerPairing)
                    }
                }
            }
        }
        XCTAssertEqual(
            newDeviceCombinations, 1,
            "Only a device with no users, no profile and no verified joiner pairing may be offered the create-company path."
        )
    }
}

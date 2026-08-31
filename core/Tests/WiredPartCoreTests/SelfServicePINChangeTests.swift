import Testing
@testable import WiredPartCore

struct SelfServicePINChangeTests {
    @Test("Wrong current PIN rejects the change and preserves the existing credential")
    func wrongCurrentPINPreservesExistingPIN() throws {
        let env = try E2ETestHelpers.setUp(adminPin: "1234")

        #expect(throws: AuthService.AuthError.self) {
            try env.auth.changePin(
                userId: env.adminUserId,
                oldPin: "9999",
                newPin: "5678"
            )
        }

        let originalPIN = try env.auth.authenticateByPin(userId: env.adminUserId, pin: "1234")
        let rejectedNewPIN = try env.auth.authenticateByPin(userId: env.adminUserId, pin: "5678")
        #expect(originalPIN.success)
        #expect(!rejectedNewPIN.success)
    }

    @Test("Correct current PIN changes the credential to the confirmed new PIN")
    func successfulChangeReplacesPIN() throws {
        let env = try E2ETestHelpers.setUp(adminPin: "1234")

        #expect(
            try env.auth.changePin(
                userId: env.adminUserId,
                oldPin: "1234",
                newPin: "5678"
            )
        )

        let oldPIN = try env.auth.authenticateByPin(userId: env.adminUserId, pin: "1234")
        let newPIN = try env.auth.authenticateByPin(userId: env.adminUserId, pin: "5678")
        #expect(!oldPIN.success)
        #expect(newPIN.success)
    }
}

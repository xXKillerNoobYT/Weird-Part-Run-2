import Testing
@testable import Weird_Parts

@MainActor
struct PINConfirmationValidationTests {
    @Test("Matching PIN and confirmation pass validation")
    func matchingPINsPass() {
        #expect(PINConfirmationValidator.newPINError(pin: "2468", confirmation: "2468") == nil)
    }

    @Test("Mismatched PIN confirmation is rejected without echoing either PIN")
    func mismatchIsRejectedWithoutSecrets() {
        let message = PINConfirmationValidator.newPINError(pin: "2468", confirmation: "1357")

        #expect(message == "PIN entries do not match.")
        #expect(message?.contains("2468") == false)
        #expect(message?.contains("1357") == false)
    }

    @Test("Missing PIN confirmation is rejected")
    func missingConfirmationIsRejected() {
        #expect(
            PINConfirmationValidator.newPINError(pin: "2468", confirmation: "")
                == "Confirm the new PIN."
        )
    }

    @Test("Self-service change requires the current PIN")
    func missingCurrentPINIsRejected() {
        #expect(
            PINConfirmationValidator.changePINError(
                currentPIN: "",
                newPIN: "2468",
                confirmation: "2468"
            ) == "Enter your current PIN."
        )
    }

    @Test("New PIN must contain four to eight digits")
    func invalidFormatIsRejected() {
        #expect(
            PINConfirmationValidator.newPINError(pin: "12ab", confirmation: "12ab")
                == "PIN must be 4–8 digits."
        )
    }
}

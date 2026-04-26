import Foundation
import Testing
@testable import WiredPartCore

@Suite("FieldEncryption Tests")
struct FieldEncryptionTests {

    // MARK: - Nil / empty pass-throughs

    @Test("encrypt(nil) returns nil")
    func testEncryptNilReturnsNil() throws {
        let result = try FieldEncryption.encrypt(nil)
        #expect(result == nil)
    }

    @Test("encrypt empty string returns empty string")
    func testEncryptEmptyReturnsEmpty() throws {
        let result = try FieldEncryption.encrypt("")
        #expect(result == "")
    }

    @Test("decrypt(nil) returns nil")
    func testDecryptNilReturnsNil() throws {
        let result = try FieldEncryption.decrypt(nil)
        #expect(result == nil)
    }

    @Test("decrypt empty string returns empty string")
    func testDecryptEmptyReturnsEmpty() throws {
        let result = try FieldEncryption.decrypt("")
        #expect(result == "")
    }

    // MARK: - Round-trip

    @Test("encrypt then decrypt returns original value")
    func testRoundTrip() throws {
        let original = "user@example.com"
        let encrypted = try FieldEncryption.encrypt(original)
        #expect(encrypted != original, "Encrypted value should differ from plaintext")
        let decrypted = try FieldEncryption.decrypt(encrypted)
        #expect(decrypted == original)
    }

    @Test("round-trip preserves unicode / special characters")
    func testRoundTripUnicode() throws {
        let original = "José+Test@ñ.com"
        let decrypted = try FieldEncryption.decrypt(try FieldEncryption.encrypt(original))
        #expect(decrypted == original)
    }

    @Test("round-trip preserves phone number")
    func testRoundTripPhone() throws {
        let original = "+1 (555) 867-5309"
        let decrypted = try FieldEncryption.decrypt(try FieldEncryption.encrypt(original))
        #expect(decrypted == original)
    }

    @Test("consecutive encryptions produce different ciphertexts (random nonce)")
    func testDifferentNonces() throws {
        let value = "test@example.com"
        let enc1 = try FieldEncryption.encrypt(value)
        let enc2 = try FieldEncryption.encrypt(value)
        // AES-GCM uses a random nonce, so two encryptions must produce different output.
        #expect(enc1 != enc2)
    }

    // MARK: - Legacy plaintext pass-through

    @Test("decrypt of non-base64 string returns the string unchanged")
    func testDecryptNonBase64Passthrough() throws {
        let plaintext = "not-base64!@#"
        let result = try FieldEncryption.decrypt(plaintext)
        #expect(result == plaintext)
    }

    @Test("decrypt of a plain email string passes through unchanged")
    func testDecryptPlaintextEmailPassthrough() throws {
        // Simulates a legacy row stored before encryption was introduced.
        let legacyEmail = "legacy@example.com"
        let result = try FieldEncryption.decrypt(legacyEmail)
        #expect(result == legacyEmail)
    }

    // MARK: - Encrypted values are not plaintext

    @Test("encrypted value is not the same as input")
    func testEncryptedDiffersFromInput() throws {
        let input = "secret@domain.com"
        let encrypted = try FieldEncryption.encrypt(input)
        #expect(encrypted != input)
    }

    @Test("encrypted value is valid base64")
    func testEncryptedIsBase64() throws {
        let encrypted = try FieldEncryption.encrypt("test@example.com")
        let decoded = encrypted.flatMap { Data(base64Encoded: $0) }
        #expect(decoded != nil, "Encrypted value should be valid base64")
    }
}

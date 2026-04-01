import Testing
import Foundation
import CryptoKit
@testable import WiredPartCore

@Suite("SyncCrypto Tests")
struct SyncCryptoTests {

    // MARK: - Helpers

    /// Create a signed certificate for testing.
    private func makeSignedCert(
        deviceId: String = "test-device-001",
        companyId: String = "test-company-001",
        expiresAt: String? = "2099-12-31T23:59:59Z",
        signingKey: Curve25519.Signing.PrivateKey? = nil
    ) -> (auth: SyncAuth, companyPublicKeyB64: String) {
        let adminKey = signingKey ?? Curve25519.Signing.PrivateKey()
        let deviceKey = Curve25519.Signing.PrivateKey()

        let payload = CertificatePayload(
            deviceId: deviceId,
            companyId: companyId,
            publicKey: deviceKey.publicKey.rawRepresentation.base64EncodedString(),
            issuedAt: "2026-01-01T00:00:00Z",
            expiresAt: expiresAt
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let certData = try! encoder.encode(payload)
        let signature = try! adminKey.signature(for: certData)

        let auth = SyncAuth(
            certificateData: certData.base64EncodedString(),
            certificateSignature: signature.base64EncodedString(),
            devicePublicKey: deviceKey.publicKey.rawRepresentation.base64EncodedString()
        )

        let companyPubB64 = adminKey.publicKey.rawRepresentation.base64EncodedString()
        return (auth: auth, companyPublicKeyB64: companyPubB64)
    }

    // MARK: - verifySyncAuth Tests

    @Test("No company key returns AllowedNoKey")
    func testNoCompanyKey() {
        let result = SyncCrypto.verifySyncAuth(
            auth: SyncAuth(),
            expectedCompanyId: "any",
            companyPublicKeyB64: nil
        )
        #expect(result == .allowedNoKey)
    }

    @Test("Company key configured but no cert returns Required")
    func testMissingCert() {
        let result = SyncCrypto.verifySyncAuth(
            auth: SyncAuth(),
            expectedCompanyId: "test-company",
            companyPublicKeyB64: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
        )
        #expect(result == .required)
    }

    @Test("Valid cert and signature returns Verified")
    func testValidCert() {
        let (auth, pubKey) = makeSignedCert(
            deviceId: "device-123",
            companyId: "company-abc"
        )
        let result = SyncCrypto.verifySyncAuth(
            auth: auth,
            expectedCompanyId: "company-abc",
            companyPublicKeyB64: pubKey
        )
        #expect(result == .verified(deviceId: "device-123", companyId: "company-abc"))
    }

    @Test("Wrong company_id in cert returns Rejected")
    func testWrongCompanyId() {
        let (auth, pubKey) = makeSignedCert(companyId: "company-A")
        let result = SyncCrypto.verifySyncAuth(
            auth: auth,
            expectedCompanyId: "company-B",
            companyPublicKeyB64: pubKey
        )
        if case .rejected(let reason) = result {
            #expect(reason.contains("mismatch"))
        } else {
            Issue.record("Expected rejected, got \(result)")
        }
    }

    @Test("Invalid base64 in company key returns Rejected")
    func testBadBase64Key() {
        let auth = SyncAuth(
            certificateData: "validbase64==",
            certificateSignature: "validbase64=="
        )
        let result = SyncCrypto.verifySyncAuth(
            auth: auth,
            expectedCompanyId: "test",
            companyPublicKeyB64: "not-valid-base64!!!"
        )
        if case .rejected = result {
            // Expected
        } else {
            Issue.record("Expected rejected, got \(result)")
        }
    }

    @Test("Invalid base64 in signature returns Rejected")
    func testBadBase64Signature() {
        let adminKey = Curve25519.Signing.PrivateKey()
        let certData = "{}".data(using: .utf8)!
        let auth = SyncAuth(
            certificateData: certData.base64EncodedString(),
            certificateSignature: "not-valid-base64!!!"
        )
        let result = SyncCrypto.verifySyncAuth(
            auth: auth,
            expectedCompanyId: "test",
            companyPublicKeyB64: adminKey.publicKey.rawRepresentation.base64EncodedString()
        )
        if case .rejected = result {
            // Expected
        } else {
            Issue.record("Expected rejected, got \(result)")
        }
    }

    @Test("Tampered data returns Rejected")
    func testTamperedData() {
        let (auth, pubKey) = makeSignedCert(companyId: "company-A")
        // Tamper: use different cert data but keep original signature
        let tamperedData = "{\"device_id\":\"hacker\",\"company_id\":\"company-A\",\"public_key\":\"fake\"}"
        let tamperedAuth = SyncAuth(
            certificateData: tamperedData.data(using: .utf8)!.base64EncodedString(),
            certificateSignature: auth.certificateSignature
        )
        let result = SyncCrypto.verifySyncAuth(
            auth: tamperedAuth,
            expectedCompanyId: "company-A",
            companyPublicKeyB64: pubKey
        )
        if case .rejected(let reason) = result {
            #expect(reason.contains("signature"))
        } else {
            Issue.record("Expected rejected, got \(result)")
        }
    }

    @Test("Expired certificate returns Rejected")
    func testExpiredCert() {
        let (auth, pubKey) = makeSignedCert(
            companyId: "test-co",
            expiresAt: "2020-01-01T00:00:00Z"
        )
        let result = SyncCrypto.verifySyncAuth(
            auth: auth,
            expectedCompanyId: "test-co",
            companyPublicKeyB64: pubKey
        )
        if case .rejected(let reason) = result {
            #expect(reason.contains("expired"))
        } else {
            Issue.record("Expected rejected, got \(result)")
        }
    }

    @Test("Certificate with no expiry returns Verified")
    func testNoExpiryCert() {
        let (auth, pubKey) = makeSignedCert(
            deviceId: "dev-1",
            companyId: "co-1",
            expiresAt: nil
        )
        let result = SyncCrypto.verifySyncAuth(
            auth: auth,
            expectedCompanyId: "co-1",
            companyPublicKeyB64: pubKey
        )
        #expect(result == .verified(deviceId: "dev-1", companyId: "co-1"))
    }

    // MARK: - X25519 Key Agreement + AES-GCM

    @Test("generateKeyAgreementPair produces 32-byte base64 keys")
    func testGenerateKeyAgreementPair() {
        let (priv, pub) = SyncCrypto.generateKeyAgreementPair()
        #expect(!priv.isEmpty)
        #expect(!pub.isEmpty)
        let privData = Data(base64Encoded: priv)
        let pubData = Data(base64Encoded: pub)
        #expect(privData?.count == 32)
        #expect(pubData?.count == 32)
    }

    @Test("Two devices derive the same shared key via ECDH")
    func testECDHSharedKeySymmetry() throws {
        let (privA, pubA) = SyncCrypto.generateKeyAgreementPair()
        let (privB, pubB) = SyncCrypto.generateKeyAgreementPair()

        let keyAB = try SyncCrypto.deriveSharedKeyData(ourPrivateKeyB64: privA, theirPublicKeyB64: pubB)
        let keyBA = try SyncCrypto.deriveSharedKeyData(ourPrivateKeyB64: privB, theirPublicKeyB64: pubA)

        #expect(keyAB == keyBA)
        #expect(keyAB.count == 32)
    }

    @Test("Different peer pairs produce different shared keys")
    func testECDHUniqueness() throws {
        let (privA, _) = SyncCrypto.generateKeyAgreementPair()
        let (_, pubB) = SyncCrypto.generateKeyAgreementPair()
        let (_, pubC) = SyncCrypto.generateKeyAgreementPair()

        let keyAB = try SyncCrypto.deriveSharedKeyData(ourPrivateKeyB64: privA, theirPublicKeyB64: pubB)
        let keyAC = try SyncCrypto.deriveSharedKeyData(ourPrivateKeyB64: privA, theirPublicKeyB64: pubC)

        #expect(keyAB != keyAC)
    }

    @Test("AES-GCM encrypt/decrypt round-trip")
    func testAESGCMRoundTrip() throws {
        let (privA, pubA) = SyncCrypto.generateKeyAgreementPair()
        let (privB, pubB) = SyncCrypto.generateKeyAgreementPair()
        let keyData = try SyncCrypto.deriveSharedKeyData(ourPrivateKeyB64: privA, theirPublicKeyB64: pubB)

        let plaintext = Data("{\"device_id\":\"test\",\"changes\":[]}".utf8)
        let encrypted = try SyncCrypto.encryptAESGCM(data: plaintext, keyData: keyData)

        // Encrypted output must differ from plaintext
        #expect(encrypted != plaintext)
        // Nonce (12) + at least 1 byte ciphertext + tag (16)
        #expect(encrypted.count >= 29)

        // Decrypt from the other side using the symmetric key
        let receiverKeyData = try SyncCrypto.deriveSharedKeyData(ourPrivateKeyB64: privB, theirPublicKeyB64: pubA)
        let decrypted = try SyncCrypto.decryptAESGCM(data: encrypted, keyData: receiverKeyData)

        #expect(decrypted == plaintext)
    }

    @Test("AES-GCM detects tampered ciphertext")
    func testAESGCMTamperDetection() throws {
        let (priv, pub) = SyncCrypto.generateKeyAgreementPair()
        let keyData = try SyncCrypto.deriveSharedKeyData(ourPrivateKeyB64: priv, theirPublicKeyB64: pub)

        let plaintext = Data("sensitive sync payload".utf8)
        var encrypted = try SyncCrypto.encryptAESGCM(data: plaintext, keyData: keyData)

        // Flip a byte in the ciphertext (after the 12-byte nonce)
        encrypted[15] ^= 0xFF

        do {
            _ = try SyncCrypto.decryptAESGCM(data: encrypted, keyData: keyData)
            Issue.record("Expected decryption to throw on tampered data")
        } catch {
            // Expected: AES-GCM authentication tag mismatch
        }
    }

    @Test("deriveSharedKeyData rejects invalid base64")
    func testDeriveSharedKeyInvalidBase64() {
        do {
            _ = try SyncCrypto.deriveSharedKeyData(ourPrivateKeyB64: "!!!bad", theirPublicKeyB64: "also-bad")
            Issue.record("Expected throw for invalid base64")
        } catch {
            // Expected
        }
    }

    // MARK: - Key Generation + Signing Round-Trip

    @Test("generateKeyPair + sign + verify round-trip")
    func testKeyGenSignVerify() throws {
        let (privateKeyB64, publicKeyB64) = SyncCrypto.generateKeyPair()

        // Create a certificate payload
        let payload = CertificatePayload(
            deviceId: "roundtrip-device",
            companyId: "roundtrip-company",
            publicKey: publicKeyB64,
            issuedAt: SyncCrypto.currentTimestamp(),
            expiresAt: "2099-12-31T23:59:59Z"
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let certData = try encoder.encode(payload)

        // Sign with our generated private key
        let signatureB64 = try SyncCrypto.sign(data: certData, privateKeyB64: privateKeyB64)

        // Verify using the matching public key
        let auth = SyncAuth(
            certificateData: certData.base64EncodedString(),
            certificateSignature: signatureB64
        )
        let result = SyncCrypto.verifySyncAuth(
            auth: auth,
            expectedCompanyId: "roundtrip-company",
            companyPublicKeyB64: publicKeyB64
        )
        #expect(result == .verified(deviceId: "roundtrip-device", companyId: "roundtrip-company"))
    }
}

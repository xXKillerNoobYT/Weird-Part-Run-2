import Foundation
import CryptoKit

// MARK: - Certificate Payload

/// The JSON payload embedded in a sync authentication certificate.
/// Signed by the company admin's Ed25519 private key.
public struct CertificatePayload: Codable, Sendable {
    public let deviceId: String
    public let companyId: String
    public let publicKey: String       // device's own Ed25519 pubkey (base64)
    public let issuedAt: String?
    public let expiresAt: String?

    public init(
        deviceId: String,
        companyId: String,
        publicKey: String,
        issuedAt: String? = nil,
        expiresAt: String? = nil
    ) {
        self.deviceId = deviceId
        self.companyId = companyId
        self.publicKey = publicKey
        self.issuedAt = issuedAt
        self.expiresAt = expiresAt
    }

    enum CodingKeys: String, CodingKey {
        case deviceId = "device_id"
        case companyId = "company_id"
        case publicKey = "public_key"
        case issuedAt = "issued_at"
        case expiresAt = "expires_at"
    }
}

// MARK: - Sync Auth

/// Authentication fields included in sync push/pull requests.
/// All fields optional for backward compatibility with Phase 4 clients
/// (which have no certificate infrastructure).
public struct SyncAuth: Codable, Sendable {
    public var certificateData: String?       // base64-encoded certificate JSON
    public var certificateSignature: String?  // base64-encoded Ed25519 signature (64 bytes)
    public var devicePublicKey: String?       // device's Ed25519 public key (base64)

    public init(
        certificateData: String? = nil,
        certificateSignature: String? = nil,
        devicePublicKey: String? = nil
    ) {
        self.certificateData = certificateData
        self.certificateSignature = certificateSignature
        self.devicePublicKey = devicePublicKey
    }

    enum CodingKeys: String, CodingKey {
        case certificateData = "certificate_data"
        case certificateSignature = "certificate_signature"
        case devicePublicKey = "device_public_key"
    }
}

// MARK: - Auth Result

/// Result of verifying sync authentication.
public enum AuthResult: Sendable, Equatable {
    /// Certificate is valid: device and company identity confirmed.
    case verified(deviceId: String, companyId: String)
    /// No company public key configured — Phase 4 compatibility mode.
    /// All requests are allowed based on company_id matching only.
    case allowedNoKey
    /// Certificate was present but verification failed.
    case rejected(reason: String)
    /// Company key is configured but the request has no certificate.
    case required
}

// MARK: - SyncCrypto

/// Ed25519 certificate verification for sync authentication.
///
/// Ported from: `src-tauri/src/crypto.rs`
///
/// Uses CryptoKit `Curve25519.Signing` to replace Rust's `ed25519-dalek`.
/// Public keys are 32 bytes, signatures are 64 bytes, both base64-encoded for transport.
public enum SyncCrypto {

    // MARK: - Pairing Codes

    private static let pairingCodeCharacters = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")

    /// Generate a one-time human-enterable pairing code.
    public static func generatePairingCode() -> String {
        var generator = SystemRandomNumberGenerator()
        return String((0..<8).map { _ in
            pairingCodeCharacters.randomElement(using: &generator)!
        })
    }

    /// Format a normalized pairing code for display as `ABCD-1234`.
    public static func formattedPairingCode(_ code: String) -> String? {
        guard let normalized = normalizedPairingCode(code) else { return nil }
        let splitIndex = normalized.index(normalized.startIndex, offsetBy: 4)
        return "\(normalized[..<splitIndex])-\(normalized[splitIndex...])"
    }

    /// Normalize a human-entered pairing code for comparison.
    ///
    /// Codes are eight alphanumeric characters, commonly displayed as
    /// `ABCD-1234`. Spaces and hyphens are ignored so users can type the
    /// displayed code naturally, but other characters fail closed.
    public static func normalizedPairingCode(_ code: String) -> String? {
        var normalized = ""
        normalized.reserveCapacity(8)

        for scalar in code.unicodeScalars {
            switch scalar.value {
            case 9...13, 32, 45:
                continue
            case 48...57, 65...90:
                normalized.append(Character(scalar))
            case 97...122:
                guard let uppercased = UnicodeScalar(scalar.value - 32) else { return nil }
                normalized.append(Character(uppercased))
            default:
                return nil
            }
        }

        guard normalized.count == 8,
              normalized.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else {
            return nil
        }
        return normalized
    }

    /// Digest a normalized pairing code before storing it in server state.
    public static func pairingCodeDigest(_ normalizedCode: String) -> Data {
        Data(SHA256.hash(data: Data(normalizedCode.utf8)))
    }

    /// Code-authenticated pairing proof sent instead of the one-time code.
    ///
    /// The proof is deliberately domain-separated from stored code digests and
    /// from LAN traffic encryption. It binds the joiner's device id and X25519
    /// public key so a captured proof cannot be reused for a different key.
    public static func pairingProof(
        normalizedCode: String,
        deviceId: String,
        clientPublicKeyB64: String
    ) -> String {
        let transcript = [
            "wiredpart-sync-pairing-proof-v1",
            deviceId,
            clientPublicKeyB64,
        ].joined(separator: "\n")
        let key = SymmetricKey(data: pairingCodeDigest(normalizedCode))
        return Data(HMAC<SHA256>.authenticationCode(
            for: Data(transcript.utf8),
            using: key
        )).base64EncodedString()
    }

    public static func verifyPairingProof(
        _ proof: String?,
        normalizedCode: String,
        deviceId: String,
        clientPublicKeyB64: String
    ) -> Bool {
        guard let proof else { return false }
        let expected = pairingProof(
            normalizedCode: normalizedCode,
            deviceId: deviceId,
            clientPublicKeyB64: clientPublicKeyB64
        )
        guard let left = Data(base64Encoded: proof),
              let right = Data(base64Encoded: expected),
              left.count == right.count else { return false }
        var diff: UInt8 = 0
        for (l, r) in zip(left, right) { diff |= l ^ r }
        return diff == 0
    }

    /// Constant-time pairing-code verification against a stored digest.
    public static func verifyPairingCode(_ candidate: String, expectedDigest: Data) -> Bool {
        guard let normalized = normalizedPairingCode(candidate) else { return false }
        let candidateDigest = pairingCodeDigest(normalized)
        guard candidateDigest.count == expectedDigest.count else { return false }

        var diff: UInt8 = 0
        for (left, right) in zip(candidateDigest, expectedDigest) {
            diff |= left ^ right
        }
        return diff == 0
    }

    // MARK: - Verification

    /// Verify a sync request's Ed25519 certificate.
    ///
    /// Verification sequence:
    /// 1. If no company public key → `.allowedNoKey` (Phase 4 compat)
    /// 2. If cert fields missing → `.required`
    /// 3. Decode base64 → verify Ed25519 signature
    /// 4. Parse cert JSON → check company_id match → check expiry
    /// 5. Return `.verified`
    public static func verifySyncAuth(
        auth: SyncAuth,
        expectedCompanyId: String,
        companyPublicKeyB64: String?
    ) -> AuthResult {
        // Phase 4 compatibility: no key configured → allow all
        guard let keyB64 = companyPublicKeyB64 else {
            return .allowedNoKey
        }

        // Key is configured but request has no certificate
        guard let certDataB64 = auth.certificateData,
              let certSigB64 = auth.certificateSignature else {
            return .required
        }

        // Decode the company public key (32 bytes)
        guard let keyData = Data(base64Encoded: certDataB64.isEmpty ? "" : keyB64) else {
            return .rejected(reason: "Invalid base64 in company public key")
        }
        let publicKey: Curve25519.Signing.PublicKey
        do {
            publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: keyData)
        } catch {
            return .rejected(reason: "Invalid public key: \(error.localizedDescription)")
        }

        // Decode certificate data (raw bytes of JSON)
        guard let certDataBytes = Data(base64Encoded: certDataB64) else {
            return .rejected(reason: "Invalid base64 in certificate data")
        }

        // Decode signature (64 bytes)
        guard let signatureBytes = Data(base64Encoded: certSigB64) else {
            return .rejected(reason: "Invalid base64 in certificate signature")
        }
        guard signatureBytes.count == 64 else {
            return .rejected(reason: "Signature must be 64 bytes, got \(signatureBytes.count)")
        }

        // Verify the Ed25519 signature
        guard publicKey.isValidSignature(signatureBytes, for: certDataBytes) else {
            return .rejected(reason: "Ed25519 signature verification failed")
        }

        // Parse the certificate JSON
        guard let certString = String(data: certDataBytes, encoding: .utf8) else {
            return .rejected(reason: "Certificate data is not valid UTF-8")
        }
        guard let certJsonData = certString.data(using: .utf8) else {
            return .rejected(reason: "Cannot re-encode certificate string")
        }

        let payload: CertificatePayload
        do {
            let decoder = JSONDecoder()
            payload = try decoder.decode(CertificatePayload.self, from: certJsonData)
        } catch {
            return .rejected(reason: "Cannot parse certificate JSON: \(error.localizedDescription)")
        }

        // Check company_id matches
        guard payload.companyId == expectedCompanyId else {
            return .rejected(reason: "Certificate company_id mismatch: expected \(expectedCompanyId), got \(payload.companyId)")
        }

        // Check expiry (lexicographic string comparison on ISO 8601)
        if let expiresAt = payload.expiresAt {
            let now = currentTimestamp()
            if expiresAt < now {
                return .rejected(reason: "Certificate expired at \(expiresAt)")
            }
        }

        return .verified(deviceId: payload.deviceId, companyId: payload.companyId)
    }

    // MARK: - Key Generation

    /// Generate a new Ed25519 signing key pair.
    /// Returns base64-encoded private key (32 bytes) and public key (32 bytes).
    public static func generateKeyPair() -> (privateKey: String, publicKey: String) {
        let privateKey = Curve25519.Signing.PrivateKey()
        let privateKeyB64 = privateKey.rawRepresentation.base64EncodedString()
        let publicKeyB64 = privateKey.publicKey.rawRepresentation.base64EncodedString()
        return (privateKey: privateKeyB64, publicKey: publicKeyB64)
    }

    // MARK: - Signing

    /// Sign data with an Ed25519 private key.
    /// Returns base64-encoded signature (64 bytes).
    public static func sign(data: Data, privateKeyB64: String) throws -> String {
        guard let keyData = Data(base64Encoded: privateKeyB64) else {
            throw CryptoError.invalidBase64("private key")
        }
        let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: keyData)
        let signature = try privateKey.signature(for: data)
        return signature.base64EncodedString()
    }

    // MARK: - Timestamp

    /// Get current UTC timestamp as ISO 8601 string.
    /// Format: `2026-03-14T12:00:00Z`
    public static func currentTimestamp() -> String { CoreFormatters.nowISO() }

    // MARK: - X25519 Key Agreement

    /// Generate a new X25519 key agreement key pair.
    /// Returns base64-encoded private key (32 bytes) and public key (32 bytes).
    public static func generateKeyAgreementPair() -> (privateKey: String, publicKey: String) {
        let privateKey = Curve25519.KeyAgreement.PrivateKey()
        let privateKeyB64 = privateKey.rawRepresentation.base64EncodedString()
        let publicKeyB64 = privateKey.publicKey.rawRepresentation.base64EncodedString()
        return (privateKey: privateKeyB64, publicKey: publicKeyB64)
    }

    /// Derive a shared 256-bit key from our X25519 private key and a peer's X25519 public key.
    /// Uses HKDF-SHA256 with the WiredPart sync info string as domain separation.
    /// Returns raw key bytes (32 bytes).
    public static func deriveSharedKeyData(
        ourPrivateKeyB64: String,
        theirPublicKeyB64: String
    ) throws -> Data {
        guard let ourRaw = Data(base64Encoded: ourPrivateKeyB64) else {
            throw CryptoError.invalidBase64("our private key")
        }
        guard let theirRaw = Data(base64Encoded: theirPublicKeyB64) else {
            throw CryptoError.invalidBase64("their public key")
        }
        let ourKey = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: ourRaw)
        let theirKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: theirRaw)
        let sharedSecret = try ourKey.sharedSecretFromKeyAgreement(with: theirKey)
        let symmetricKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data(),
            sharedInfo: Data("wiredpart-sync-v1".utf8),
            outputByteCount: 32
        )
        return symmetricKey.withUnsafeBytes { Data($0) }
    }

    public static func derivePairingSharedKeyData(
        ourPrivateKeyB64: String,
        theirPublicKeyB64: String,
        normalizedCode: String,
        clientPublicKeyB64: String,
        serverPublicKeyB64: String
    ) throws -> Data {
        guard let ourRaw = Data(base64Encoded: ourPrivateKeyB64) else {
            throw CryptoError.invalidBase64("our private key")
        }
        guard let theirRaw = Data(base64Encoded: theirPublicKeyB64) else {
            throw CryptoError.invalidBase64("their public key")
        }
        let ourKey = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: ourRaw)
        let theirKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: theirRaw)
        let sharedSecret = try ourKey.sharedSecretFromKeyAgreement(with: theirKey)
        let codeSalt = pairingCodeDigest(normalizedCode)
        let transcript = [
            "wiredpart-sync-pairing-response-v1",
            clientPublicKeyB64,
            serverPublicKeyB64,
        ].joined(separator: "\n")
        let symmetricKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: codeSalt,
            sharedInfo: Data(transcript.utf8),
            outputByteCount: 32
        )
        return symmetricKey.withUnsafeBytes { Data($0) }
    }

    // MARK: - AES-GCM Payload Encryption

    /// Encrypt data using AES-GCM.
    /// Returns the sealed box combined bytes: nonce (12) + ciphertext + tag (16).
    public static func encryptAESGCM(data: Data, keyData: Data, aad: Data? = nil) throws -> Data {
        let key = SymmetricKey(data: keyData)
        let sealedBox = if let aad {
            try AES.GCM.seal(data, using: key, authenticating: aad)
        } else {
            try AES.GCM.seal(data, using: key)
        }
        guard let combined = sealedBox.combined else {
            throw CryptoError.encryptionFailed
        }
        return combined
    }

    /// Decrypt AES-GCM sealed box bytes (nonce + ciphertext + tag).
    public static func decryptAESGCM(data: Data, keyData: Data, aad: Data? = nil) throws -> Data {
        let key = SymmetricKey(data: keyData)
        let sealedBox = try AES.GCM.SealedBox(combined: data)
        if let aad {
            return try AES.GCM.open(sealedBox, using: key, authenticating: aad)
        }
        return try AES.GCM.open(sealedBox, using: key)
    }

    // MARK: - Errors

    public enum CryptoError: Error, LocalizedError {
        case invalidBase64(String)
        case encryptionFailed

        public var errorDescription: String? {
            switch self {
            case .invalidBase64(let field):
                return "Invalid base64 encoding in \(field)"
            case .encryptionFailed:
                return "AES-GCM encryption failed (combined representation unavailable)"
            }
        }
    }
}

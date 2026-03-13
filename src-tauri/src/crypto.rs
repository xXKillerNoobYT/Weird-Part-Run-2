/// Ed25519 Certificate Verification for P2P Sync
///
/// Verifies that incoming sync requests come from devices belonging to the
/// same company. Each device has a certificate (JSON) signed by the company's
/// admin key using Ed25519. The admin key's public half is stored on every
/// device during initial setup.
///
/// Certificate format (JSON string, base64-encoded in transport):
/// ```json
/// {
///   "device_id": "uuid-of-device",
///   "company_id": "company-uuid",
///   "public_key": "base64-device-public-key",
///   "issued_at": "2026-01-01T00:00:00Z",
///   "expires_at": "2027-01-01T00:00:00Z"
/// }
/// ```
///
/// Verification steps:
/// 1. Decode the company public key (base64 → 32 bytes → Ed25519 VerifyingKey)
/// 2. Decode the certificate signature (base64 → 64 bytes → Ed25519 Signature)
/// 3. Verify: company_pub_key.verify(certificate_data_bytes, signature) == ok
/// 4. Parse the certificate JSON and check company_id matches the request
/// 5. (Optional) Check certificate expiry
///
/// Graceful degradation: If no company public key is configured, the sync
/// server falls back to company_id-only auth (Phase 4 behavior). This ensures
/// backward compatibility during initial setup / bootstrap.

use base64::Engine;
use ed25519_dalek::{Signature, Verifier, VerifyingKey};
use serde::Deserialize;

/// Parsed certificate payload (the JSON inside certificate_data)
#[derive(Debug, Deserialize)]
#[allow(dead_code)]
pub struct CertificatePayload {
    pub device_id: String,
    pub company_id: String,
    pub public_key: String,
    pub issued_at: Option<String>,
    pub expires_at: Option<String>,
}

/// Auth fields that can be included in sync push/pull requests.
/// All fields are optional for backward compatibility with Phase 4 clients.
#[derive(Debug, Clone, Default, Deserialize)]
pub struct SyncAuth {
    /// Base64-encoded certificate JSON (issued by company admin)
    pub certificate_data: Option<String>,
    /// Base64-encoded Ed25519 signature over the certificate data
    pub certificate_signature: Option<String>,
    /// Device's Ed25519 public key (base64) — for future nonce challenges
    pub device_public_key: Option<String>,
}

/// Result of verifying a sync request's authentication
#[derive(Debug)]
pub enum AuthResult {
    /// Certificate verified — the device belongs to the same company
    Verified {
        device_id: String,
        company_id: String,
    },
    /// No auth provided but server has no company key — allow (Phase 4 compat)
    AllowedNoKey,
    /// Auth provided but verification failed
    Rejected(String),
    /// No auth provided but server requires it (has company key configured)
    Required,
}

/// Verify a sync request's certificate against the company public key.
///
/// Returns `AuthResult::Verified` if the certificate is valid and the
/// company_id in the cert matches `expected_company_id`.
///
/// If `company_public_key_b64` is None, returns `AllowedNoKey` (Phase 4 compat).
/// If it's Some but the request has no cert, returns `Required`.
pub fn verify_sync_auth(
    auth: &SyncAuth,
    expected_company_id: &str,
    company_public_key_b64: Option<&str>,
) -> AuthResult {
    let b64 = base64::engine::general_purpose::STANDARD;

    // No company key configured — Phase 4 compatibility mode
    let Some(pub_key_b64) = company_public_key_b64 else {
        return AuthResult::AllowedNoKey;
    };

    // Company key is configured — cert fields are required
    let (Some(cert_data_b64), Some(cert_sig_b64)) =
        (&auth.certificate_data, &auth.certificate_signature)
    else {
        return AuthResult::Required;
    };

    // Decode the company public key
    let pub_key_bytes = match b64.decode(pub_key_b64) {
        Ok(bytes) => bytes,
        Err(e) => return AuthResult::Rejected(format!("Invalid company public key: {e}")),
    };

    let pub_key_array: [u8; 32] = match pub_key_bytes.try_into() {
        Ok(arr) => arr,
        Err(_) => {
            return AuthResult::Rejected("Company public key must be 32 bytes".into());
        }
    };

    let verifying_key = match VerifyingKey::from_bytes(&pub_key_array) {
        Ok(k) => k,
        Err(e) => return AuthResult::Rejected(format!("Invalid Ed25519 key: {e}")),
    };

    // Decode the certificate data (the raw bytes that were signed)
    let cert_data_bytes = match b64.decode(cert_data_b64) {
        Ok(bytes) => bytes,
        Err(e) => return AuthResult::Rejected(format!("Invalid certificate_data base64: {e}")),
    };

    // Decode the signature
    let sig_bytes = match b64.decode(cert_sig_b64) {
        Ok(bytes) => bytes,
        Err(e) => {
            return AuthResult::Rejected(format!("Invalid certificate_signature base64: {e}"))
        }
    };

    let sig_array: [u8; 64] = match sig_bytes.try_into() {
        Ok(arr) => arr,
        Err(_) => return AuthResult::Rejected("Signature must be 64 bytes".into()),
    };

    let signature = Signature::from_bytes(&sig_array);

    // Verify the Ed25519 signature
    if verifying_key.verify(&cert_data_bytes, &signature).is_err() {
        return AuthResult::Rejected("Ed25519 signature verification failed".into());
    }

    // Parse the certificate JSON to extract device_id and company_id
    let cert_json = match String::from_utf8(cert_data_bytes) {
        Ok(s) => s,
        Err(e) => return AuthResult::Rejected(format!("Certificate data is not valid UTF-8: {e}")),
    };

    let payload: CertificatePayload = match serde_json::from_str(&cert_json) {
        Ok(p) => p,
        Err(e) => return AuthResult::Rejected(format!("Certificate JSON parse error: {e}")),
    };

    // Verify company_id matches
    if payload.company_id != expected_company_id {
        return AuthResult::Rejected(format!(
            "Certificate company_id '{}' doesn't match expected '{}'",
            payload.company_id, expected_company_id
        ));
    }

    // Check expiry if present
    if let Some(ref expires_at) = payload.expires_at {
        // Simple string comparison works for ISO 8601 dates
        let now = crate::discovery::chrono_now_utc();
        if *expires_at < now {
            return AuthResult::Rejected(format!(
                "Certificate expired at {} (now: {})",
                expires_at, now
            ));
        }
    }

    AuthResult::Verified {
        device_id: payload.device_id,
        company_id: payload.company_id,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn no_company_key_allows_all() {
        let auth = SyncAuth::default();
        match verify_sync_auth(&auth, "company-1", None) {
            AuthResult::AllowedNoKey => {} // expected
            other => panic!("Expected AllowedNoKey, got {:?}", other),
        }
    }

    #[test]
    fn missing_cert_when_key_configured() {
        let auth = SyncAuth::default();
        match verify_sync_auth(&auth, "company-1", Some("AAAA")) {
            AuthResult::Required => {} // expected
            other => panic!("Expected Required, got {:?}", other),
        }
    }
}

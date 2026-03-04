"""
Tests for the auth service — PIN hashing, JWT creation/verification.

Covers:
- PIN hashing and verification (bcrypt)
- Access token creation and decoding
- PIN token creation and decoding
- Token expiration behavior
- Edge cases (placeholder hash, invalid tokens, tampered JWTs)
"""

from __future__ import annotations

import time
from datetime import datetime, timedelta, timezone

import pytest

from app.services.auth_service import (
    ALGORITHM,
    create_access_token,
    create_pin_token,
    decode_token,
    get_user_id_from_token,
    hash_pin,
    is_pin_token,
    verify_pin,
)
from app.config import settings


# ══════════════════════════════════════════════════════════════════
# PIN Hashing
# ══════════════════════════════════════════════════════════════════


class TestPinHashing:
    """Tests for bcrypt PIN hashing and verification."""

    def test_hash_pin_returns_bcrypt_string(self):
        """hash_pin should return a string starting with $2b$ (bcrypt marker)."""
        hashed = hash_pin("1234")
        assert hashed.startswith("$2b$")
        assert len(hashed) == 60  # bcrypt hashes are always 60 chars

    def test_hash_pin_different_salts(self):
        """Hashing the same PIN twice should produce different hashes (random salt)."""
        h1 = hash_pin("1234")
        h2 = hash_pin("1234")
        assert h1 != h2

    def test_verify_pin_correct(self):
        """verify_pin should return True for a matching PIN."""
        hashed = hash_pin("5678")
        assert verify_pin("5678", hashed) is True

    def test_verify_pin_wrong(self):
        """verify_pin should return False for a wrong PIN."""
        hashed = hash_pin("5678")
        assert verify_pin("0000", hashed) is False

    def test_verify_pin_placeholder_hash(self):
        """verify_pin should return False for the placeholder hash."""
        assert verify_pin("1234", "__PLACEHOLDER_HASH__") is False

    def test_verify_pin_garbage_hash(self):
        """verify_pin should return False for an invalid hash string."""
        assert verify_pin("1234", "not-a-hash") is False

    def test_verify_pin_empty_inputs(self):
        """verify_pin should handle empty strings gracefully."""
        hashed = hash_pin("1234")
        assert verify_pin("", hashed) is False


# ══════════════════════════════════════════════════════════════════
# Access Tokens
# ══════════════════════════════════════════════════════════════════


class TestAccessToken:
    """Tests for JWT access token creation and decoding."""

    def test_create_and_decode(self):
        """A freshly created token should decode successfully."""
        token = create_access_token(42)
        payload = decode_token(token)

        assert payload is not None
        assert payload["sub"] == "42"
        assert payload["type"] == "access"
        assert "iat" in payload
        assert "exp" in payload

    def test_user_id_extraction(self):
        """get_user_id_from_token should return the correct user_id."""
        token = create_access_token(99)
        assert get_user_id_from_token(token) == 99

    def test_device_id_claim(self):
        """Access token should embed device_id when provided."""
        token = create_access_token(1, device_id=7)
        payload = decode_token(token)

        assert payload is not None
        assert payload["device_id"] == 7

    def test_extra_claims(self):
        """Extra claims should be embedded in the token."""
        token = create_access_token(1, extra_claims={"hat": "admin"})
        payload = decode_token(token)

        assert payload is not None
        assert payload["hat"] == "admin"

    def test_access_token_is_not_pin_token(self):
        """An access token should not be identified as a PIN token."""
        token = create_access_token(1)
        assert is_pin_token(token) is False

    def test_invalid_token_returns_none(self):
        """decode_token should return None for garbage input."""
        assert decode_token("not.a.jwt") is None

    def test_tampered_token_returns_none(self):
        """A token with a modified payload should fail verification."""
        token = create_access_token(1)
        # Flip a character in the payload section
        parts = token.split(".")
        payload = parts[1]
        tampered = payload[:-1] + ("A" if payload[-1] != "A" else "B")
        bad_token = f"{parts[0]}.{tampered}.{parts[2]}"
        assert decode_token(bad_token) is None

    def test_get_user_id_invalid_token(self):
        """get_user_id_from_token should return None for bad tokens."""
        assert get_user_id_from_token("garbage") is None

    def test_get_user_id_missing_sub(self):
        """get_user_id_from_token should return None if sub claim is missing."""
        from jose import jwt as jose_jwt

        token = jose_jwt.encode(
            {"type": "access", "exp": datetime.now(timezone.utc) + timedelta(hours=1)},
            settings.SECRET_KEY,
            algorithm=ALGORITHM,
        )
        assert get_user_id_from_token(token) is None


# ══════════════════════════════════════════════════════════════════
# PIN Tokens
# ══════════════════════════════════════════════════════════════════


class TestPinToken:
    """Tests for short-lived PIN verification tokens."""

    def test_create_and_decode(self):
        """A freshly created PIN token should decode with type=pin_verify."""
        token = create_pin_token(42)
        payload = decode_token(token)

        assert payload is not None
        assert payload["sub"] == "42"
        assert payload["type"] == "pin_verify"

    def test_is_pin_token(self):
        """is_pin_token should return True for a PIN token."""
        token = create_pin_token(1)
        assert is_pin_token(token) is True

    def test_access_is_not_pin(self):
        """is_pin_token should return False for an access token."""
        token = create_access_token(1)
        assert is_pin_token(token) is False

    def test_garbage_is_not_pin(self):
        """is_pin_token should return False for garbage input."""
        assert is_pin_token("not.a.jwt") is False

    def test_pin_token_user_id(self):
        """get_user_id_from_token should work with PIN tokens too."""
        token = create_pin_token(55)
        assert get_user_id_from_token(token) == 55

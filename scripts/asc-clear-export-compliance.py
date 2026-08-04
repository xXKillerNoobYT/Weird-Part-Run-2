#!/usr/bin/env python3
"""Declare exempt encryption on any TestFlight build stuck on export compliance.

`ITSAppUsesNonExemptEncryption` in the app Info.plist is the real fix — it stops
builds from ever reaching this state. This script is for the gap: builds already
uploaded from a commit that predates that key, which otherwise sit as
MISSING_EXPORT_COMPLIANCE and cannot be installed by any tester until someone
answers the questions by hand in App Store Connect.

The declaration it applies is the owner determination of 2026-08-04: every
algorithm in the app is published-standard (SQLCipher/AES, scrypt RFC 7914,
PBKDF2, SHA-256, OS TLS) and is used only to protect the user's own data on
their own device and to sign them in. See the comment in
`Weird Parts IOS/Weird-Parts-IOS-Info.plist` for the full rationale.

Do not run this against a build whose cryptography has changed. Redo the
determination with the owner first.

Usage:
    scripts/asc-clear-export-compliance.py            # report only
    scripts/asc-clear-export-compliance.py --apply    # clear blocked builds

Requires PyJWT and the ASC API key at the path below.
"""
import argparse
import json
import sys
import time
import urllib.error
import urllib.request

try:
    import jwt
except ImportError:
    sys.exit("PyJWT is required: pip install pyjwt")

KEY_ID = "NXX8AAR37T"
ISSUER = "15fb05d6-12b4-494e-9a26-6edc0a23f9b6"
KEY_PATH = f"/Users/IA/.appstoreconnect/private_keys/AuthKey_{KEY_ID}.p8"
APP_ID = "6792639040"
BASE = "https://api.appstoreconnect.apple.com"
BLOCKED = "MISSING_EXPORT_COMPLIANCE"


def token() -> str:
    with open(KEY_PATH) as fh:
        key = fh.read()
    now = int(time.time())
    return jwt.encode(
        {"iss": ISSUER, "iat": now, "exp": now + 900, "aud": "appstoreconnect-v1"},
        key, algorithm="ES256", headers={"kid": KEY_ID, "typ": "JWT"},
    )


def call(method: str, path: str, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(
        BASE + path, data=data, method=method,
        headers={"Authorization": f"Bearer {token()}",
                 "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=45) as resp:
            raw = resp.read()
            return json.loads(raw) if raw else {"_ok": resp.status}
    except urllib.error.HTTPError as exc:
        return {"_error": f"{exc.code} {exc.read()[:300].decode(errors='replace')}"}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true",
                    help="actually declare exempt; default is report only")
    ap.add_argument("--limit", type=int, default=10)
    args = ap.parse_args()

    builds = call("GET", f"/v1/builds?filter[app]={APP_ID}&sort=-version"
                         f"&limit={args.limit}&include=buildBetaDetail")
    if "_error" in builds:
        print(f"builds query failed: {builds['_error']}", file=sys.stderr)
        return 1

    included = {i["id"]: i for i in builds.get("included", [])}
    blocked = 0
    failed = 0

    for b in builds.get("data", []):
        version = b["attributes"].get("version")
        ref = b.get("relationships", {}).get("buildBetaDetail", {}).get("data")
        state = "?"
        if ref:
            state = included.get(ref["id"], {}).get(
                "attributes", {}).get("internalBuildState", "?")

        if state != BLOCKED:
            print(f"build {version:>4}  {state}")
            continue

        blocked += 1
        if not args.apply:
            print(f"build {version:>4}  {state}  <- would declare exempt (--apply)")
            continue

        res = call("PATCH", f"/v1/builds/{b['id']}",
                   {"data": {"type": "builds", "id": b["id"],
                             "attributes": {"usesNonExemptEncryption": False}}})
        if "_error" in res:
            failed += 1
            print(f"build {version:>4}  FAILED: {res['_error']}", file=sys.stderr)
        else:
            print(f"build {version:>4}  declared exempt")

    if not blocked:
        print("\nNo build is blocked on export compliance.")
    elif not args.apply:
        print(f"\n{blocked} build(s) blocked. Re-run with --apply to clear them.")

    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())

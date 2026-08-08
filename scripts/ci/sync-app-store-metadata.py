#!/usr/bin/env python3
"""Push docs/app-store/description.md into App Store Connect — idempotently.

Owner directive 2026-08-04: *"keep that up to date by the way"*. The listing
copy lives in the repo (reviewable, diffable, versioned); ASC is a rendering of
it. Running this after any edit to description.md re-syncs every field the API
owns, for EVERY platform version (iOS and macOS both have version records).

Fields the API cannot set are reported, never faked:
  - privacyPolicyUrl / marketingUrl — no URL exists yet (front-end task)
  - screenshots — upload via the ASC UI
  - age rating, categories — ASC UI

Usage:
    ~/.claude/scripts/ascenv/bin/python scripts/ci/sync-app-store-metadata.py [--check]

--check exits 1 when ASC differs from the repo (for CI drift detection) and
writes nothing.
"""
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

APP_ID = "6792639040"
API = "https://api.appstoreconnect.apple.com/v1"
DOC = Path(__file__).resolve().parents[2] / "docs" / "app-store" / "description.md"
SUPPORT_URL = "https://github.com/xXKillerNoobYT/Weird-Part-Run-2/issues"


def _token() -> str:
    """Reuse the local ASC helper so key material stays in one place."""
    sys.path.insert(0, os.path.expanduser("~/.claude/scripts"))
    from asc_feedback import token  # type: ignore
    return token()


def _get(path: str):
    req = urllib.request.Request(f"{API}{path}", headers={"Authorization": f"Bearer {_token()}"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.load(resp)


def _patch(kind: str, ident: str, attrs: dict) -> str:
    body = json.dumps({"data": {"type": kind, "id": ident, "attributes": attrs}}).encode()
    req = urllib.request.Request(
        f"{API}/{kind}/{ident}", data=body, method="PATCH",
        headers={"Authorization": f"Bearer {_token()}", "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return f"OK {resp.status}"
    except urllib.error.HTTPError as exc:
        detail = json.loads(exc.read()).get("errors", [{}])[0].get("detail", "")
        return f"ERROR {exc.code}: {detail[:200]}"


def block(source: str, header: str):
    """Read one fenced block from the listing doc by its heading prefix."""
    pattern = r"## " + re.escape(header) + r"[^\n]*\n```\n(.*?)\n```"
    match = re.search(pattern, source, re.S)
    return match.group(1).strip() if match else None


def desired_fields() -> dict:
    src = DOC.read_text()
    fields = {
        "description": block(src, "Description"),
        "keywords": block(src, "Keywords"),
        "promotionalText": block(src, "Promotional Text"),
        "supportUrl": SUPPORT_URL,
        "_subtitle": block(src, "Subtitle"),
    }
    missing = [k for k, v in fields.items() if not v]
    if missing:
        raise SystemExit(f"description.md is missing required blocks: {missing}")
    # Apple's hard limits — fail loudly here rather than getting a 409 later.
    for key, limit in (("description", 4000), ("keywords", 100),
                       ("promotionalText", 170), ("_subtitle", 30)):
        if len(fields[key]) > limit:
            raise SystemExit(f"{key} is {len(fields[key])} chars; Apple's limit is {limit}")
    return fields


def main() -> int:
    check_only = "--check" in sys.argv
    want = desired_fields()
    subtitle = want.pop("_subtitle")
    drift, wrote = [], []

    for version in _get(f"/apps/{APP_ID}/appStoreVersions?limit=10")["data"]:
        platform = version["attributes"].get("platform")
        state = version["attributes"].get("appStoreState")
        # Only editable states accept writes; a live version must not be touched.
        if state not in ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED",
                         "REJECTED", "METADATA_REJECTED", "INVALID_BINARY"):
            print(f"skip {platform} version ({state}) — not editable")
            continue
        for loc in _get(f"/appStoreVersions/{version['id']}/appStoreVersionLocalizations")["data"]:
            current = loc["attributes"]
            diff = {k: v for k, v in want.items() if (current.get(k) or "") != v}
            if not diff:
                print(f"{platform} {current.get('locale')}: up to date")
                continue
            drift.append(f"{platform}/{current.get('locale')}: {sorted(diff)}")
            if not check_only:
                print(f"{platform} {current.get('locale')}: {_patch('appStoreVersionLocalizations', loc['id'], diff)}")
                wrote.append(loc["id"])
                time.sleep(0.5)

    for info in _get(f"/apps/{APP_ID}/appInfos")["data"]:
        for loc in _get(f"/appInfos/{info['id']}/appInfoLocalizations")["data"]:
            if (loc["attributes"].get("subtitle") or "") == subtitle:
                continue
            drift.append(f"appInfo/{loc['attributes'].get('locale')}: subtitle")
            if not check_only:
                print(f"appInfo subtitle: {_patch('appInfoLocalizations', loc['id'], {'subtitle': subtitle})}")

    print("\n-- fields the API cannot set (owner/UI only) --")
    print("  privacyPolicyUrl : REQUIRED before submission; no URL hosted yet")
    print("  marketingUrl     : optional; no URL hosted yet")
    print("  screenshots      : upload in the ASC UI (docs/app-store/screenshots/)")
    print("  categories, age rating : ASC UI")

    if check_only and drift:
        print("\nDRIFT: ASC differs from description.md:")
        for d in drift:
            print(f"  - {d}")
        return 1
    if not check_only:
        print(f"\nsynced {len(wrote)} localization(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

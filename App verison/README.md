# App verison/ — release channel triggers

One machine-parseable file per release channel. **The folder name's spelling is
load-bearing** — Xcode Cloud Branch-Changes conditions reference it URL-encoded
(`App%20verison`); do not rename. NOTE: until 2026-08-01 this folder existed
only as an untracked local file on the shared Mac, so cloud conditions watching
it could never fire — this commit makes the trigger real.

**This folder is the EXTERNAL-release trigger and nothing else** (owner
clarification 2026-08-01). Routine PR merges must NEVER touch it — internal
builds already fire from any edit landing on `main` and do not require (or
want) changes here. Change a file in this folder only when the intent is a
release beyond the internal group:

- `INTERNAL-BETA.md` — Home Base group reference info only. Internal builds
  are triggered by main-branch edits, NOT by this file; do not bump it per
  build.
- `PUBLIC-BETA.md` — Camp 1 external group (public link). Full Xcode Cloud
  workflow + Apple beta review. **Cadence (owner 2026-08-01, supersedes the
  5–9 day spec): at MOST one push every 5 days, and at LEAST one every 14
  days** — a stable-ish external release lands every 5–14 days. Owner-gated;
  agents never bump this autonomously.
- `PUBLIC-RELEASE.md` — App Store. Owner-gated.

Rules (owner spec, 2026-07-31): when a bump does happen, it goes in the same
commit/PR as everything its build needs (notes written, fixes merged). Strict
`key: value` format so any agent or bot can parse and bump. Replaces the
original single `Version File.md`.

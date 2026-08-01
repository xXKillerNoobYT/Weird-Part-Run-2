# App verison/ — release channel triggers

One machine-parseable file per release channel. **The folder name's spelling is
load-bearing** — Xcode Cloud Branch-Changes conditions reference it URL-encoded
(`App%20verison`); do not rename. NOTE: until 2026-08-01 this folder existed
only as an untracked local file on the shared Mac, so cloud conditions watching
it could never fire — this commit makes the trigger real.

- `INTERNAL-BETA.md` — Home Base group. Bumping it produces an internal build
  automatically (no Apple review).
- `PUBLIC-BETA.md` — Camp 1 external group (public link). Full Xcode Cloud
  workflow + Apple beta review. HARD CAP: one push per 5–9 days, owner-gated.
- `PUBLIC-RELEASE.md` — App Store. Owner-gated.

Rules (owner spec, 2026-07-31): bump a channel file ONLY in the same commit/PR
as everything its build needs (notes written, fixes merged). Strict `key: value`
format so any agent or bot can parse and bump. Replaces the original single
`Version File.md`.

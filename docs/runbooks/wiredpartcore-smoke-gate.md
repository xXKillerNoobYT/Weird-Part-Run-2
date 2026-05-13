# WiredPartCore CI Smoke Gate

Purpose: fast signal that `WiredPartCore` still compiles, tests execute, and source-only line coverage stays above the audited floor.

## Command

Run from repository root:

```bash
scripts/ci-core-smoke.sh
```

## What it validates

1. `swift build` succeeds in `core/`.
2. `swift test --enable-code-coverage` succeeds in `core/`.
3. `scripts/wiredpartcore-source-coverage.py` parses the SwiftPM coverage JSON and reports:
   - total source lines under `core/Sources/WiredPartCore`
   - covered source lines
   - source-only line coverage percent
   - lowest-covered source files
4. The default coverage threshold is 88%. Override with `WIREDPARTCORE_COVERAGE_THRESHOLD=<percent>` when intentionally ratcheting the gate.

## CI wiring

GitHub Actions workflow: `.github/workflows/wiredpartcore-smoke.yml`

It runs on:
- Pull requests touching `core/**` or smoke-gate files.
- Pushes to `main` touching `core/**` or smoke-gate files.
- Manual dispatch.

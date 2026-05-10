# Fast-Review vs Critical-Review Lane (Pilot)

## Convention

- Default lane: fast-review.
- Escalation lane: critical-review.

A PR is considered **critical-review** if either of these is true:

- PR includes label `critical-review`.
- PR template checkbox `Critical-review lane` is checked.

When critical-review is selected, PR metadata must include:

- `ClaudeReviewer sign-off captured` checked.
- `GPTReviewer sign-off captured` checked.
- `Critical review requested at (UTC)` timestamp.
- `Critical review approved at (UTC)` timestamp.

The CI workflow `Critical Review Gate` enforces this from the pull-request metadata snapshot.

## Failure mode

If any required metadata is missing, `scripts/critical-review-gate.sh` exits non-zero and CI fails with a list of missing fields.

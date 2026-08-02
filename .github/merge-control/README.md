# Copilot merge waivers

`copilot-review-waivers.json` is the only exception path for the serialized PR merge maintainer.

A waiver is valid only when it is committed to trusted `main` and has all of these exact fields:

- `pr`: the pull request number;
- `head_sha`: the full current head SHA of that pull request;
- `approved_by`: `xXKillerNoobYT`;
- `reason`: a non-empty incident or policy reason; and
- `approval_url`: the owner’s GitHub issue or PR comment URL for that PR.

The merge maintainer compares both `pr` and `head_sha`; any new commit invalidates the waiver. Do not add broad, reusable, environment-variable, or expiry-only exceptions. Remove a used waiver in a follow-up reviewed change to keep the ledger small and auditable.

# Copilot merge waivers

`copilot-review-waivers.json` is the only exception path for the serialized PR merge maintainer.

A waiver is valid only when it is committed to trusted `main` and has all of these exact fields:

- `pr`: the pull request number;
- `head_sha`: the full current head SHA of that pull request;
- `approved_by`: `xXKillerNoobYT`;
- `reason`: a non-empty incident or policy reason; and
- `approval_url`: the owner’s GitHub issue or PR comment URL for that PR.

The merge maintainer fetches this ledger through the GitHub API at its merge base (`main` by default), never from the workflow checkout or an environment-configured path. It also reads the referenced comment API record and requires both the owner login and matching PR/issue number. The maintainer fails closed if either GitHub read is unavailable. It compares both `pr` and `head_sha`; any new commit invalidates the waiver. Do not add broad, reusable, environment-variable, or expiry-only exceptions. Remove a used waiver in a follow-up reviewed change to keep the ledger small and auditable.

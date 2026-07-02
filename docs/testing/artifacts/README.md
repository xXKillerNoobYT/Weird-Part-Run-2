# Test Evidence Policy

QA/verification evidence (screenshots, exports, attachment dumps) is **not**
committed to this repository. Attach evidence directly to the GitHub issue or
pull request it verifies — attachments are hosted by GitHub and keep clones
small.

The per-ticket evidence folders that used to live here (~18.7 MB across
wei-996 … wei-3041) were removed from the index on 2026-07-02 (issue #1333);
they remain available in git history prior to that date if ever needed.

`scripts/guard-tracked-artifacts.py` (run by the Artifact Guard workflow on
every PR) enforces this policy: tracked images outside `docs/problems/` and
asset catalogs fail CI, as does any tracked file over 1 MB.

# GitHub Organization Migration Plan

Date: 2026-05-23
Paperclip issue: WEI-2163

## Why this exists

The current Paperclip company has multiple active project repositories owned by personal GitHub accounts instead of a shared GitHub organization. That makes access control, agent permissions, billing ownership, secrets, and continuity harder to manage as the coding company grows.

This document records the safe migration plan. It intentionally does not transfer any repository by itself; repo transfer changes ownership, permissions, webhooks, secrets, app installs, and clone URLs, so it should be approved and scheduled before execution.

## Current inventory

| Paperclip project | GitHub repo | Current owner type | Visibility | Current permission seen by CTO | Default branch | Recommended target |
| --- | --- | --- | --- | --- | --- | --- |
| Mythos Writer | `SkyyPlayz/Mythos-Writer` | User (`SkyyPlayz`) | Private | Write | `main` | `Weirdtoo/Mythos-Writer` |
| Questing | `SkyyPlayz/Questing` | User (`SkyyPlayz`) | Private | Write | `main` | `Weirdtoo/Questing` |
| Weird Part's run 2 | `xXKillerNoobYT/Weird-Part-Run-2` | User (`xXKillerNoobYT`) | Public | Admin | `main` | `Weirdtoo/Weird-Part-Run-2` |
| Coding setup and Policy Senter | `xXKillerNoobYT/paperclip` | User (`xXKillerNoobYT`) | Public | Admin | `master` | `Weirdtoo/paperclip` |

Authenticated GitHub account: `xXKillerNoobYT`.
Available organization detected: `Weirdtoo`.

## Key risk notes

1. `Weird-Part-Run-2` currently has 68 remote branches. That is above the 20-branch soft cap from the branch hygiene policy, though below the 100-branch hard cap. Do not combine org migration with branch cleanup; migrate ownership first or drain branches first as a separate tracked task.
2. `Mythos-Writer` and `Questing` are private and currently only show Write permission for the authenticated account. Transfers may require the current owner account (`SkyyPlayz`) or an organization owner to initiate/approve.
3. GitHub automatically redirects old repo URLs after transfer, but Paperclip project workspace records, local remotes, secrets, deploy keys, GitHub Apps, webhooks, branch protection, and CI assumptions should still be audited and updated explicitly.
4. The `paperclip` repo uses `master`; the others use `main`. Preserve default branches during transfer unless a separate migration explicitly changes them.
5. Public/private visibility should be preserved unless the user explicitly approves a visibility change.

## Recommended migration sequence

### Phase 0: Confirm destination policy

- Confirm whether `Weirdtoo` is the intended long-term organization.
- Confirm whether each repo should keep its current visibility.
- Confirm desired org teams, for example:
  - Owners/Admins: user + trusted maintainers.
  - Agents: Paperclip/Hermes service accounts with least privilege.
  - Viewers: read-only collaborators if needed.

### Phase 1: Preflight each repo

For each repo:

```bash
gh repo view OWNER/REPO --json nameWithOwner,isPrivate,visibility,owner,defaultBranchRef,viewerPermission,url
gh api repos/OWNER/REPO/hooks --jq 'length'
gh secret list -R OWNER/REPO
gh variable list -R OWNER/REPO
gh api repos/OWNER/REPO/environments --jq '.environments | length'
gh api repos/OWNER/REPO/branches/DEFAULT_BRANCH/protection || true
gh workflow list -R OWNER/REPO --all
gh pr list -R OWNER/REPO --state open --limit 100
```

Record anything that must be recreated or reauthorized after transfer.

### Phase 2: Transfer repositories one at a time

Preferred order:

1. `xXKillerNoobYT/paperclip` because it is public and admin-accessible.
2. `xXKillerNoobYT/Weird-Part-Run-2` because it is the active beta trunk and admin-accessible.
3. `SkyyPlayz/Questing` after owner/admin permission is confirmed.
4. `SkyyPlayz/Mythos-Writer` after owner/admin permission is confirmed.

Use GitHub UI or API. API shape for an admin-authorized transfer:

```bash
gh api -X POST repos/OWNER/REPO/transfer -f new_owner=Weirdtoo
```

Do not run this command until the user approves the specific repo transfer window.

### Phase 3: Update local and Paperclip references

After each successful transfer:

```bash
git remote set-url origin https://github.com/Weirdtoo/REPO.git
git remote -v
git fetch origin --prune
gh repo view Weirdtoo/REPO --json nameWithOwner,visibility,defaultBranchRef
```

Then update the matching Paperclip project workspace `repoUrl` / codebase metadata if Paperclip does not follow GitHub redirects automatically.

### Phase 4: Post-transfer verification

For each repo:

- Clone/fetch works with the new URL.
- Existing open PRs and branches are still visible.
- GitHub Actions workflows still run or are intentionally disabled.
- Secrets, variables, environments, webhooks, and GitHub Apps are present or recreated.
- Branch protection/default branch settings are preserved.
- Paperclip can start a new workspace and push a test branch if needed.

## Paperclip follow-up work items to create

Create one issue per repository so transfer can be approved, executed, and verified independently:

1. `[GitHub][Org Migration] Transfer paperclip repo to Weirdtoo`
2. `[GitHub][Org Migration] Transfer Weird-Part-Run-2 repo to Weirdtoo`
3. `[GitHub][Org Migration] Transfer Questing repo to Weirdtoo`
4. `[GitHub][Org Migration] Transfer Mythos-Writer repo to Weirdtoo`

Each issue should include the preflight checklist, transfer command/UI step, and post-transfer verification checklist above.

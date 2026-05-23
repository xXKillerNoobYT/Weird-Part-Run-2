# GitHub Account Context

This project currently lives under the user's personal GitHub account, not a GitHub organization.

Current verified repo context:

- Repository: `xXKillerNoobYT/Weird-Part-Run-2`
- Remote: `https://github.com/xXKillerNoobYT/Weird-Part-Run-2.git`
- Owner account: `xXKillerNoobYT`
- Visibility at last verification: public
- Viewer permission at last verification: admin

Verification command:

```bash
gh repo view xXKillerNoobYT/Weird-Part-Run-2 \
  --json nameWithOwner,owner,visibility,isPrivate,url,viewerPermission
```

## Operating rule for agents

Do not assume GitHub organization features, organization teams, organization policy pages, or organization-level settings exist for this repo.

When a workflow asks for GitHub owner/org settings:

1. First inspect the actual repo owner from `git remote get-url origin` or `gh repo view`.
2. If the owner is a personal account, use repo-level or user-account-level GitHub settings only.
3. If a requested control only exists for organizations, document that it is not applicable until the repo is transferred to a GitHub organization.
4. Do not block implementation work waiting for org-only settings unless the user explicitly decides to create or move to a GitHub organization.

## Practical impact

- Branch protection, required checks, auto-merge, issues, PRs, and repo secrets are repo-level and still apply.
- Organization teams, organization rulesets, organization member permissions, and organization Copilot policy screens may not apply.
- Any Paperclip task created from an "org settings" assumption should be re-scoped to the equivalent repo/user-account setting or marked not applicable with evidence.

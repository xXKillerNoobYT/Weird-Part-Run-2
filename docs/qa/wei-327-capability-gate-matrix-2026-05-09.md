# WEI-327 Capability Gate Matrix (2026-05-09)

## Verdict

Accept for closure evidence.

## Environment

- Workspace: `/Users/IA/GitHub/Weird-Part-Run-2/.paperclip/worktrees/WEI-125-adding-to-the-plan-mcp`
- Paperclip server package inspected from local runtime: `/Users/IA/.npm/_npx/43414d9b790239bb/node_modules/@paperclipai/server`
- Host gate implementation: `dist/services/plugin-capability-validator.js`
- Runtime enforcement entry point: `dist/services/plugin-runtime-sandbox.js`

## Rerunnable Verification

```bash
node --input-type=module <<'EOF'
import { pluginCapabilityValidator } from '/Users/IA/.npm/_npx/43414d9b790239bb/node_modules/@paperclipai/server/dist/services/plugin-capability-validator.js';
const validator = pluginCapabilityValidator();
const operations = [
  ['read.issue', 'issues.get', ['issues.read']],
  ['read.comments', 'issue.comments.list', ['issue.comments.read']],
  ['write.issue', 'issues.create', ['issues.create']],
  ['write.comment', 'issue.comments.create', ['issue.comments.create']],
  ['notifications.subscribe', 'events.subscribe', ['events.subscribe']],
  ['todo.create', 'issues.create', ['issues.create']],
  ['qa.ask_user_questions', 'issue.interactions.create', ['issue.interactions.create']],
];
for (const [label, operation, capabilities] of operations) {
  const allowManifest = { id: `allow-${label}`, capabilities };
  const denyManifest = { id: `deny-${label}`, capabilities: [] };
  const allow = validator.checkOperation(allowManifest, operation);
  const deny = validator.checkOperation(denyManifest, operation);
  console.log(`${label}|${operation}|${capabilities.join(',')}|allow=${allow.allowed}|deny=${deny.allowed}|missing=${deny.missing.join(',')}`);
}
EOF
```

## Observed Output

```text
read.issue|issues.get|issues.read|allow=true|deny=false|missing=issues.read
read.comments|issue.comments.list|issue.comments.read|allow=true|deny=false|missing=issue.comments.read
write.issue|issues.create|issues.create|allow=true|deny=false|missing=issues.create
write.comment|issue.comments.create|issue.comments.create|allow=true|deny=false|missing=issue.comments.create
notifications.subscribe|events.subscribe|events.subscribe|allow=true|deny=false|missing=events.subscribe
todo.create|issues.create|issues.create|allow=true|deny=false|missing=issues.create
qa.ask_user_questions|issue.interactions.create|issue.interactions.create|allow=true|deny=false|missing=issue.interactions.create
```

## Matrix

| Path | Host operation | Required capability | Positive check | Negative check | Result |
|---|---|---|---|---|---|
| Read issue | `issues.get` | `issues.read` | Manifest with `issues.read` returned `allow=true` | Empty manifest returned `deny=false`, missing `issues.read` | PASS |
| Read comments | `issue.comments.list` | `issue.comments.read` | Manifest with `issue.comments.read` returned `allow=true` | Empty manifest returned `deny=false`, missing `issue.comments.read` | PASS |
| Write issue | `issues.create` | `issues.create` | Manifest with `issues.create` returned `allow=true` | Empty manifest returned `deny=false`, missing `issues.create` | PASS |
| Write comment | `issue.comments.create` | `issue.comments.create` | Manifest with `issue.comments.create` returned `allow=true` | Empty manifest returned `deny=false`, missing `issue.comments.create` | PASS |
| Notifications | `events.subscribe` | `events.subscribe` | Manifest with `events.subscribe` returned `allow=true` | Empty manifest returned `deny=false`, missing `events.subscribe` | PASS |
| Todo/task creation | `issues.create` | `issues.create` | Manifest with `issues.create` returned `allow=true` | Empty manifest returned `deny=false`, missing `issues.create` | PASS |
| Q&A / ask-user interaction | `issue.interactions.create` | `issue.interactions.create` | Manifest with `issue.interactions.create` returned `allow=true` | Empty manifest returned `deny=false`, missing `issue.interactions.create` | PASS |

## Code Evidence

- Capability mapping includes the tested read/write/event/interaction operations: `/Users/IA/.npm/_npx/43414d9b790239bb/node_modules/@paperclipai/server/dist/services/plugin-capability-validator.js:16`
- Unknown or missing capability checks are rejected by default: `/Users/IA/.npm/_npx/43414d9b790239bb/node_modules/@paperclipai/server/dist/services/plugin-capability-validator.js:188`
- Runtime calls pass through `validator.assertOperation(...)` before executing host work: `/Users/IA/.npm/_npx/43414d9b790239bb/node_modules/@paperclipai/server/dist/services/plugin-runtime-sandbox.js:24`

## Residual Risk

- This verifies the host capability gate and operation mapping, not an end-to-end UI flow for every plugin. The acceptance scope asked for PLAN MCP capability-gate evidence, and the host gate is the enforcement point for those MCP-style operations.

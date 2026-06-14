# Subscription-Usage Heartbeat Manager Plugin Spec

> Status: implementation-ready specification
> Paperclip: WEI-3605, child of WEI-3602
> Scope: Government Watchdog first; reusable for multiple Paperclip companies/computers later
> Owner intent source: WEI-3602 request plus attached Claude usage dashboard screenshot
> Owner clarification: Paperclip already has usage tracking and limit data; this plugin should consume that existing tracking to keep usage within owner-defined pacing limits, not rebuild provider usage tracking from scratch.

## 1. Purpose

Build a Paperclip plugin that reads provider usage windows and schedules bounded, auditable wake opportunities for CEOs and other explicitly qualifying key agents so subscription credits are used steadily instead of being exhausted early or left unused at reset.

The plugin must support two pacing horizons:

1. A short provider window, represented by the screenshot's `Current Session` window: 3% used, resets in 4 hr 49 min at 7:09 PM. Treat this as a 6-hour rolling/session-style quota window unless provider telemetry supplies a different duration.
2. A weekly provider window, represented by the screenshot's `Weekly Limit` window: 18% used, resets Monday at 9:59 AM.

The owner's target behavior is:

- Do not burn the whole subscription at the beginning of the week.
- Before the final day of the weekly period, stay at least 5 percentage points under the optimal even-burn line.
- On the final day before reset, safely increase wake opportunities so the system uses remaining weekly capacity by reset.
- Coordinate multiple companies and computers that share one subscription by taking turns through a shared synced state file.
- Make turn-taking fair across CEOs/key agents and providers; fairness is more important than absolute maximum throughput.

## 2. Non-goals and hard boundaries

- Do not create a hidden polling loop. The plugin may run as a Paperclip plugin/scheduler and may trigger heartbeat-like wakes, but all wake decisions must be recorded with reason, quota state, and selected agent.
- Preserve Isaac's current CEO-only routine heartbeat policy by default. Non-CEO agents may only be scheduled when their agent or company config explicitly marks them as `usageHeartbeatEligible` and records why they qualify.
- Government Watchdog is the first rollout. Do not automatically enable this for WPR2/WEI, Mythos Writer, Questing, or other companies without explicit configuration.
- Do not automate campaign messaging, legal conclusions, public accusations, final publication decisions, official-contact automation, or publication approvals.
- Do not bypass provider limits, simulate usage, or intentionally create wasteful requests. The goal is useful work paced to available credits, not artificial burn.
- Do not store provider secrets in the synced state file.
- Do not wake agents if Paperclip already has active live runs above the configured concurrency cap for that company/provider.

## 3. Inputs

### 3.1 Paperclip usage telemetry

Paperclip's existing usage tracking is the required telemetry source for the first implementation. The plugin must read the usage percentages, reset timestamps, and limit/window metadata that Paperclip already records, normalize those records into the snapshot shape below, and use them to decide whether to hold, dry-run, or wake agents. Backend implementation should only add adapter-specific usage collectors if the current Paperclip usage-tracking surface is missing a field required for pacing, and that gap must be documented before adding new tracking storage.

Each provider adapter should expose normalized usage snapshots:

```json
{
  "provider": "claude",
  "accountKey": "isaac-claude-main",
  "observedAt": "2026-06-14T20:20:42Z",
  "windows": [
    {
      "kind": "session",
      "durationSeconds": 21600,
      "usedFraction": 0.03,
      "resetAt": "2026-06-15T01:09:00Z",
      "sourceLabel": "Current Session",
      "sourceResetLabel": "Resets in 4 hr 49 min (7:09 PM)",
      "confidence": "observed"
    },
    {
      "kind": "weekly",
      "durationSeconds": 604800,
      "usedFraction": 0.18,
      "resetAt": "2026-06-15T15:59:00Z",
      "sourceLabel": "Weekly Limit",
      "sourceResetLabel": "Resets Mon, 9:59 AM",
      "confidence": "observed"
    }
  ]
}
```

The normalizer must treat Paperclip's built-in usage tracking as authoritative. If Paperclip exposes only percentage and reset time, derive elapsed time from the configured nominal duration. Local provider dashboard exports or provider APIs are allowed only as operator-approved diagnostic fallbacks when Paperclip's usage tracking is unavailable; they are not the default product path.

### 3.2 Company and agent eligibility config

Config must be explicit per company:

```json
{
  "companyId": "bcac096e-4aff-4ce3-ad33-c4e0b693b36f",
  "companyPrefix": "GOV",
  "enabled": true,
  "providers": ["claude", "codex"],
  "defaultPriority": "normal",
  "agents": [
    {
      "agentId": "...",
      "role": "CEO",
      "usageHeartbeatEligible": true,
      "reason": "CEO owns Government Watchdog task breakdown and coordination",
      "maxWakePerSessionWindow": 1,
      "maxWakePerWeeklyWindow": 12,
      "allowedWakeKinds": ["planning", "triage", "review", "routing"]
    },
    {
      "agentId": "...",
      "role": "BackendCoder",
      "usageHeartbeatEligible": true,
      "reason": "Only when an unblocked implementation issue is assigned and provider budget is available",
      "maxWakePerSessionWindow": 1,
      "maxWakePerWeeklyWindow": 8,
      "allowedWakeKinds": ["implementation", "repair"]
    }
  ]
}
```

The plugin must ignore any agent without `usageHeartbeatEligible: true`.

### 3.3 Shared synced state file path

For multi-computer coordination, every participating Paperclip instance must be configured with a shared file path in a synced folder, for example:

```json
{
  "sharedStatePath": "/Users/IA/Library/Mobile Documents/com~apple~CloudDocs/Paperclip/shared-usage-heartbeat-state.json",
  "instanceId": "isaac-macbook-paperclip-default",
  "instancePriority": 100,
  "clockSkewToleranceSeconds": 90
}
```

`instanceId` must be stable and unique per computer/Paperclip instance.

## 4. Outputs

The plugin produces:

1. Wake decision records in the shared state file.
2. Local Paperclip wake calls for the selected agent when the local instance owns the decision.
3. Paperclip issue comments only when useful for closeout, escalation, or blocked state; normal routine wake decisions should be logged, not spammed into issues.
4. Metrics for operator review: usage snapshot, budget, chosen agent, skipped agents, and reason.

A wake trigger must include a reason payload such as:

```json
{
  "reason": "subscription_usage_manager",
  "triggerDetail": "weekly catch-up window: provider=claude account=isaac-claude-main weeklyUsed=0.72 target=0.81 selectedTurn=GOV CEO",
  "forceFreshSession": false
}
```

## 5. Pacing model

### 5.1 Normalized time and usage

For each provider/account/window:

- `now` = current trusted local time.
- `resetAt` = provider window reset time.
- `duration` = provider window duration.
- `startAt = resetAt - duration`.
- `elapsed = clamp(now - startAt, 0, duration)`.
- `remaining = max(resetAt - now, 0)`.
- `progress = elapsed / duration`.
- `used = clamp(usedFraction, 0, 1)`.
- `remainingQuota = 1 - used`.

For the screenshot's current session example, if duration is 6 hours and reset is in 4 hr 49 min, elapsed is about 1 hr 11 min and `progress ≈ 0.197`. With `used = 0.03`, usage is well below even pace.

For the screenshot's weekly example, `used = 0.18` and weekly reset is Monday 9:59 AM. The target line depends on current time inside the weekly window.

### 5.2 Optimal even-burn target

The base optimal burn line is:

```text
optimalUsed(now) = progress
```

This means that halfway through a window, the system may have used about 50% of that window's quota.

### 5.3 Pre-final-day safety target

Before the final 24 hours of the weekly period, owner requested staying 5% under optimal. Treat this as 5 percentage points, not 5% relative.

```text
preFinalWeeklyTarget = max(0, optimalUsed - 0.05)
```

The plugin may schedule wakes only when current usage is below the target minus a small deadband:

```text
weeklyDeficit = preFinalWeeklyTarget - used
eligibleForWeeklyCatchup = weeklyDeficit >= wakeCostEstimate + deadband
```

Recommended initial `deadband = 0.01` (1 percentage point) to prevent oscillation.

Example: if weekly progress is 40%, target before final day is 35%. If usage is 18%, the weekly deficit is 17 points, so extra wakes are allowed, subject to session-window limits and fairness.

### 5.4 Final-day catch-up target

During the final 24 hours before weekly reset, the target changes from conservative to catch-up. The system should ramp toward 100% by reset while preserving a reserve so it does not hard-exhaust early.

Define:

```text
finalDayProgress = clamp((24h - remainingWeekly) / 24h, 0, 1)
startOfFinalDayTarget = max(usedAtFinalDayStart, optimalUsedAtFinalDayStart - 0.05)
finalDayTarget = startOfFinalDayTarget + (1.00 - finalReserve - startOfFinalDayTarget) * finalDayProgress
```

Recommended `finalReserve = 0.02` until the last 2 hours, then `finalReserve = 0.005`. This aims to use nearly all weekly capacity without losing the ability to handle urgent final requests.

In the last 2 hours before weekly reset:

```text
lastTwoHourTarget = 0.995
```

The plugin may schedule more frequent useful work if:

- weekly usage is under target,
- session usage has enough remaining capacity,
- agents have real actionable work,
- concurrency caps are clear,
- provider-specific cooldowns are respected.

### 5.5 Session-window protection

The 6-hour/session window is a hard short-term guard. Even if weekly usage is behind, do not overrun the session window.

Session target:

```text
sessionTarget = min(0.95, max(progress - 0.05, configuredSessionFloorTarget))
```

Recommended `configuredSessionFloorTarget = 0.10` only when the session has less than 2 hours remaining and weekly usage is behind. Otherwise the plugin can stay below even session pace.

Hard stop rules:

- If `sessionUsed >= 0.90`, do not schedule non-urgent wakes for this provider/account.
- If `sessionUsed >= 0.95`, stop all plugin-initiated wakes for this provider/account until reset unless an operator manually overrides.
- If `weeklyUsed >= 0.995`, stop all plugin-initiated wakes for this provider/account until reset.

### 5.6 Wake cost estimates

Because provider dashboards usually expose percentages rather than exact remaining messages/tokens, use a conservative wake-cost estimate per provider and task class.

Initial values:

```json
{
  "claude": {
    "planning": 0.015,
    "triage": 0.010,
    "review": 0.020,
    "implementation": 0.030,
    "repair": 0.025
  },
  "codex": {
    "planning": 0.010,
    "triage": 0.008,
    "review": 0.015,
    "implementation": 0.025,
    "repair": 0.020
  }
}
```

After each wake finishes, update estimates by comparing before/after usage snapshots. Use exponential smoothing:

```text
newEstimate = 0.7 * oldEstimate + 0.3 * observedDelta
```

Clamp estimates to `[0.002, 0.08]` so one bad reading does not make the scheduler useless.

### 5.7 Decision formula

For each provider/account:

```text
allowedByWeekly = weeklyUsed + estimatedWakeCost <= weeklyTarget
allowedBySession = sessionUsed + estimatedWakeCost <= sessionTarget
allowedByHardStops = sessionUsed < 0.90 and weeklyUsed < 0.995
eligible = allowedByWeekly and allowedBySession and allowedByHardStops
```

Final day may relax `sessionTarget` but must not relax hard stops.

## 6. Fairness and turn-taking

### 6.1 Fairness goal

The owner explicitly said taking turns is more important than anything so usage is equal. The scheduler must therefore select the next eligible agent by fairness score, not by whichever company wakes first.

### 6.2 Fairness unit

The fairness unit is a tuple:

```text
(providerAccountKey, companyId, agentId, wakeKind)
```

This lets Claude usage by one company be balanced separately from Codex usage by another company while still coordinating shared subscription accounts.

### 6.3 Agent selection score

For every eligible candidate, compute:

```text
turnDebt = idealShare - actualShare
idleBonus = min(hoursSinceLastWake / 24, 1) * 0.05
priorityBonus = configuredPriorityWeight
blockedPenalty = 1.0 if candidate has no actionable work else 0
score = turnDebt + idleBonus + priorityBonus - blockedPenalty
```

Where:

```text
idealShare = totalCompletedWakesForProvider / eligibleAgentCount
actualShare = completedWakesForAgentProvider
```

Choose the highest score. Break ties by oldest `lastSelectedAt`, then stable lexical order of `companyId:agentId` so every instance reaches the same decision.

### 6.4 Qualifying work check

Before waking an agent, the local instance must verify the agent has useful work. Minimum acceptable work sources:

- assigned actionable issue in `todo`, `backlog`, or `in_progress`,
- explicit routine role allowed by config,
- manager-created work queue item for the company,
- review/triage issue whose dependencies are satisfied.

Do not wake an agent solely to spend quota.

### 6.5 Per-agent caps

Respect all caps:

- `maxWakePerSessionWindow`
- `maxWakePerWeeklyWindow`
- Paperclip runtime heartbeat concurrency / live-run caps
- Provider/account caps
- Company cap
- Manual pause/cancel state

## 7. Shared state file schema

Use a single JSON file with append-only event records plus compact summaries. Keep it small enough for cloud-sync tools.

```json
{
  "schemaVersion": 1,
  "updatedAt": "2026-06-14T21:10:00Z",
  "lock": {
    "ownerInstanceId": null,
    "token": null,
    "acquiredAt": null,
    "expiresAt": null,
    "fencingToken": 42
  },
  "providerAccounts": {
    "claude:isaac-claude-main": {
      "provider": "claude",
      "accountKey": "isaac-claude-main",
      "lastSnapshot": { "observedAt": "...", "windows": [] },
      "windows": {
        "session": {
          "resetAt": "...",
          "usedFraction": 0.03,
          "targetFraction": 0.10,
          "hardStop": false
        },
        "weekly": {
          "resetAt": "...",
          "usedFraction": 0.18,
          "targetFraction": 0.35,
          "finalDay": false,
          "hardStop": false
        }
      }
    }
  },
  "participants": {
    "bcac096e-4aff-4ce3-ad33-c4e0b693b36f:agent-uuid": {
      "instanceId": "isaac-macbook-paperclip-default",
      "companyId": "bcac096e-4aff-4ce3-ad33-c4e0b693b36f",
      "agentId": "agent-uuid",
      "providerAccounts": ["claude:isaac-claude-main"],
      "eligible": true,
      "lastSeenAt": "...",
      "lastSelectedAt": "...",
      "completedWakeCountByWindow": { "session": 0, "weekly": 3 },
      "inFlightWakeId": null
    }
  },
  "wakeEvents": [
    {
      "id": "01J...",
      "createdAt": "...",
      "decisionInstanceId": "isaac-macbook-paperclip-default",
      "providerAccountKey": "claude:isaac-claude-main",
      "companyId": "bcac096e-4aff-4ce3-ad33-c4e0b693b36f",
      "agentId": "agent-uuid",
      "wakeKind": "planning",
      "status": "queued",
      "reason": "weekly_deficit_and_fair_turn",
      "usageBefore": { "session": 0.03, "weekly": 0.18 },
      "targetAtDecision": { "session": 0.10, "weekly": 0.35 },
      "estimatedCost": 0.015,
      "paperclipRunId": null,
      "expiresAt": "..."
    }
  ],
  "estimateModel": {
    "claude:planning": 0.015,
    "claude:review": 0.020,
    "codex:implementation": 0.025
  }
}
```

Retention:

- Keep full wake events for 14 days.
- Keep daily aggregate summaries for 90 days.
- Compact old event records after successful backup.

## 8. Locking, staleness, and conflict recovery

### 8.1 Lock acquisition

Because cloud-synced files can conflict, use a best-effort lock with fencing tokens:

1. Read the file.
2. If `lock.expiresAt` is in the future and owner is not this instance, do not write.
3. Write a new lock with a random token, this instance ID, `acquiredAt`, `expiresAt = now + 30 seconds`, and `fencingToken + 1`.
4. Re-read the file after a short jittered delay.
5. Proceed only if the lock token and fencing token still match.

All wake events written under a lock must include the fencing token. If two instances produce conflicting events, keep the event with the higher fencing token and mark the other `conflict_lost` unless it already launched a Paperclip run.

### 8.2 Stale participants

Mark participant stale if `lastSeenAt` is older than:

```text
max(2 * pluginCadenceSeconds, 15 minutes)
```

A stale participant is skipped for new local wake ownership, but its fairness history remains. This handles a computer being off.

### 8.3 Computer-off fallback

If a computer is off:

- Other computers continue using their local eligible agents.
- The offline computer's agents are excluded from `eligibleAgentCount` after staleness threshold.
- When the computer returns, it does not immediately receive a burst to catch up; fairness debt is capped at 2 wakes per provider/account so it rejoins gradually.

### 8.4 Cloud-sync conflict files

If the synced provider creates conflict copies:

- Detect sibling files with the configured basename plus conflict markers.
- Parse all valid state files.
- Merge by `wakeEvents.id`, highest `fencingToken`, and latest `updatedAt` for summaries.
- Write a clean canonical file.
- Move conflict copies to an archive folder after successful merge.
- Log a `conflict_recovered` event.

## 9. Paperclip integration points

### 9.1 Reading usage

Required first path:

1. Read Paperclip's built-in usage tracking and limit records for the provider/account.
2. Normalize the existing records into the plugin snapshot model without duplicating Paperclip's usage store.
3. Use those normalized records to keep each provider/account under the owner-defined pacing limits.

Fallback path, only when built-in usage tracking is unavailable or incomplete:

1. Provider adapter telemetry already recorded by Paperclip runs.
2. Approved local provider dashboard export or CSV.
3. Manual/unknown fallback: disable catch-up scheduling and only run conservative CEO wake if operator explicitly enables fallback estimates.

The implementation task must first locate the actual Paperclip usage-tracking API/service and map its existing fields. Do not add a second usage-tracking database unless Paperclip lacks a necessary field after discovery; if extra storage is needed, store only derived pacing metadata and references to Paperclip's source usage record.

### 9.2 Triggering wakes

Use Paperclip's existing agent heartbeat invoke path, equivalent to:

```http
POST /api/agents/{agentId}/heartbeat/invoke
Content-Type: application/json

{
  "reason": "subscription_usage_manager",
  "triggerDetail": "...",
  "forceFreshSession": false
}
```

Before calling, verify:

- agent belongs to configured company,
- agent is not paused/error unless recovery config allows it,
- no live run already exists for that agent/issue that would make the wake duplicate,
- selected work item is actionable and not blocked/done/cancelled,
- provider quota decision is still valid after a fresh usage read.

### 9.3 Avoiding hidden heartbeat policy violations

The plugin is not a general heartbeat toggle. It is a bounded quota-aware scheduler. Every non-CEO wake must be traceable to:

- explicit eligibility config,
- actionable issue or permitted role routine,
- provider/account budget decision,
- fairness decision.

If any part is missing, skip the wake and record why.

### 9.4 Operator controls

Add config and/or UI controls for:

- enable/disable plugin per company,
- provider account mapping,
- agent eligibility and reason,
- final-day catch-up enabled/disabled,
- session hard-stop thresholds,
- shared state path,
- dry-run mode,
- emergency pause until timestamp.

Default mode for first rollout should be dry-run for at least one weekly cycle unless Isaac explicitly asks to activate live wakes sooner.

## 10. Scheduling cadence

The plugin may run periodically, but not as an unbounded hidden poller. Recommended cadence:

- Dry-run/normal: every 15 minutes.
- Final 24 hours before weekly reset: every 10 minutes.
- Final 2 hours before weekly reset: every 5 minutes.
- Never schedule more than one wake decision per provider/account per 10 minutes unless manually overridden.

Each tick must be cheap: read config, read usage, acquire lock, decide, write log, optionally invoke one wake.

## 11. Failure behavior

### 11.1 Usage data unavailable

If fresh usage data is unavailable:

- Do not schedule catch-up wakes.
- Allow only explicitly configured conservative CEO wake if `fallbackMode = conservative` and the last known usage is below 50% for both session and weekly windows.
- Record `usage_unavailable` with provider/account and data age.

### 11.2 Shared state unavailable

If the state file cannot be read/written:

- Do not coordinate multi-computer fairness.
- In live mode, fall back to local-only scheduling only if `allowLocalFallback = true`.
- Local fallback cap: one CEO wake per provider/account per 6-hour session and no non-CEO wakes.
- Record `shared_state_unavailable` locally and surface an operator warning.

### 11.3 Paperclip wake fails

If heartbeat invoke fails:

- Mark wake event `failed` with HTTP status/error.
- Do not immediately retry more than once.
- Leave quota estimate unchanged unless usage changed.
- If repeated failures occur for the same agent, mark participant temporarily ineligible and create or update a Paperclip operator issue only after threshold is reached.

### 11.4 Clock skew

If local time differs from state file or provider observations beyond `clockSkewToleranceSeconds`, do not write decisions; record `clock_skew_detected` and require operator/system time fix.

## 12. Acceptance checklist for BackendCoder

Backend implementation is ready when all of the following are true:

- Config model exists for company/provider/account/agent eligibility with explicit reasons.
- Usage snapshot normalization reads Paperclip's existing usage tracking first and supports at least `session` and `weekly` windows, percentages, reset time, duration, limit metadata, source record ID/reference, and confidence.
- Pacing algorithm implements:
  - even-burn `optimalUsed = elapsed / duration`,
  - pre-final-day weekly target `optimal - 0.05`,
  - final-day ramp to 99.5% by the last 2 hours,
  - session hard stops at 90% and 95%,
  - weekly hard stop at 99.5%,
  - wake-cost estimates and smoothing.
- Fairness algorithm selects by provider/account/company/agent turn debt and excludes stale/offline participants.
- Shared JSON state file implements schema versioning, lock token, fencing token, stale participant handling, event retention, and conflict recovery.
- Paperclip heartbeat invoke integration records reason and trigger detail for every plugin wake.
- Dry-run mode records all decisions without invoking wakes.
- Government Watchdog can be enabled without enabling WPR2/WEI or other companies.
- Non-CEO wakes are impossible unless explicit eligibility config exists.
- Tests cover math boundaries:
  - screenshot-like session state: 3% used, 4 hr 49 min remaining in a 6-hour window,
  - weekly 18% used with pre-final-day target,
  - final-day ramp,
  - hard-stop thresholds,
  - fairness tie-breaks,
  - stale/offline participant removal,
  - lock conflict and recovery.
- Logs expose enough evidence for CTO/security review without leaking provider secrets.

## 13. Security and privacy review checklist

Security/privacy/ops review should verify:

- Shared state contains no secrets, tokens, private prompts, generated content, or user data beyond IDs and scheduling metadata.
- State file path is configurable and can be moved out of public/shared folders.
- File permissions are owner-readable/writable only where the OS supports it.
- Wakes cannot be triggered by untrusted edits to the state file without local config confirming agent/company/provider eligibility.
- All provider/account keys are aliases, not raw credentials.
- Plugin cannot schedule campaign/publication/official-contact automation.
- Plugin has emergency pause and per-company disable controls.
- Failure mode is fail-closed for unknown usage, corrupted state, clock skew, and provider hard stops.

## 14. Suggested first rollout plan

1. Locate and document Paperclip's existing usage-tracking API/service and limit fields.
2. Implement the math model and state schema behind unit tests.
3. Add dry-run telemetry using existing Paperclip usage tracking only.
4. Enable dry-run for Government Watchdog provider accounts for one weekly cycle.
5. Review dry-run decisions against actual usage and fairness.
6. Enable live wakes for Government Watchdog CEO only.
7. After one successful week, optionally enable explicitly qualifying key agents.
8. Only after GOV is stable, consider additional companies/computers with the synced state file.

## 15. Open implementation questions

BackendCoder should answer these during implementation discovery and record the answers in the implementation issue:

- Where exactly does the current Paperclip build expose built-in usage tracking and limits, and what are the field names for percentage, reset timestamp, window kind/duration, provider/account alias, and source record ID?
- Does Paperclip's heartbeat invoke route accept `forceFreshSession` and custom `triggerDetail` in the deployed version for all adapters?
- Which provider/account aliases should Government Watchdog use for Claude and Codex in the first dry run?
- What synced folder path will Isaac use for cross-computer coordination?
- Does the plugin run inside the Paperclip server process, as a local plugin process, or as a managed scheduler job registered by Paperclip?

Until those questions are answered, implementation should stay in dry-run mode.

# Companion Rules System — Full Design Plan

## Context

The Companion Rules page (`PartsCompanionsPage.swift`, 635 lines) needs a major overhaul. Currently it picks individual parts for rules (wrong — should be category/style/type level), uses raw SQL, hard deletes, and has no poll/auto-discovery system. The user wants a sophisticated auto-discovery engine that analyzes PO/job history, proposes new companion rules via weekly team polls, and cascades from categories down through styles → types → brands.

## Architecture Summary

### Points System
- **1 point per part co-occurrence on the same job**
- Example: Job has Boxes(100), Outlets(75), Switches(25), Cover Plates(100)
  - Boxes+CoverPlates = 100pts, Boxes+Outlets = 75pts, Outlets+CoverPlates = 75pts, etc.
- **Thresholds**: 50 POs OR 3 months data (analysis window up to 48 months), 15+ co-occurrences, 15% confidence, 100 points minimum
- **Rejection**: -100 points per rejection. 5 rejections = permanently blocked (admin can reset)
- **Tied polls**: If result is tied, don't ask that pair again for 2 months minimum

### Hierarchical Cascade
- Category level accepted → recalculate points for Styles within those categories → poll
- Style level accepted → recalculate for Types → poll
- Type level accepted → check Brands → poll (end of cascade)
- Each level gets its own poll
- Deleting a parent rule: children turn red, auto-delete in 30 days, parent restorable

### Weekly Polls
- One new poll per week (highest-point qualified pair)
- Multiple can run simultaneously
- Ends: 30 days OR all eligible voted
- ALL users vote, only `companion_vote_power` permission holders count
- Track all votes for future leaderboard

### Admin Controls (requires `edit_parts_catalog` + `vote_veto` permissions)
1. **"I know the answer"**: Lock result. Poll still runs. Only admin+IT see it was locked.
2. **Skip**: Replace with next-best. -50 points penalty (points only).
3. **Preview**: See current + next week's poll. Can only skip current.

### Voting & Display
- Users see last week's result as "Passed/Didn't Pass" + their vote side
- Users can change vote until poll closes
- After 7 days, poll appears in clock-out questions
- If no qualifying poll: show training question (closest matches, historically confusing)

## Existing Infrastructure

### Tables (migration 016)
- `companion_rules`, `companion_rule_sources`, `companion_rule_targets` — missing `type_id`
- `co_occurrence_pairs` — missing points, level, rejection tracking
- `companion_suggestions`, `companion_feedback`, `part_alternatives` — exist

### Permissions
- `hat_permissions` table, `appCore.hasPermission("key")` in views
- Need new: `companion_vote_power` seeded for Admin, Manager, Lead
- Need new: `vote_veto` seeded for Admin only (admin controls: lock/skip/preview)

### Clock-Out Questions
- `clock_out_questions` + `clock_out_responses` tables exist
- `IOSQuestionnairePage.swift` exists but NOT wired into clock-out flow
- `JobsService.getActiveQuestions()`, `saveClockOutResponses()` exist

### PO/Job Data for Analysis
- `po_line_items.part_id` → `parts.category_id/style_id/type_id/brand_id`
- `job_parts.job_id + part_id` — co-occurrence source
- `purchase_orders.order_date` — for 3-month to 48-month analysis window

## Prompt Chain (19A–19K)

### 19A — Migration 025 + Models ✅ (written, needs update)

**File**: `core/Sources/WiredPartCore/Database/AppDatabase+Migrations.swift`

ALTER existing:
- `companion_rule_sources/targets`: add `type_id` column
- `companion_rules`: add `try_match_brand`, `auto_color_match`, `parent_rule_id`, `auto_delete_at`, `deleted_at`
- `co_occurrence_pairs`: add `points`, `style_a/b_id`, `type_a/b_id`, `brand_a/b_id`, `match_level`, `rejection_count`, `is_blocked`

CREATE new:
- `companion_polls`: co_occurrence_pair_id, match_level, source/target IDs, status (active/closed/locked), locked_by/result/at, start/end dates
- `companion_votes`: poll_id, user_id, vote (yes/no), has_power (cached), voted_at — UNIQUE(poll_id, user_id)
- `companion_poll_results`: poll_id, passed, yes/no counts, powered yes/no counts, finalized_at

Also:
- Seed `companion_vote_power` permission for Admin, Manager, Lead hats
- Seed `vote_veto` permission for Admin hat only
- Add `tied_cooldown_until` column to `co_occurrence_pairs` (2-month cooldown for tied polls)
- Add new tables to ConflictResolver + ChangeTracker
- Model structs: `CompanionPoll`, `CompanionVote`, `CompanionPollResult`

### 19B — Service: Rules CRUD + Points Engine

**File**: `core/Sources/WiredPartCore/Services/PartsService.swift`

Methods:
- `listCompanionRulesWithHierarchy()` — grouped by parent, children show orphan status
- `createCompanionRuleAtLevel(...)` — category/style/type level with brand/color flags
- `deleteCompanionRuleSoft(id:)` — sets deleted_at, marks children for 30-day auto-delete
- `restoreCompanionRule(id:)` — clears deletion on self + children
- `purgeExpiredRules()` — hard-delete past auto_delete_at
- `addRuleSources/Targets(ruleId:, entries:)`
- `listAllAlternatives()` — for the alternatives tab (replaces raw SQL)
- `calculateCoOccurrencePoints()` — scan job_parts, count co-occurrences per job, write points
- `getQualifiedPairs(minPoints:100, minConfidence:0.15, minJobs:15)` — pairs meeting thresholds
- `applyRejectionPenalty(pairId:)` — subtract 100 points
- `blockPair(pairId:)` — 5th rejection = permanent block
- `resetBlockedPair(pairId:)` — admin reset

### 19C — Service: Polls + Voting

**File**: `core/Sources/WiredPartCore/Services/PartsService.swift`

Methods:
- `createWeeklyPoll()` — pick highest-point qualified pair, create poll with 30-day end
- `getActivePolls()` — all currently active polls with vote counts
- `getPollDetail(pollId:)` — poll + votes + result
- `castVote(pollId:, userId:, vote:)` — insert/update, cache has_power from permission
- `closePoll(pollId:)` — count powered votes, determine pass/fail, create rule if passed, trigger next-level recalculation. If tied: set `tied_cooldown_until` to 2 months out, don't re-ask until cooldown expires
- `adminLockPoll(pollId:, result:, lockedBy:)` — lock result, poll still runs. Requires `vote_veto` permission
- `adminSkipPoll(pollId:)` — close + -50 points, create replacement poll. Requires `vote_veto` permission
- `getLastWeekResults(userId:)` — pass/fail + user's vote side
- `getUserVotingAccuracy(userId:)` — training metric
- `getNextPollPreview()` — next-best pair for admin
- `getTrainingQuestion()` — closest-to-threshold pair + historically confusing votes
- `getActivePollsForClockOut()` — polls 7+ days active, formatted for questionnaire

### 19D — Page Cleanup: Raw SQL → Service, Errors, Guards

**File**: `Weird Parts IOS/.../Features/Parts/PartsCompanionsPage.swift`

- Remove `import GRDB`
- Replace all raw SQL with PartsService calls
- Add `@State private var loadError/actionError` with user-visible error banners
- Add delete confirmation alerts (no more silent hard deletes)
- Remove all `#if os(iOS)` / `#elseif os(macOS)` guards
- Show orphaned child rules in red with "Deleting in X days" badge
- Use `guard let service = appCore.partsService` pattern

### 19E — Rule Form Rebuild: Hierarchy Pickers

**File**: `Weird Parts IOS/.../Features/Parts/PartsCompanionsPage.swift`

Replace CompanionRuleFormSheet:
- **Level picker**: Category / Style / Type
- **Source picker**: cascading — pick category, then style (if level=style+), then type (if level=type)
- **Target picker**: same cascading pattern
- **Options**: Try Match Brand toggle, Color Auto-Match toggle, Qty mode, Qty ratio
- **Parent rule link**: if creating child rule, show parent name
- Supports create AND edit modes
- Uses `partsService.listCategories()`, `listStyles(categoryId:)`, `listTypes(styleId:)`
- Saves via `createCompanionRuleAtLevel()` + `addRuleSources()` + `addRuleTargets()`

### 19F — Polls UI: Vote Cards, Admin Controls

**File**: `Weird Parts IOS/.../Features/Parts/PartsCompanionsPage.swift`

Add third tab: **Polls**
- **Active Poll Card**: source→target names, vote Yes/No buttons, days remaining, change vote option
- **Last Week's Result**: Pass/Fail banner + user's vote side
- **Admin Controls** (gated by `edit_parts_catalog` + `vote_veto` permissions):
  - "I Know the Answer" — lock button, lock icon only visible to admin/IT
  - "Skip" — confirmation dialog, replaces with next-best
  - "Preview Next Week" — shows next pair
- **Training Question** (when no qualifying poll): practice question, clearly marked, no real vote
- **Vote counts**: visible only to admin, everyone else sees just their own vote

### 19G — Clock-Out Integration

**Files**: `IOSQuestionnairePage.swift`, `IOSClockPage.swift`

- After loading regular clock-out questions, append companion polls 7+ days active as Yes/No items
- Submitting a poll answer calls `partsService.castVote()` behind the scenes
- Verify/wire questionnaire sheet into clock-out flow in IOSClockPage

### 19H — Rule Testing Sandbox

**File**: NEW `Weird Parts IOS/.../Features/Parts/CompanionSandboxSheet.swift`

- "What If" scenario: pick categories/styles being ordered
- Shows which rules would fire and what they'd suggest
- Shows current hierarchy level + possible next level examples
- Uses real PO/job data for context-aware examples
- Read-only, no data modification
- Accessible from toolbar button on Companions page

### 19I — Admin Voting Dashboard

**File**: `Weird Parts IOS/.../Features/Parts/PartsCompanionsPage.swift`

- Admin section showing voting analytics
- Per-user accuracy (% voting with winning side) — training tool
- Historical poll results with drill-down
- Total auto-discovered vs manual rules
- Permission-gated: admin/manager only

### 19J — Auto-Discovery Engine

**File**: `core/Sources/WiredPartCore/Services/PartsService.swift`

- Full `calculateCoOccurrencePoints()` implementation scanning `job_parts`
- Analysis window: 3 months minimum to start, scans up to 48 months of history
- Threshold checking: 50 POs OR 3 months, 15+ co-occurrences, 15% confidence, 100+ points
- Tied pair handling: set `tied_cooldown_until` = 2 months out, skip pair in `getQualifiedPairs()` until cooldown expires
- Category pass → auto-recalculate at style level within accepted categories
- Style pass → type level, then brand level
- Blocked pair handling: 5 rejections = blocked, admin reset
- Trigger: on app launch or daily timer in AppCore

### 19K — AI Integration (read-only)

**Files**: `FoundationModelsService.swift`, `PartsCompanionsPage.swift`

- AI reads companion rules, active polls, co-occurrence data
- Explains why a pairing was suggested (points breakdown)
- Summarizes voting patterns
- Read-only, no editing

## Verification

After each prompt:
1. Project builds with no errors
2. Companions page loads without crashes
3. Rules display correctly at category/style/type level
4. Polls can be created/voted on
5. Admin controls work with proper permission gating
6. Clock-out integration presents polls after 7 days
7. Training questions appear when no qualifying poll exists

# 19C — Companion Polls + Voting Service Methods

## Context
You are working on a SwiftUI iOS app. Prompt 19B added rule CRUD and points engine methods to `PartsService.swift`. This prompt adds the poll lifecycle and voting system.

**Key tables (from migration 025):**
- `companion_polls` — co_occurrence_id, proposed_rule_name, match_level, source/target IDs, status (active/closed/locked/skipped), admin_locked_result/by/at, result, start_date, end_date
- `companion_votes` — poll_id, user_id, vote (accept/reject), has_power (cached from permission), voted_at. UNIQUE(poll_id, user_id)
- `companion_poll_results` — poll_id, passed, total_votes, powered_accept/reject, all_accept/reject, was_admin_locked
- `companion_rules` — existing table, auto-created when poll passes
- `co_occurrence_pairs` — points, rejection_count, is_blocked, tied_cooldown_until

**Permission keys:**
- `companion_vote_power` — if user has this, their vote counts toward results (Admin, Manager, Lead)
- `vote_veto` — admin controls: lock result, skip poll (Admin only)

**Existing methods from 19B:**
- `createCompanionRuleAtLevel(...)` — creates a rule with sources/targets
- `applyRejectionPenalty(pairId:)` — -100 points, blocks at 5 rejections
- `applySkipPenalty(pairId:)` — -50 points only
- `getQualifiedPairs(...)` — pairs meeting thresholds

## Task

Add the following methods to `PartsService.swift` in a `// MARK: - Companion Polls` section.

### 1. Display Row for Polls

```swift
/// Row for displaying a poll in the UI.
public struct CompanionPollDisplayRow: Sendable {
    public let pollId: Int64
    public let proposedRuleName: String
    public let proposedRuleDescription: String?
    public let sourceName: String           // resolved category/style/type name
    public let targetName: String           // resolved category/style/type name
    public let matchLevel: String
    public let status: String
    public let startDate: String
    public let endDate: String
    public let daysRemaining: Int
    public let myVote: String?              // "accept" or "reject" or nil if not voted
    public let totalVotes: Int
    public let poweredAcceptCount: Int      // only populated for admin
    public let poweredRejectCount: Int      // only populated for admin
    public let isAdminLocked: Bool
    public let adminLockedResult: String?   // only visible to admin/IT
    public let result: String?              // set after poll closes
}
```

### 2. Create Weekly Poll

```swift
/// Create a new weekly poll from the highest-scoring qualified pair.
/// Returns the new poll ID, or nil if no qualifying pairs exist.
/// Only call this once per week (check last poll's start_date before calling).
@discardableResult
public func createWeeklyPoll() throws -> Int64? {
    // 1. Check if a poll was already created this week
    //    SELECT id FROM companion_polls WHERE start_date >= date('now', '-7 days')
    //    If one exists, return nil (one poll per week max)

    // 2. Get qualified pairs (from 19B method)
    //    let pairs = try getQualifiedPairs()
    //    If empty, return nil

    // 3. Pick the highest-point pair (first in list, already sorted by points DESC)
    //    Use pair.catAName + " → " + pair.catBName for proposed_rule_name

    // 4. Resolve source/target names based on match_level:
    //    - "category": just category names
    //    - "style": category > style names
    //    - "type": category > style > type names

    // 5. Insert into companion_polls with status = "active", end_date = date('now', '+30 days')
    //    Set source/target category/style/type IDs from the pair

    // 6. Count total eligible voters: SELECT COUNT(DISTINCT uh.user_id) FROM user_hats uh
    //    JOIN hat_permissions hp ON hp.hat_id = uh.hat_id
    //    WHERE hp.permission_key = 'companion_vote_power' AND uh.is_active = 1

    // 7. Log to companion_auto_discovery_log

    // 8. Create a notification for all active users:
    //    INSERT INTO notifications (user_id, title, body, severity, source, entity_type, entity_id, type)
    //    For each active user: title = "New Companion Poll", body = proposed_rule_name,
    //    entity_type = "companion_poll", entity_id = poll_id

    // Return the poll ID
}
```

### 3. Get Active Polls

```swift
/// Get all currently active polls with the current user's vote status.
/// Admin/IT users see admin lock details; regular users don't.
public func getActivePolls(userId: Int64, isAdmin: Bool = false) throws -> [CompanionPollDisplayRow] {
    try db.writer.read { dbConn in
        let rows = try Row.fetchAll(dbConn, sql: """
            SELECT cp.*,
                   cv.vote AS my_vote,
                   (SELECT COUNT(*) FROM companion_votes WHERE poll_id = cp.id) AS total_votes,
                   (SELECT COUNT(*) FROM companion_votes WHERE poll_id = cp.id AND vote = 'accept' AND has_power = 1) AS powered_accept,
                   (SELECT COUNT(*) FROM companion_votes WHERE poll_id = cp.id AND vote = 'reject' AND has_power = 1) AS powered_reject,
                   COALESCE(ca_src.name, '') AS source_cat_name,
                   COALESCE(cs_src.name, '') AS source_style_name,
                   COALESCE(ct_src.name, '') AS source_type_name,
                   COALESCE(ca_tgt.name, '') AS target_cat_name,
                   COALESCE(cs_tgt.name, '') AS target_style_name,
                   COALESCE(ct_tgt.name, '') AS target_type_name
            FROM companion_polls cp
            LEFT JOIN companion_votes cv ON cv.poll_id = cp.id AND cv.user_id = ?
            LEFT JOIN part_categories ca_src ON ca_src.id = cp.source_category_id
            LEFT JOIN part_styles cs_src ON cs_src.id = cp.source_style_id
            LEFT JOIN part_types ct_src ON ct_src.id = cp.source_type_id
            LEFT JOIN part_categories ca_tgt ON ca_tgt.id = cp.target_category_id
            LEFT JOIN part_styles cs_tgt ON cs_tgt.id = cp.target_style_id
            LEFT JOIN part_types ct_tgt ON ct_tgt.id = cp.target_type_id
            WHERE cp.status = 'active'
            ORDER BY cp.start_date DESC
            """, arguments: [userId])

        return rows.map { row in
            let matchLevel: String = row["match_level"]
            // Build display names based on match level
            let sourceName = buildHierarchyName(
                category: row["source_cat_name"], style: row["source_style_name"],
                type: row["source_type_name"], level: matchLevel)
            let targetName = buildHierarchyName(
                category: row["target_cat_name"], style: row["target_style_name"],
                type: row["target_type_name"], level: matchLevel)

            let endDateStr: String = row["end_date"]
            let daysLeft = Calendar.current.dateComponents([.day],
                from: Date(), to: ISO8601DateFormatter().date(from: endDateStr) ?? Date()).day ?? 0

            return CompanionPollDisplayRow(
                pollId: row["id"],
                proposedRuleName: row["proposed_rule_name"],
                proposedRuleDescription: row["proposed_rule_description"],
                sourceName: sourceName,
                targetName: targetName,
                matchLevel: matchLevel,
                status: row["status"],
                startDate: row["start_date"],
                endDate: endDateStr,
                daysRemaining: max(0, daysLeft),
                myVote: row["my_vote"],
                totalVotes: row["total_votes"],
                poweredAcceptCount: isAdmin ? (row["powered_accept"] ?? 0) : 0,
                poweredRejectCount: isAdmin ? (row["powered_reject"] ?? 0) : 0,
                isAdminLocked: (row["admin_locked_result"] as String?) != nil,
                adminLockedResult: isAdmin ? row["admin_locked_result"] : nil,
                result: row["result"]
            )
        }
    }
}

/// Helper: build a display name like "Category > Style > Type" based on match level.
private func buildHierarchyName(category: String?, style: String?, type: String?, level: String) -> String {
    switch level {
    case "type":
        return [category, style, type].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " > ")
    case "style":
        return [category, style].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " > ")
    default:
        return category ?? "Unknown"
    }
}
```

### 4. Cast Vote

```swift
/// Cast or update a vote on a poll. Checks companion_vote_power permission and caches it.
/// All users can vote; only users with companion_vote_power have their vote count.
/// Users can change their vote until the poll closes.
public func castVote(pollId: Int64, userId: Int64, vote: String) throws {
    try db.writer.write { dbConn in
        // Verify poll is active
        guard let poll = try Row.fetchOne(dbConn, sql: "SELECT status FROM companion_polls WHERE id = ?", arguments: [pollId]),
              (poll["status"] as String) == "active" else {
            return // Poll is not active, silently ignore
        }

        // Check if user has companion_vote_power permission
        let hasPower = try Int.fetchOne(dbConn, sql: """
            SELECT COUNT(*) FROM user_hats uh
            JOIN hat_permissions hp ON hp.hat_id = uh.hat_id
            WHERE uh.user_id = ? AND uh.is_active = 1 AND hp.permission_key = 'companion_vote_power'
            """, arguments: [userId]) ?? 0

        // Upsert: insert or update vote
        try dbConn.execute(sql: """
            INSERT INTO companion_votes (poll_id, user_id, vote, has_power, voted_at, updated_at)
            VALUES (?, ?, ?, ?, datetime('now'), datetime('now'))
            ON CONFLICT(poll_id, user_id)
            DO UPDATE SET vote = excluded.vote, updated_at = datetime('now')
            """, arguments: [pollId, userId, vote, hasPower > 0 ? 1 : 0])

        // Check if all eligible voters have voted — if so, auto-close
        let eligibleCount = try Int.fetchOne(dbConn, sql: """
            SELECT COUNT(DISTINCT uh.user_id) FROM user_hats uh
            JOIN hat_permissions hp ON hp.hat_id = uh.hat_id
            WHERE hp.permission_key = 'companion_vote_power' AND uh.is_active = 1
            """) ?? 0

        let poweredVoteCount = try Int.fetchOne(dbConn, sql: """
            SELECT COUNT(*) FROM companion_votes
            WHERE poll_id = ? AND has_power = 1
            """, arguments: [pollId]) ?? 0

        if eligibleCount > 0 && poweredVoteCount >= eligibleCount {
            // All eligible users have voted — close the poll
            // (closePoll will be called separately to handle the result logic)
        }
    }
}
```

### 5. Close Poll

```swift
/// Close an active poll and determine the result.
/// If accepted: auto-creates a companion rule from the poll data.
/// If rejected: applies -100 point penalty to the co_occurrence_pair.
/// If tied: sets tied_cooldown_until to 2 months out, neither creates nor rejects.
public func closePoll(pollId: Int64) throws {
    try db.writer.write { dbConn in
        guard let poll = try Row.fetchOne(dbConn, sql: "SELECT * FROM companion_polls WHERE id = ?", arguments: [pollId]),
              (poll["status"] as String) == "active" || (poll["status"] as String) == "locked" else {
            return
        }

        let coOccurrenceId: Int64 = poll["co_occurrence_id"]
        let adminLockedResult: String? = poll["admin_locked_result"]

        // Count powered votes
        let poweredAccept = try Int.fetchOne(dbConn, sql: """
            SELECT COUNT(*) FROM companion_votes
            WHERE poll_id = ? AND vote = 'accept' AND has_power = 1
            """, arguments: [pollId]) ?? 0

        let poweredReject = try Int.fetchOne(dbConn, sql: """
            SELECT COUNT(*) FROM companion_votes
            WHERE poll_id = ? AND vote = 'reject' AND has_power = 1
            """, arguments: [pollId]) ?? 0

        // Count ALL votes (for leaderboard tracking)
        let allAccept = try Int.fetchOne(dbConn, sql: """
            SELECT COUNT(*) FROM companion_votes WHERE poll_id = ? AND vote = 'accept'
            """, arguments: [pollId]) ?? 0
        let allReject = try Int.fetchOne(dbConn, sql: """
            SELECT COUNT(*) FROM companion_votes WHERE poll_id = ? AND vote = 'reject'
            """, arguments: [pollId]) ?? 0
        let totalVotes = allAccept + allReject

        // Determine result
        let result: String
        let passed: Bool
        let wasLocked = adminLockedResult != nil

        if let locked = adminLockedResult {
            // Admin locked the result — use their decision
            result = locked == "accept" ? "accepted" : "rejected"
            passed = locked == "accept"
        } else if poweredAccept > poweredReject {
            result = "accepted"
            passed = true
        } else if poweredReject > poweredAccept {
            result = "rejected"
            passed = false
        } else {
            // Tied — 2 month cooldown, no action taken
            result = "tied"
            passed = false
            let cooldownDate = Calendar.current.date(byAdding: .month, value: 2, to: Date())!
            let cooldownStr = ISO8601DateFormatter().string(from: cooldownDate)
            try dbConn.execute(sql: """
                UPDATE co_occurrence_pairs SET tied_cooldown_until = ? WHERE id = ?
                """, arguments: [cooldownStr, coOccurrenceId])
        }

        // Update poll status
        try dbConn.execute(sql: """
            UPDATE companion_polls SET status = 'closed', result = ?, completed_at = datetime('now')
            WHERE id = ?
            """, arguments: [result, pollId])

        // Write result record
        try dbConn.execute(sql: """
            INSERT INTO companion_poll_results
            (poll_id, passed, total_votes, powered_accept, powered_reject,
             all_accept, all_reject, was_admin_locked, finalized_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, datetime('now'))
            """, arguments: [pollId, passed ? 1 : 0, totalVotes,
                             poweredAccept, poweredReject, allAccept, allReject,
                             wasLocked ? 1 : 0])

        // Handle result
        if passed && result != "tied" {
            // Auto-create companion rule from poll data
            let matchLevel: String = poll["match_level"]
            let sourceCatId: Int64? = poll["source_category_id"]
            let sourceStyleId: Int64? = poll["source_style_id"]
            let sourceTypeId: Int64? = poll["source_type_id"]
            let targetCatId: Int64? = poll["target_category_id"]
            let targetStyleId: Int64? = poll["target_style_id"]
            let targetTypeId: Int64? = poll["target_type_id"]
            let ruleName: String = poll["proposed_rule_name"]

            try dbConn.execute(sql: """
                INSERT INTO companion_rules
                (name, description, style_match, qty_mode, qty_ratio, try_match_brand, auto_color_match,
                 is_active, created_at, updated_at)
                VALUES (?, 'Auto-created from poll', ?, 'sum', 1.0, ?, ?, 1, datetime('now'), datetime('now'))
                """, arguments: [ruleName, matchLevel,
                                 poll["try_match_brand"] as Int,
                                 poll["auto_color_match"] as Int])
            let ruleId = dbConn.lastInsertedRowID

            // Add sources
            if let catId = sourceCatId {
                try dbConn.execute(sql: """
                    INSERT INTO companion_rule_sources (rule_id, category_id, style_id, type_id)
                    VALUES (?, ?, ?, ?)
                    """, arguments: [ruleId, catId, sourceStyleId, sourceTypeId])
            }

            // Add targets
            if let catId = targetCatId {
                try dbConn.execute(sql: """
                    INSERT INTO companion_rule_targets (rule_id, category_id, style_id, type_id)
                    VALUES (?, ?, ?, ?)
                    """, arguments: [ruleId, catId, targetStyleId, targetTypeId])
            }

            // Link poll to created rule
            try dbConn.execute(sql: """
                UPDATE companion_polls SET created_rule_id = ? WHERE id = ?
                """, arguments: [ruleId, pollId])
        } else if result == "rejected" {
            // Apply rejection penalty
            try dbConn.execute(sql: """
                UPDATE co_occurrence_pairs
                SET points = MAX(0, points - 100),
                    rejection_count = rejection_count + 1,
                    is_blocked = CASE WHEN rejection_count + 1 >= 5 THEN 1 ELSE 0 END,
                    last_computed = datetime('now')
                WHERE id = ?
                """, arguments: [coOccurrenceId])
        }
    }
}
```

### 6. Admin Controls

```swift
/// Admin "I know the answer" — lock the poll result. Poll still runs visually.
/// Only admin + IT hat users will see the lock status.
/// Requires vote_veto permission.
public func adminLockPoll(pollId: Int64, result: String, lockedBy: Int64) throws {
    try db.writer.write { dbConn in
        try dbConn.execute(sql: """
            UPDATE companion_polls
            SET status = 'locked', admin_locked_result = ?, admin_locked_by = ?,
                admin_locked_at = datetime('now')
            WHERE id = ? AND status = 'active'
            """, arguments: [result, lockedBy, pollId])
    }
}

/// Admin skip — close the current poll and replace with the next-best suggestion.
/// Applies a -50 point penalty to the skipped pair.
/// Requires vote_veto permission.
@discardableResult
public func adminSkipPoll(pollId: Int64) throws -> Int64? {
    var newPollId: Int64?
    try db.writer.write { dbConn in
        // Get the co_occurrence_id before closing
        guard let poll = try Row.fetchOne(dbConn, sql: "SELECT co_occurrence_id FROM companion_polls WHERE id = ?", arguments: [pollId]) else { return }
        let coOccurrenceId: Int64 = poll["co_occurrence_id"]

        // Close the poll as skipped
        try dbConn.execute(sql: """
            UPDATE companion_polls SET status = 'skipped', result = 'skipped', completed_at = datetime('now')
            WHERE id = ?
            """, arguments: [pollId])

        // Apply -50 point penalty (points only, no rejection count)
        try dbConn.execute(sql: """
            UPDATE co_occurrence_pairs SET points = MAX(0, points - 50), last_computed = datetime('now')
            WHERE id = ?
            """, arguments: [coOccurrenceId])
    }

    // Create a replacement poll (next-best pair)
    newPollId = try createWeeklyPoll()
    return newPollId
}

/// Admin preview: get the next-best pair that would become next week's poll.
/// Requires vote_veto permission.
public func getNextPollPreview() throws -> (pairId: Int64, catAName: String, catBName: String, points: Int, confidence: Double)? {
    let pairs = try getQualifiedPairs()
    // Skip any pairs that already have active polls
    guard let best = pairs.first else { return nil }
    return (pairId: best.pairId, catAName: best.catAName, catBName: best.catBName,
            points: best.points, confidence: best.confidence)
}
```

### 7. Results & History

```swift
/// Get last week's poll results for a user — shows pass/fail + which side they voted on.
public func getLastWeekResults(userId: Int64) throws -> [(pollName: String, passed: Bool, myVote: String?, matchedWinner: Bool)] {
    try db.writer.read { dbConn in
        let rows = try Row.fetchAll(dbConn, sql: """
            SELECT cp.proposed_rule_name, cpr.passed,
                   cv.vote AS my_vote
            FROM companion_polls cp
            JOIN companion_poll_results cpr ON cpr.poll_id = cp.id
            LEFT JOIN companion_votes cv ON cv.poll_id = cp.id AND cv.user_id = ?
            WHERE cp.completed_at >= datetime('now', '-7 days')
            ORDER BY cp.completed_at DESC
            """, arguments: [userId])

        return rows.map { row in
            let passed = (row["passed"] as Int) == 1
            let myVote: String? = row["my_vote"]
            let matchedWinner: Bool
            if let vote = myVote {
                matchedWinner = (vote == "accept" && passed) || (vote == "reject" && !passed)
            } else {
                matchedWinner = false
            }
            return (pollName: row["proposed_rule_name"] as String,
                    passed: passed, myVote: myVote, matchedWinner: matchedWinner)
        }
    }
}

/// Get a user's voting accuracy (% of times they voted with the winning side).
/// Used as a training metric — admin can see this for all users.
public func getUserVotingAccuracy(userId: Int64) throws -> (totalVotes: Int, correctVotes: Int, accuracy: Double) {
    try db.writer.read { dbConn in
        let row = try Row.fetchOne(dbConn, sql: """
            SELECT COUNT(*) AS total,
                   SUM(CASE
                       WHEN (cv.vote = 'accept' AND cpr.passed = 1)
                         OR (cv.vote = 'reject' AND cpr.passed = 0) THEN 1
                       ELSE 0
                   END) AS correct
            FROM companion_votes cv
            JOIN companion_poll_results cpr ON cpr.poll_id = cv.poll_id
            WHERE cv.user_id = ?
            """, arguments: [userId])

        let total = (row?["total"] as Int?) ?? 0
        let correct = (row?["correct"] as Int?) ?? 0
        let accuracy = total > 0 ? Double(correct) / Double(total) : 0.0
        return (totalVotes: total, correctVotes: correct, accuracy: accuracy)
    }
}
```

### 8. Training Questions & Clock-Out Integration

```swift
/// When no qualifying poll exists this week, generate a training question.
/// Uses the closest-to-threshold pair and historically most-confusing votes.
/// Returns nil if no suitable training data exists.
public func getTrainingQuestion() throws -> (sourceName: String, targetName: String, points: Int, isTraining: Bool)? {
    try db.writer.read { dbConn in
        // Get the pair closest to qualifying (has some points but below threshold)
        let row = try Row.fetchOne(dbConn, sql: """
            SELECT cop.points,
                   ca.name AS cat_a_name, cb.name AS cat_b_name
            FROM co_occurrence_pairs cop
            JOIN part_categories ca ON ca.id = cop.category_a_id
            JOIN part_categories cb ON cb.id = cop.category_b_id
            WHERE cop.match_level = 'category'
              AND cop.is_blocked = 0
              AND cop.points > 0 AND cop.points < 100
            ORDER BY cop.points DESC
            LIMIT 1
            """)

        guard let row = row else { return nil }
        return (sourceName: row["cat_a_name"] as String,
                targetName: row["cat_b_name"] as String,
                points: row["points"] as Int,
                isTraining: true)
    }
}

/// Get active polls that have been running for 7+ days, formatted for clock-out questions.
/// These appear as recommended questions in the clock-out questionnaire.
public func getActivePollsForClockOut(userId: Int64) throws -> [(pollId: Int64, questionText: String, hasVoted: Bool)] {
    try db.writer.read { dbConn in
        let rows = try Row.fetchAll(dbConn, sql: """
            SELECT cp.id, cp.proposed_rule_name,
                   (cv.id IS NOT NULL) AS has_voted
            FROM companion_polls cp
            LEFT JOIN companion_votes cv ON cv.poll_id = cp.id AND cv.user_id = ?
            WHERE cp.status IN ('active', 'locked')
              AND cp.start_date <= date('now', '-7 days')
              AND cp.end_date >= date('now')
            ORDER BY cp.start_date ASC
            """, arguments: [userId])

        return rows.map { row in
            let name: String = row["proposed_rule_name"]
            return (pollId: row["id"] as Int64,
                    questionText: "Should \(name) be a companion rule?",
                    hasVoted: (row["has_voted"] as Int) == 1)
        }
    }
}

/// Check and close any expired polls (past end_date).
/// Call this on app launch or periodically.
public func closeExpiredPolls() throws {
    try db.writer.read { dbConn in
        let expiredIds = try Int64.fetchAll(dbConn, sql: """
            SELECT id FROM companion_polls
            WHERE status IN ('active', 'locked')
              AND end_date < date('now')
            """)

        for pollId in expiredIds {
            // closePoll is a write operation, so we call it separately
        }
    }
    // Close each expired poll
    let expiredIds = try db.writer.read { dbConn in
        try Int64.fetchAll(dbConn, sql: """
            SELECT id FROM companion_polls
            WHERE status IN ('active', 'locked') AND end_date < date('now')
            """)
    }
    for pollId in expiredIds {
        try closePoll(pollId: pollId)
    }
}
```

## Success Criteria
- [ ] `createWeeklyPoll()` picks highest-point pair, creates poll, notifies all users
- [ ] `getActivePolls(userId:, isAdmin:)` returns polls with vote status, admin sees lock details
- [ ] `castVote(pollId:, userId:, vote:)` inserts/updates with has_power cached from permission
- [ ] `closePoll(pollId:)` determines pass/fail/tied, creates rule if passed, applies penalties if rejected, sets cooldown if tied
- [ ] `adminLockPoll(...)` locks result, poll continues running
- [ ] `adminSkipPoll(...)` closes + -50 penalty + creates replacement
- [ ] `getNextPollPreview()` returns next-best pair for admin preview
- [ ] `getLastWeekResults(userId:)` shows pass/fail + user's vote side
- [ ] `getUserVotingAccuracy(userId:)` calculates % correct for training metric
- [ ] `getTrainingQuestion()` returns closest-to-threshold pair when no qualifying poll
- [ ] `getActivePollsForClockOut(userId:)` returns polls 7+ days old for clock-out integration
- [ ] `closeExpiredPolls()` auto-closes polls past their end_date
- [ ] Project builds with no errors

## Log Entry
```
## Prompt 19C Results (YYYY-MM-DD)
- Added CompanionPollDisplayRow struct
- Added createWeeklyPoll() with notification broadcasting
- Added getActivePolls() with admin-gated lock visibility
- Added castVote() with has_power caching from companion_vote_power permission
- Added closePoll() with pass/fail/tied logic, auto-rule creation, rejection penalty, tied cooldown
- Added adminLockPoll/adminSkipPoll/getNextPollPreview admin controls
- Added getLastWeekResults/getUserVotingAccuracy for results display
- Added getTrainingQuestion/getActivePollsForClockOut for fallback + clock-out integration
- Added closeExpiredPolls() for periodic cleanup
- Build: [PASS/FAIL]
```

When done, start prompt 19D next.

# 37D — User Warehouse Ratings + Leaderboard + Consensus

> **Chain position:** 37A → 37B → 37C → **37D**
> **Prerequisite:** 37A (user_warehouse_ratings table exists)
> **Log file:** `xcode-ai/prompt-results-log.md`

## Task

### Leaderboard (visible to all)
- Shows on Warehouse Dashboard or Audit page
- Name + overall rating (0-10) + bar graph
- No detailed breakdown visible to regular users

### Manager Detail View (hat-locked)
- Per-user breakdown: accuracy, effort, placement, wizard compliance, speed, proactive
- Trend indicator (improving/declining/stable over 30 days)
- Training suggestion based on weakest area:
  - Low accuracy on small parts → "Start with larger items"
  - Low placement → "Buddy with [high-rated user]"
  - Persistent issues → AI training topic suggestion

### Multi-User Consensus Verification
- Triggers when: part confidence <60%, high dollar value, or mismatch history
- System assigns 2-3 users to count independently
- Users don't see each other's counts
- Results:
  - All match → all boosted, system updates, confidence 100%
  - All different → all lowered, manager recount flagged
  - 2 match, 1 off → 2 boosted, 1 lowered + training suggestion

### Rating Calculation
- Each audit action updates the user's rating
- Accurate count → accuracy up
- Proactive misplaced-part fix → proactive rating up
- Fast completion → speed up
- Following wizard properly → compliance up
- Overall = weighted average of all sub-ratings

## Success Criteria
- [ ] Leaderboard visible to all users (just name + score)
- [ ] Detailed breakdown for managers only
- [ ] Training suggestions based on weak areas
- [ ] Multi-user consensus system working
- [ ] Rating updates on every audit action
- [ ] Project builds with no errors

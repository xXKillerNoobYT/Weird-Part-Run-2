# 19F — Companion Polls UI: Vote Cards, Admin Controls

## Context
You are working on a SwiftUI iOS app. `PartsCompanionsPage.swift` currently has 2 tabs (Rules, Alternatives). This prompt adds a 3rd tab: **Polls** — the team voting interface for auto-suggested companion rules.

**Available PartsService methods (from 19C):**
- `getActivePolls(userId:, isAdmin:)` → `[CompanionPollDisplayRow]`
- `castVote(pollId:, userId:, vote:)` — cast or change vote
- `adminLockPoll(pollId:, result:, lockedBy:)` — lock result (vote_veto)
- `adminSkipPoll(pollId:)` → Int64? — skip + create replacement (vote_veto)
- `getNextPollPreview()` → optional tuple — next-best pair for admin
- `getLastWeekResults(userId:)` → [(pollName, passed, myVote, matchedWinner)]
- `getTrainingQuestion()` → optional tuple — practice question when no poll
- `closeExpiredPolls()` — auto-close past-due polls

**Permissions:**
- `companion_vote_power` — vote counts toward results (Admin, Manager, Lead)
- `vote_veto` — admin controls: lock, skip, preview (Admin only)
- Check with: `appCore.hasPermission("vote_veto")`

**Key rules:**
- Everyone sees the Polls tab and can vote
- Only users with `companion_vote_power` have their vote count toward results
- Admin controls only visible to users with `vote_veto` permission
- Admin lock status only visible to users with `vote_veto` permission
- If no qualifying poll: show a training question (practice, no real vote)
- Last week's results shown at the top

## Task

### 1. Add Polls tab

Update the `CompanionTab` enum to add `.polls`:
```swift
private enum CompanionTab {
    case rules, alternatives, polls
}
```

Add the tab to the segmented picker:
```swift
Text("Companion Rules").tag(CompanionTab.rules)
Text("Alternatives").tag(CompanionTab.alternatives)
Text("Polls").tag(CompanionTab.polls)
```

Add the view:
```swift
case .polls:
    pollsView
```

### 2. Polls state variables

```swift
@State private var activePolls: [PartsService.CompanionPollDisplayRow] = []
@State private var lastWeekResults: [(pollName: String, passed: Bool, myVote: String?, matchedWinner: Bool)] = []
@State private var trainingQuestion: (sourceName: String, targetName: String, points: Int, isTraining: Bool)?
@State private var nextPollPreview: (pairId: Int64, catAName: String, catBName: String, points: Int, confidence: Double)?
@State private var showLockConfirm = false
@State private var lockAction: String = "accept"
@State private var pollToLock: Int64?
@State private var showSkipConfirm = false
@State private var pollToSkip: Int64?
```

### 3. Load poll data

In `loadData()`, after loading rules and alternatives, also load polls:
```swift
let userId = appCore.currentUserId ?? 0
let isAdmin = appCore.hasPermission("vote_veto")
let polls = try service.getActivePolls(userId: userId, isAdmin: isAdmin)
let results = try service.getLastWeekResults(userId: userId)
let training = try service.getTrainingQuestion()
let preview = isAdmin ? try service.getNextPollPreview() : nil

// Also close any expired polls on load
try service.closeExpiredPolls()
try service.purgeExpiredRules()

await MainActor.run {
    activePolls = polls
    lastWeekResults = results
    trainingQuestion = training
    nextPollPreview = preview
    // ... existing assignments
}
```

### 4. Polls view

```swift
@ViewBuilder
private var pollsView: some View {
    ScrollView {
        VStack(spacing: 16) {
            // Last Week's Results
            if !lastWeekResults.isEmpty {
                lastWeekResultsSection
            }

            // Active Polls
            if activePolls.isEmpty {
                // No active polls — show training question or empty state
                if let training = trainingQuestion {
                    trainingQuestionCard(training)
                } else {
                    emptyPollsState
                }
            } else {
                ForEach(activePolls, id: \.pollId) { poll in
                    pollCard(poll)
                }
            }

            // Admin: Preview Next Week
            if appCore.hasPermission("vote_veto"), let preview = nextPollPreview {
                adminPreviewSection(preview)
            }
        }
        .padding()
    }
}
```

### 5. Last Week's Results Section

```swift
@ViewBuilder
private var lastWeekResultsSection: some View {
    VStack(alignment: .leading, spacing: 8) {
        Text("Last Week's Results")
            .font(.headline)
            .foregroundStyle(.secondary)

        ForEach(Array(lastWeekResults.enumerated()), id: \.offset) { _, result in
            HStack(spacing: 12) {
                Image(systemName: result.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(result.passed ? .green : .red)

                VStack(alignment: .leading, spacing: 2) {
                    Text(result.pollName)
                        .font(.subheadline)
                        .fontWeight(.medium)

                    HStack(spacing: 4) {
                        Text(result.passed ? "Passed" : "Didn't Pass")
                            .font(.caption)
                            .foregroundStyle(result.passed ? .green : .red)

                        if let myVote = result.myVote {
                            Text("·")
                            Text("You voted: \(myVote == "accept" ? "Yes" : "No")")
                                .font(.caption)
                                .foregroundStyle(result.matchedWinner ? .green : .orange)
                        }
                    }
                }
                Spacer()
            }
            .padding(12)
            .background(Color(.systemGray6))
            .cornerRadius(10)
        }
    }
}
```

### 6. Active Poll Card

```swift
@ViewBuilder
private func pollCard(_ poll: PartsService.CompanionPollDisplayRow) -> some View {
    VStack(alignment: .leading, spacing: 12) {
        // Header: match level badge + days remaining
        HStack {
            Text(poll.matchLevel.capitalized)
                .font(.caption2)
                .fontWeight(.semibold)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.accentColor.opacity(0.15))
                .clipShape(Capsule())

            Spacer()

            Text("\(poll.daysRemaining) days left")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        // Question: Source → Target
        HStack(spacing: 8) {
            Text(poll.sourceName)
                .font(.body)
                .fontWeight(.semibold)
            Image(systemName: "arrow.right")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(poll.targetName)
                .font(.body)
                .fontWeight(.semibold)
        }

        if let desc = poll.proposedRuleDescription, !desc.isEmpty {
            Text(desc)
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        // Vote buttons
        HStack(spacing: 12) {
            Button {
                Task { await vote(pollId: poll.pollId, vote: "accept") }
            } label: {
                HStack {
                    Image(systemName: poll.myVote == "accept" ? "hand.thumbsup.fill" : "hand.thumbsup")
                    Text("Yes, link these")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(poll.myVote == "accept" ? Color.green.opacity(0.2) : Color(.systemGray5))
                .cornerRadius(8)
            }
            .buttonStyle(.plain)

            Button {
                Task { await vote(pollId: poll.pollId, vote: "reject") }
            } label: {
                HStack {
                    Image(systemName: poll.myVote == "reject" ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                    Text("No")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(poll.myVote == "reject" ? Color.red.opacity(0.2) : Color(.systemGray5))
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }

        // Admin controls (vote_veto permission only)
        if appCore.hasPermission("vote_veto") {
            adminControlsSection(poll)
        }
    }
    .padding()
    .background(Color(.systemBackground))
    .cornerRadius(12)
    .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
}
```

### 7. Admin Controls Section (inside poll card)

```swift
@ViewBuilder
private func adminControlsSection(_ poll: PartsService.CompanionPollDisplayRow) -> some View {
    Divider()

    VStack(alignment: .leading, spacing: 8) {
        // Vote counts (admin only)
        HStack {
            Text("Powered votes: \(poll.poweredAcceptCount) accept / \(poll.poweredRejectCount) reject")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text("Total: \(poll.totalVotes)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        // Admin lock indicator (only visible to vote_veto holders)
        if poll.isAdminLocked, let lockedResult = poll.adminLockedResult {
            HStack {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.orange)
                Text("Locked: \(lockedResult == "accept" ? "Will Pass" : "Will Reject")")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.orange)
            }
        }

        // Admin action buttons
        HStack(spacing: 12) {
            if !poll.isAdminLocked {
                // "I Know the Answer" button
                Menu {
                    Button("Lock as Pass") {
                        pollToLock = poll.pollId
                        lockAction = "accept"
                        showLockConfirm = true
                    }
                    Button("Lock as Reject") {
                        pollToLock = poll.pollId
                        lockAction = "reject"
                        showLockConfirm = true
                    }
                } label: {
                    Label("Lock Result", systemImage: "lock.fill")
                        .font(.caption)
                }
            }

            Button {
                pollToSkip = poll.pollId
                showSkipConfirm = true
            } label: {
                Label("Skip", systemImage: "forward.fill")
                    .font(.caption)
            }
            .tint(.orange)
        }
    }
}
```

### 8. Training Question Card

```swift
@ViewBuilder
private func trainingQuestionCard(_ question: (sourceName: String, targetName: String, points: Int, isTraining: Bool)) -> some View {
    VStack(alignment: .leading, spacing: 12) {
        HStack {
            Image(systemName: "graduationcap.fill")
                .foregroundStyle(.blue)
            Text("Training Question")
                .font(.headline)
                .foregroundStyle(.blue)
            Spacer()
            Text("Practice")
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.blue.opacity(0.1))
                .clipShape(Capsule())
        }

        Text("Should these categories be linked as companions?")
            .font(.subheadline)
            .foregroundStyle(.secondary)

        HStack(spacing: 8) {
            Text(question.sourceName)
                .fontWeight(.semibold)
            Image(systemName: "arrow.right")
                .foregroundStyle(.secondary)
            Text(question.targetName)
                .fontWeight(.semibold)
        }

        Text("This is a practice question — your answer won't create any rules.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .italic()
    }
    .padding()
    .background(Color.blue.opacity(0.05))
    .cornerRadius(12)
    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.blue.opacity(0.2)))
}
```

### 9. Admin Preview Section

```swift
@ViewBuilder
private func adminPreviewSection(_ preview: (pairId: Int64, catAName: String, catBName: String, points: Int, confidence: Double)) -> some View {
    VStack(alignment: .leading, spacing: 8) {
        HStack {
            Image(systemName: "eye.fill")
                .foregroundStyle(.purple)
            Text("Next Week's Poll (Preview)")
                .font(.headline)
                .foregroundStyle(.purple)
        }

        HStack(spacing: 8) {
            Text(preview.catAName)
                .fontWeight(.medium)
            Image(systemName: "arrow.right")
                .foregroundStyle(.secondary)
            Text(preview.catBName)
                .fontWeight(.medium)
        }

        HStack {
            Text("\(preview.points) points")
                .font(.caption)
            Text("·")
            Text("\(Int(preview.confidence * 100))% confidence")
                .font(.caption)
        }
        .foregroundStyle(.secondary)
    }
    .padding()
    .background(Color.purple.opacity(0.05))
    .cornerRadius(12)
    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.purple.opacity(0.2)))
}
```

### 10. Vote + Admin action methods

```swift
private func vote(pollId: Int64, vote: String) async {
    do {
        guard let service = appCore.partsService, let userId = appCore.currentUserId else { return }
        try service.castVote(pollId: pollId, userId: userId, vote: vote)
        await loadData()
    } catch {
        actionError = "Vote failed: \(error.localizedDescription)"
    }
}
```

### 11. Confirmation alerts

Add to the view body (on the VStack or parent container):
```swift
.alert("Lock Poll Result?", isPresented: $showLockConfirm) {
    Button("Lock as \(lockAction == "accept" ? "Pass" : "Reject")", role: .destructive) {
        Task {
            guard let pollId = pollToLock, let service = appCore.partsService,
                  let userId = appCore.currentUserId else { return }
            do {
                try service.adminLockPoll(pollId: pollId, result: lockAction, lockedBy: userId)
                await loadData()
            } catch { actionError = error.localizedDescription }
        }
    }
    Button("Cancel", role: .cancel) {}
} message: {
    Text("The poll will continue running but the outcome is already decided. Only admin and IT users will see the lock.")
}

.alert("Skip This Poll?", isPresented: $showSkipConfirm) {
    Button("Skip (-50 points)", role: .destructive) {
        Task {
            guard let pollId = pollToSkip, let service = appCore.partsService else { return }
            do {
                _ = try service.adminSkipPoll(pollId: pollId)
                await loadData()
            } catch { actionError = error.localizedDescription }
        }
    }
    Button("Cancel", role: .cancel) {}
} message: {
    Text("This poll will be closed and a -50 point penalty applied. A replacement poll will be created from the next-best suggestion.")
}
```

### 12. Empty polls state

```swift
@ViewBuilder
private var emptyPollsState: some View {
    VStack(spacing: 16) {
        Image(systemName: "chart.bar.doc.horizontal")
            .font(.system(size: 48))
            .foregroundStyle(.secondary)
        Text("No Active Polls")
            .font(.title3)
            .fontWeight(.semibold)
        Text("The system needs at least 3 months of ordering data before it can suggest companion rules.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
}
```

## Success Criteria
- [ ] Polls tab added as third tab with segmented picker
- [ ] Active poll cards show source→target names, match level badge, days remaining
- [ ] Vote Yes/No buttons work and highlight current vote
- [ ] Users can change their vote (buttons update immediately)
- [ ] Last week's results shown at top with pass/fail + user's vote side
- [ ] Admin controls (lock/skip) visible ONLY to users with `vote_veto` permission
- [ ] Lock confirmation shows transparency message
- [ ] Skip confirmation shows -50 point penalty warning
- [ ] Admin preview shows next week's poll
- [ ] Training question card shown when no qualifying poll (clearly marked "Practice")
- [ ] Empty state with explanation when no polls exist
- [ ] Project builds with no errors

## Log Entry
```
## Prompt 19F Results (YYYY-MM-DD)
- Added Polls tab (3rd tab) with full voting interface
- Active poll cards: source→target, vote buttons, days remaining
- Last week's results: pass/fail + user's vote side
- Admin controls: lock result, skip poll, preview next week (vote_veto gated)
- Training question fallback when no qualifying poll
- Empty state for no polls
- Build: [PASS/FAIL]
```

When done, start prompt 19G next.

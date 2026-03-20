# 19G — Companion Polls Clock-Out Integration

## Context
You are working on a SwiftUI iOS app. Active companion polls (7+ days old) should appear as recommended questions during clock-out. The clock-out questionnaire system exists but is NOT wired into the clock-out flow.

**Existing files:**
- `IOSQuestionnairePage.swift` — questionnaire UI (exists, uses `JobsService.getActiveQuestions()`)
- `IOSClockPage.swift` — clock in/out page (calls `clockOut()` but doesn't present questionnaire)
- `JobsService.swift` — has `getActiveQuestions()`, `saveClockOutResponses(laborEntryId:, responses:)`

**Available PartsService method (from 19C):**
- `getActivePollsForClockOut(userId:)` → `[(pollId: Int64, questionText: String, hasVoted: Bool)]`
- `castVote(pollId:, userId:, vote:)` — cast a vote from the questionnaire

## Task

### 1. Wire questionnaire into clock-out flow

In `IOSClockPage.swift`, after a successful `clockOut()` call, present the `IOSQuestionnairePage` as a sheet:

```swift
@State private var showQuestionnaire = false
@State private var lastLaborEntryId: Int64?
```

After `clockOut()` succeeds:
```swift
lastLaborEntryId = laborEntryId
showQuestionnaire = true
```

Add sheet:
```swift
.sheet(isPresented: $showQuestionnaire) {
    if let entryId = lastLaborEntryId {
        IOSQuestionnairePage(laborEntryId: entryId)
    }
}
```

### 2. Add companion poll questions to IOSQuestionnairePage

In `IOSQuestionnairePage.swift`, after loading regular questions via `jobsService.getActiveQuestions()`, also load companion polls:

```swift
// Load companion polls (7+ days active) as additional questions
if let partsService = appCore.partsService, let userId = appCore.currentUserId {
    let pollQuestions = try partsService.getActivePollsForClockOut(userId: userId)
    for pq in pollQuestions where !pq.hasVoted {
        // Add as a special "companion_poll" type question
        // Display as a Yes/No toggle with the poll question text
        // Mark these distinctly in the UI (e.g., with a link icon)
    }
}
```

Add a section header above companion poll questions:
```swift
if hasCompanionQuestions {
    Section {
        HStack {
            Image(systemName: "link.badge.plus")
                .foregroundStyle(.blue)
            Text("Companion Rule Votes")
                .font(.subheadline)
                .fontWeight(.medium)
            Spacer()
            Text("Recommended")
                .font(.caption2)
                .foregroundStyle(.blue)
        }
    }
}
```

### 3. Handle companion poll answers on submit

When the questionnaire is submitted, for each companion poll question that was answered:
```swift
// Save companion poll votes
for pollAnswer in companionPollAnswers {
    try partsService.castVote(
        pollId: pollAnswer.pollId,
        userId: userId,
        vote: pollAnswer.answeredYes ? "accept" : "reject"
    )
}
```

These are separate from regular clock-out responses — don't save them to `clock_out_responses`.

### 4. Make companion poll questions optional

Companion poll questions should NEVER be required. Users can skip them. Only regular clock-out questions respect the `is_required` flag.

## Success Criteria
- [ ] Questionnaire sheet presented after successful clock-out
- [ ] Companion polls (7+ days old, not yet voted) appear as Yes/No questions
- [ ] Companion questions clearly marked with "Companion Rule Votes" section header
- [ ] Companion questions are always optional (never block submission)
- [ ] Voting from questionnaire calls `partsService.castVote()` correctly
- [ ] Regular clock-out questions still work as before
- [ ] Project builds with no errors

## Log Entry
```
## Prompt 19G Results (YYYY-MM-DD)
- Wired IOSQuestionnairePage sheet into IOSClockPage clock-out flow
- Added companion poll questions (7+ days active) to questionnaire
- Companion questions marked as "Recommended", always optional
- Voting from questionnaire calls partsService.castVote()
- Build: [PASS/FAIL]
```

When done, start prompt 19H next.

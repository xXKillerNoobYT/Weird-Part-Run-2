# 42D — Q&A Escalation Ladder + Smart Cards

> **Chain position:** 42A → 42B → 42C → **42D**
> **Prerequisite:** 42A (unified inbox)
> **Log file:** `xcode-ai/prompt-results-log.md`

## MANDATORY RULES
1. DO NOT use `import GRDB` in UI files
2. DO NOT use empty `catch { }` blocks
3. DO NOT use `#if os(iOS)` guards
4. Use ActiveSheet enum for all sheets

## Instructions

**IMPORTANT:** Before implementing, read `IOSQuestionsPage.swift`, `IOSRFIListPage.swift`, and `ChatService.swift`. Add visual escalation ladder, fix silent guard returns on both pages, and replace capsule chips with smart cards.

## Context

Q&A threads follow an escalation chain: Worker → Lead → Manager → Office. Currently there's no visual representation of where a question is in this chain. Workers need to see who reviewed their question and when. The "push back down" option lets managers send questions back with feedback instead of just answering. Both the Q&A and RFI pages need the same fixes (silent guards, capsule → smart cards).

## Task

### Step 1: Create IOSEscalationTimeline Component

Create `Weird Parts IOS/Weird Parts IOS/Features/Chat/IOSEscalationTimeline.swift`:

```swift
import SwiftUI

struct EscalationStep: Identifiable, Sendable {
    let id: Int64
    let level: String      // "worker", "lead", "manager", "office"
    let levelLabel: String  // "Worker", "Lead", "Manager", "Office"
    let isCurrent: Bool
    let isComplete: Bool
    let reviewedBy: String?
    let reviewedAt: Date?
    let notes: String?
}

struct IOSEscalationTimeline: View {
    let steps: [EscalationStep]
    let canEscalate: Bool
    let canPushBack: Bool
    let onEscalate: () -> Void
    let onPushBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                HStack(alignment: .top, spacing: 12) {
                    // Timeline node
                    VStack(spacing: 0) {
                        Circle()
                            .fill(step.isCurrent ? Color.blue : step.isComplete ? Color.green : Color.gray.opacity(0.3))
                            .frame(width: 12, height: 12)
                        if index < steps.count - 1 {
                            Rectangle()
                                .fill(step.isComplete ? Color.green : Color.gray.opacity(0.3))
                                .frame(width: 2, height: 40)
                        }
                    }

                    // Step content
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(step.levelLabel)
                                .font(.subheadline)
                                .fontWeight(step.isCurrent ? .bold : .regular)
                            if step.isCurrent {
                                Text("Current")
                                    .font(.caption2)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1)
                                    .background(.blue)
                                    .clipShape(Capsule())
                            }
                        }
                        if let reviewer = step.reviewedBy, let date = step.reviewedAt {
                            Text("\(reviewer) — \(date, style: .relative)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let notes = step.notes {
                            Text(notes)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .italic()
                        }
                    }
                }
            }

            // Action buttons
            if canEscalate || canPushBack {
                HStack(spacing: 12) {
                    if canEscalate {
                        Button {
                            onEscalate()
                        } label: {
                            Label("Escalate", systemImage: "arrow.up.circle")
                                .font(.caption)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    if canPushBack {
                        Button {
                            onPushBack()
                        } label: {
                            Label("Push Back", systemImage: "arrow.down.circle")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .tint(.orange)
                    }
                }
                .padding(.top, 8)
            }
        }
    }
}
```

### Step 2: Service Methods

```swift
// In ChatService:

/// Get escalation history for a Q&A thread
func getEscalationHistory(channelId: Int64) async throws -> [EscalationStep]

/// Escalate Q&A thread to next level
func escalateThread(channelId: Int64, escalatedBy: Int64, notes: String?) async throws

/// Push Q&A thread back down one level with feedback
func pushBackThread(channelId: Int64, pushedBackBy: Int64, reason: String) async throws
```

### Step 3: Update IOSQuestionsPage.swift

**Replace capsule chips with smart cards:**

```swift
// BEFORE: capsule chip bar
// AFTER: smart cards
@State private var statusFilter: QAFilter = .all

enum QAFilter: String, CaseIterable {
    case all = "All"
    case open = "Open"
    case myQuestions = "My Questions"
    case needsMyReview = "Needs My Review"
    case resolved = "Resolved"
}

ScrollView(.horizontal, showsIndicators: false) {
    HStack(spacing: 10) {
        ForEach(QAFilter.allCases, id: \.self) { filter in
            SmartCard(
                title: filter.rawValue,
                count: countFor(filter),
                isActive: statusFilter == filter
            ) {
                statusFilter = filter
            }
        }
    }
    .padding(.horizontal)
}
```

**Fix silent guard returns:**

```swift
// BEFORE:
guard let service = appCore.chatService else { return }

// AFTER:
guard let service = appCore.chatService else {
    loadError = "Chat service unavailable"
    isLoading = false
    return
}
```

**Add escalation timeline to question detail:**

When tapping a Q&A question, the thread view (from 42B) shows the escalation timeline in the info panel.

### Step 4: Update IOSRFIListPage.swift

Apply the same fixes:
- Replace capsule chips with smart cards (All, Open, Pending Response, Closed)
- Fix silent guard returns
- Add escalation display for RFI threads

### Step 5: Thread History with Timestamps

In the escalation timeline, each step shows:
- WHO reviewed (name)
- WHEN (relative date: "2 hours ago")
- WHAT they said (notes/feedback from push-back)

## Important Notes
- The escalation ladder is bidirectional: up (escalate) AND down (push back)
- "Push Back" requires a reason/feedback message (shown as notes on the timeline)
- "Needs My Review" filter shows questions at the user's escalation level
- Workers see their own questions + questions they can answer
- Leads/Managers see questions at their level awaiting review
- The escalation timeline is reusable — it should work in both the thread info panel (42B) and as a standalone component

## Success Criteria
- [ ] IOSEscalationTimeline component created
- [ ] Bidirectional flow: Worker ⇄ Lead ⇄ Manager ⇄ Office
- [ ] Each level shows reviewer name and timestamp
- [ ] Push back shows reason/feedback notes
- [ ] IOSQuestionsPage: smart cards replace capsule chips
- [ ] IOSQuestionsPage: silent guard returns fixed
- [ ] IOSRFIListPage: smart cards replace capsule chips
- [ ] IOSRFIListPage: silent guard returns fixed
- [ ] 3+ service methods for escalation
- [ ] Project builds with no errors

## Log Entry
```
## Prompt 42D Results (YYYY-MM-DD)
- Created IOSEscalationTimeline.swift
- ChatService: getEscalationHistory, escalateThread, pushBackThread
- IOSQuestionsPage: smart cards, guard fixes
- IOSRFIListPage: smart cards, guard fixes
- Build: PASS/FAIL
```

**Wait for user confirmation before proceeding.**

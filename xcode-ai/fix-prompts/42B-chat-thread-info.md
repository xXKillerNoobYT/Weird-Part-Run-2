# 42B — Chat Thread Info Panel

> **Chain position:** 42A → **42B** → 42C → 42D
> **Prerequisite:** 42A (unified inbox)
> **Log file:** `xcode-ai/prompt-results-log.md`

## MANDATORY RULES
1. DO NOT use `import GRDB` in UI files
2. DO NOT use empty `catch { }` blocks
3. DO NOT use `#if os(iOS)` guards

## Instructions

**IMPORTANT:** Before implementing, read `IOSMessageThreadView.swift` to understand the current thread layout. Then add an iMessage-style inline expandable info panel that shows thread context, people, and quick actions.

## Context

When viewing a message thread, users need context: where did this conversation come from (a JPO? a job? a supplier?), who's involved, and what actions can they take (approve, reject, escalate, push back). Instead of a separate detail page, an expandable panel inside the thread view keeps everything in context — tap the header to expand, tap again to collapse.

## Task

### Step 1: Add Thread Info Data Model

```swift
struct ThreadInfo: Sendable {
    let channelType: String
    let channelName: String

    // Source context
    let sourceType: String?  // "jpo", "po", "job", "supplier", nil for general
    let sourceId: Int64?
    let sourceName: String?

    // Escalation (for Q&A/RFI)
    let escalationLevel: String?  // "worker", "lead", "manager", "office"
    let canEscalate: Bool
    let canPushBack: Bool

    // People
    let members: [ChannelMember]

    // Quick actions based on type
    let availableActions: [ThreadAction]
}

enum ThreadAction: Identifiable {
    case approve
    case reject
    case escalate
    case pushBack
    case markResolved
    case addPeople

    var id: String { "\(self)" }
}
```

### Step 2: Service Method

```swift
// In ChatService:
func getThreadInfo(channelId: Int64) async throws -> ThreadInfo {
    // Join channel with its source (job, JPO, PO, supplier)
    // Get channel members
    // Determine available actions based on channel type and user permissions
}
```

### Step 3: Inline Expandable Panel in IOSMessageThreadView

```swift
@State private var showInfoPanel = false
@State private var threadInfo: ThreadInfo?

// Thread header — tappable to expand
VStack(spacing: 0) {
    // Header bar
    Button {
        withAnimation(.easeInOut(duration: 0.25)) {
            showInfoPanel.toggle()
        }
    } label: {
        HStack {
            Text(channelName).font(.headline)
            Spacer()
            Image(systemName: showInfoPanel ? "chevron.up" : "info.circle")
                .foregroundStyle(.blue)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
    .buttonStyle(.plain)

    // Expandable info panel
    if showInfoPanel, let info = threadInfo {
        ThreadInfoPanel(info: info, onAction: handleAction)
            .transition(.move(edge: .top).combined(with: .opacity))
    }

    Divider()
}
```

### Step 4: ThreadInfoPanel View

```swift
struct ThreadInfoPanel: View {
    let info: ThreadInfo
    let onAction: (ThreadAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Source Context
            if let sourceName = info.sourceName, let sourceType = info.sourceType {
                HStack {
                    Image(systemName: sourceIcon(sourceType))
                        .foregroundStyle(.blue)
                    VStack(alignment: .leading) {
                        Text(sourceLabel(sourceType)).font(.caption).foregroundStyle(.secondary)
                        Text(sourceName).font(.subheadline)
                    }
                }
                .padding(.horizontal)
            }

            // Escalation Ladder (Q&A/RFI only)
            if let level = info.escalationLevel {
                EscalationLadder(
                    currentLevel: level,
                    canEscalate: info.canEscalate,
                    canPushBack: info.canPushBack
                )
                .padding(.horizontal)
            }

            // People
            VStack(alignment: .leading, spacing: 4) {
                Text("People (\(info.members.count))")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal)
                ForEach(info.members) { member in
                    HStack {
                        Text(member.name).font(.subheadline)
                        Spacer()
                        Text(member.role ?? "Member")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                }
            }

            // Quick Actions
            if !info.availableActions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(info.availableActions) { action in
                            Button {
                                onAction(action)
                            } label: {
                                Label(actionLabel(action), systemImage: actionIcon(action))
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .tint(actionColor(action))
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    func sourceIcon(_ type: String) -> String {
        switch type {
        case "jpo": return "doc.plaintext"
        case "po": return "shippingbox"
        case "job": return "wrench.and.screwdriver"
        case "supplier": return "building.2"
        default: return "bubble.left"
        }
    }

    func sourceLabel(_ type: String) -> String {
        switch type {
        case "jpo": return "Job Parts Order"
        case "po": return "Purchase Order"
        case "job": return "Job"
        case "supplier": return "Supplier"
        default: return "Source"
        }
    }
}
```

### Step 5: Different Layouts by Thread Type

The panel should adapt based on channel type:
- **DM:** Show people only, no escalation, action = Add People
- **Job:** Show job source, people, actions = Mark Resolved, Add People
- **Supplier:** Show supplier + PO source, people, no escalation
- **Q&A:** Show escalation ladder (bidirectional), people, actions = Escalate, Push Back, Mark Resolved
- **RFI:** Same as Q&A

### Step 6: Load Thread Info on Appear

```swift
.task {
    do {
        threadInfo = try await chatService.getThreadInfo(channelId: channelId)
    } catch {
        // Non-fatal — panel just won't show content
    }
}
```

## Important Notes
- The panel is INSIDE the thread view (not a sheet or popover) — it pushes messages down
- Animation should be smooth (0.25s ease-in-out)
- Collapsed state shows just the info.circle icon as a hint
- Quick actions trigger confirmation where appropriate (escalate, reject)
- The panel uses `.ultraThinMaterial` background to visually separate from messages
- Thread info loads once on appear — not on every expand/collapse

## Success Criteria
- [ ] Tapping thread header toggles inline info panel
- [ ] Panel shows source context (JPO, Job, Supplier, etc.)
- [ ] Panel shows escalation ladder for Q&A/RFI threads
- [ ] Panel shows people list with roles
- [ ] Quick action buttons based on thread type
- [ ] Smooth expand/collapse animation
- [ ] Different layouts for DM/Job/Supplier/Q&A thread types
- [ ] Project builds with no errors

## Log Entry
```
## Prompt 42B Results (YYYY-MM-DD)
- ThreadInfoPanel component created
- ChatService.getThreadInfo added
- 5 thread type layouts (DM, Job, Supplier, Q&A, RFI)
- Build: PASS/FAIL
```

**Wait for user confirmation before proceeding to prompt 42C.**

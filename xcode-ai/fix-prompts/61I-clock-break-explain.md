# 61I — Explain Why Clock Out Is Disabled During Break

> **Chain position:** **61I** (standalone)
> **Issue:** T2-11
> **Log file:** `xcode-ai/prompt-results-log.md`

## MANDATORY RULES
1. DO NOT change the break/clock business logic — only add UI explanation
2. The explanation must be visible WITHOUT any user interaction (not hidden in a tooltip)
3. Choose ONE approach: either explanation text OR auto-end break on clock out
4. Project must build with zero errors when done

## Context

When a worker is on break, the Clock Out button is disabled. But there's no explanation of WHY it's disabled. Users tap it, nothing happens, and they don't understand what to do. They need to end their break first before clocking out.

## File to Modify

`Weird Parts IOS/Weird Parts IOS/Features/Jobs/IOSClockPage.swift`

## Task

### Approach: Show Explanation Text

Find the Clock Out button. It likely looks like:
```swift
Button("Clock Out") {
    // clock out action
}
.disabled(isOnBreak)
```

Add explanation text below the button when it's disabled:

```swift
Button("Clock Out") {
    // clock out action
}
.disabled(isOnBreak)

if isOnBreak {
    HStack(spacing: 6) {
        Image(systemName: "info.circle")
            .foregroundColor(.orange)
        Text("End your break first to clock out")
            .font(.subheadline)
            .foregroundColor(.orange)
    }
    .padding(.top, 4)
}
```

### Also: Style the Disabled Button Clearly

Make sure the disabled state is visually obvious:
```swift
Button("Clock Out") {
    // clock out action
}
.disabled(isOnBreak)
.opacity(isOnBreak ? 0.4 : 1.0)
```

### Find the Break State Variable

Search `IOSClockPage.swift` for:
- `isOnBreak` or `onBreak` — a boolean state
- `breakStartTime` — if non-nil, user is on break
- `activeBreak` — a break object
- `clockEntry.breakStart` — break tracking on the clock entry

Whatever the variable name is, use it for the `if` condition.

### Also: Highlight the "End Break" Button

If there's an "End Break" button on the same page, make it more prominent when it's the required next action:

```swift
if isOnBreak {
    Button("End Break") {
        // end break action
    }
    .buttonStyle(.borderedProminent)
    .tint(.orange)
}
```

## Success Criteria

- [ ] When on break, text "End your break first to clock out" appears below Clock Out button
- [ ] Clock Out button is visually dimmed when disabled (opacity 0.4)
- [ ] End Break button is prominent (borderedProminent, orange tint) during active break
- [ ] Info icon + text are orange to draw attention
- [ ] No business logic changes — break must still be ended before clock out
- [ ] Project builds with zero errors

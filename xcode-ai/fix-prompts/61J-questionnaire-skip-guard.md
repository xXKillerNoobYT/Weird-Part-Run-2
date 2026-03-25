# 61J — Guard Questionnaire Skip Button Against Required Questions

> **Chain position:** **61J** (standalone)
> **Issue:** T2-12
> **Log file:** `xcode-ai/prompt-results-log.md`

## MANDATORY RULES
1. DO NOT remove the skip functionality entirely — it's valid when all questions are optional
2. DO NOT change question data models — only change UI behavior
3. Required questions must be answered before proceeding, period
4. Project must build with zero errors when done

## Context

The clock-out questionnaire has a "Skip" button that lets workers bypass ALL questions, including required ones. If a question is marked as required (e.g., "Did you clean up your work area?"), the Skip button should NOT be available. This is a data integrity issue — required questions exist for a reason.

## File to Modify

`Weird Parts IOS/Weird Parts IOS/Features/Jobs/IOSQuestionnairePage.swift`

## Task

### 1. Find the Skip Button

Search for "Skip" in the file. It's likely a toolbar button or a footer button:
```swift
Button("Skip") {
    // Dismiss or skip to next step
    dismiss()
}
```

### 2. Determine If Questions Have a "Required" Flag

Search the file and related models for:
- `isRequired` property on question models
- `required` field
- `optional` field (inverse)
- Any boolean that marks a question as mandatory

If the question model has NO required flag, add one:
```swift
struct QuestionnaireQuestion {
    // existing fields...
    var isRequired: Bool = false  // ADD THIS
}
```

### 3. Hide Skip When Required Questions Exist

```swift
// Compute whether any required questions are unanswered
var hasUnansweredRequired: Bool {
    questions.filter { $0.isRequired }.contains { question in
        let answer = answers[question.id]
        return answer == nil || answer?.isEmpty == true
    }
}

// In the view:
if !hasUnansweredRequired {
    Button("Skip") {
        dismiss()
    }
}
```

### 4. Alternative: Rename to "Submit Without Optional Answers"

If ALL questions have answers for the required ones but some optional ones are blank:

```swift
if hasUnansweredRequired {
    // No skip button at all — must answer required questions
} else if hasUnansweredOptional {
    Button("Submit Without Optional Answers") {
        showConfirmation = true
    }
    .confirmationDialog("Skip Optional Questions?", isPresented: $showConfirmation) {
        Button("Submit Anyway") {
            submitAnswers()
            dismiss()
        }
        Button("Go Back", role: .cancel) { }
    } message: {
        Text("You have \(unansweredOptionalCount) optional questions unanswered. Submit anyway?")
    }
} else {
    // All questions answered — show Submit
    Button("Submit") {
        submitAnswers()
        dismiss()
    }
}
```

### 5. Mark Required Questions Visually

Add a red asterisk to required question labels:
```swift
HStack(spacing: 2) {
    Text(question.text)
    if question.isRequired {
        Text("*")
            .foregroundColor(.red)
            .fontWeight(.bold)
    }
}
```

### 6. Show Validation Error

If the user somehow tries to proceed with unanswered required questions (e.g., via a Submit button), show inline validation:

```swift
if question.isRequired && (answers[question.id] == nil || answers[question.id]?.isEmpty == true) {
    Text("This question is required")
        .font(.caption)
        .foregroundColor(.red)
}
```

## Success Criteria

- [ ] Skip button hidden when any required questions are unanswered
- [ ] Skip button visible when all questions are optional (or all required ones answered)
- [ ] Required questions marked with red asterisk (*)
- [ ] Validation error shown for unanswered required questions
- [ ] "Submit Without Optional Answers" option available when only optional questions remain
- [ ] Project builds with zero errors

# Fix Prompt 08: Missing CRUD — Scheduling & Chat

> **BEFORE DOING ANYTHING:** Read `xcode-ai/xcode.md` and follow every instruction in it.

---

## The Problem (User Perspective)

An employee submits a time-off request but the manager has no way to approve or deny it — the page is read-only. In Chat, users see channel listings but can't create a new channel or start a DM. The Q&A question form exists in code but there's no button to open it.

---

## Files To Fix

### 1. IOSTimeOffPage.swift — Add Approve/Deny for Managers

The page lists time-off requests but managers can't act on them. Add action buttons for users with the right permissions:

```swift
// On each pending request row, if user is manager/admin:
if appCore.hasPermission("manage_scheduling") && request.status == "pending" {
    HStack(spacing: 12) {
        Button {
            denyTimeOff(requestId: request.id)
        } label: {
            Label("Deny", systemImage: "xmark")
        }
        .buttonStyle(.bordered)
        .tint(.red)

        Button {
            approveTimeOff(requestId: request.id)
        } label: {
            Label("Approve", systemImage: "checkmark")
        }
        .buttonStyle(.borderedProminent)
    }
}
```

Also add a "Request Time Off" button for the current user:
```swift
.toolbar {
    ToolbarItem(placement: .primaryAction) {
        Button { showRequestForm = true } label: { Image(systemName: "plus") }
    }
}
```

### 2. IOSDispatchPage.swift — Add "Create Dispatch" Button

Users need to assign employees to jobs for specific dates. Add a create button and form.

### 3. IOSScheduleCalendarPage.swift — Add Event Creation

If the calendar only displays events, add a way to create new schedule entries by tapping a date.

### 4. IOSChannelsPage.swift — Add "New Channel" and "New DM" Buttons

```swift
.toolbar {
    ToolbarItem(placement: .primaryAction) {
        Menu {
            Button {
                showCreateChannel = true
            } label: {
                Label("New Channel", systemImage: "number")
            }
            Button {
                showNewDM = true
            } label: {
                Label("New Message", systemImage: "envelope")
            }
        } label: {
            Image(systemName: "plus")
        }
    }
}
```

Create a `CreateChannelSheet` with fields: Channel Name, Description, Members picker.

### 5. IOSQuestionsPage.swift — Add "Ask Question" Button

The Q&A section lists questions but there's no button to ask a new one. `IOSQAQuestionForm.swift` exists but isn't reachable. Add:

```swift
.toolbar {
    ToolbarItem(placement: .primaryAction) {
        Button { showAskQuestion = true } label: {
            Label("Ask", systemImage: "plus")
        }
    }
}
.sheet(isPresented: $showAskQuestion) {
    IOSQAQuestionForm(onSubmit: { loadData() })
}
```

### 6. IOSRFIListPage.swift — Add "Create RFI" Button

Same pattern — add toolbar button and creation form.

### 7. IOSNotebooksListPage.swift — Add "Create Notebook" Button

```swift
.toolbar {
    ToolbarItem(placement: .primaryAction) {
        Button { showCreateNotebook = true } label: { Image(systemName: "plus") }
    }
}
```

### 8. IOSNotebookDetailPage.swift — Add "Add Entry" Button and Fix Tasks Tab

The notebook detail shows sections but there's no "Add Entry" or "Add Task" button. Add:

```swift
// Floating action button or toolbar button
Button {
    showAddEntry = true
} label: {
    Label("Add Entry", systemImage: "plus")
}
```

Fix the Tasks tab placeholder (already addressed in prompt 04, but make sure the add button is also present).

### 9. IOSNotebookTemplatesPage.swift — Add "Create Template" Button

Same pattern — toolbar + button + form.

---

## Testing Checklist

1. Scheduling → Time Off → pending request → manager sees Approve/Deny buttons
2. Scheduling → Time Off → "+" button → can submit a new request
3. Chat → Channels → "+" menu → can create new channel
4. Chat → Q&A → "Ask" button → opens IOSQAQuestionForm → can submit
5. Notebooks → list → "+" → can create notebook
6. Notebook detail → "Add Entry" → can add text entry or task

---

## When Done

Start **prompt 09 (Security Hardening)** next.

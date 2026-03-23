# 42C — Chat Attachments + References

> **Chain position:** 42A → 42B → **42C** → 42D
> **Prerequisite:** 42B (thread info panel)
> **Log file:** `xcode-ai/prompt-results-log.md`

## MANDATORY RULES
1. DO NOT use `import GRDB` in UI files
2. DO NOT use empty `catch { }` blocks
3. DO NOT use `#if os(iOS)` guards

## Instructions

**IMPORTANT:** Before implementing, read `IOSMessageThreadView.swift` and `ChatService.swift`. Add attachment support (photos, files, part/PO/job references) to the message composer and display.

## Context

Chat is more useful when workers can share photos (job site pics), reference specific parts ("I need this part — [Part #1234]"), and link to orders or jobs. Attachments should auto-save to the job's notebook when the channel is job-linked. When a user is clocked into a job, job context should auto-fill when creating messages or other job-related actions (this is a program-wide rule).

## Task

### Step 1: Migration — Message Attachments

```swift
// In AppDatabase+Migrations.swift
try db.create(table: "message_attachments") { t in
    t.autoIncrementedPrimaryKey("id")
    t.column("message_id", .integer).notNull()
        .references("messages", onDelete: .cascade)
    t.column("attachment_type", .text).notNull()  // "photo", "file", "part_ref", "po_ref", "job_ref", "jpo_ref"
    t.column("file_path", .text)       // local file path for photos/files
    t.column("file_name", .text)       // display name
    t.column("file_size", .integer)    // bytes
    t.column("mime_type", .text)       // "image/jpeg", "application/pdf", etc.
    t.column("reference_id", .integer) // ID of the referenced entity (part, PO, job, JPO)
    t.column("reference_label", .text) // Display label for the reference
    t.column("created_at", .text).defaults(sql: "datetime('now')")
}
```

### Step 2: Service Methods in ChatService

```swift
// MARK: - Attachments

struct MessageAttachment: Identifiable, Codable, Sendable {
    let id: Int64
    let messageId: Int64
    let attachmentType: String
    let filePath: String?
    let fileName: String?
    let fileSize: Int64?
    let mimeType: String?
    let referenceId: Int64?
    let referenceLabel: String?
}

/// Send message with attachments
func sendMessageWithAttachments(
    channelId: Int64,
    content: String,
    userId: Int64,
    attachments: [PendingAttachment]
) async throws -> Message

/// Get attachments for a message
func getMessageAttachments(messageId: Int64) async throws -> [MessageAttachment]

/// Auto-save photo attachments to job notebook
func autoSaveToJobNotebook(channelId: Int64, attachment: MessageAttachment) async throws

struct PendingAttachment {
    let type: String  // "photo", "file", "part_ref", "po_ref", "job_ref"
    let filePath: String?
    let referenceId: Int64?
    let referenceLabel: String?
}
```

### Step 3: Composer Attachment Buttons

Add attachment buttons to the message composer in `IOSMessageThreadView.swift`:

```swift
// Attachment bar above the text field
@State private var pendingAttachments: [PendingAttachment] = []
@State private var showPhotoPicker = false
@State private var showPartPicker = false
@State private var showReferencePicker = false

HStack(spacing: 16) {
    // Photo button
    Button { showPhotoPicker = true } label: {
        Image(systemName: "photo")
    }

    // File button
    Button { showFilePicker = true } label: {
        Image(systemName: "doc")
    }

    // Reference button (part/PO/job)
    Menu {
        Button { showPartPicker = true } label: {
            Label("Part Reference", systemImage: "shippingbox")
        }
        Button { showPOPicker = true } label: {
            Label("PO Reference", systemImage: "doc.text")
        }
        Button { showJobPicker = true } label: {
            Label("Job Reference", systemImage: "wrench.and.screwdriver")
        }
    } label: {
        Image(systemName: "link")
    }
}

// Pending attachments preview
if !pendingAttachments.isEmpty {
    ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
            ForEach(pendingAttachments.indices, id: \.self) { idx in
                AttachmentChip(attachment: pendingAttachments[idx]) {
                    pendingAttachments.remove(at: idx)
                }
            }
        }
    }
}
```

### Step 4: Part Reference Display (Tappable Links)

In message bubbles, render part references as tappable links:

```swift
// In the message bubble view
ForEach(messageAttachments) { attachment in
    switch attachment.attachmentType {
    case "part_ref":
        Button {
            // Navigate to part detail
            navigateToPartDetail(partId: attachment.referenceId!)
        } label: {
            HStack {
                Image(systemName: "shippingbox.fill")
                    .foregroundStyle(.blue)
                Text(attachment.referenceLabel ?? "Part")
                    .foregroundStyle(.blue)
                    .underline()
            }
            .font(.caption)
            .padding(6)
            .background(.blue.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }

    case "photo":
        // Thumbnail image
        if let path = attachment.filePath {
            AsyncImage(url: URL(fileURLWithPath: path)) { image in
                image.resizable().aspectRatio(contentMode: .fill)
                    .frame(maxWidth: 200, maxHeight: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } placeholder: {
                ProgressView()
            }
        }

    case "po_ref", "job_ref", "jpo_ref":
        // Reference chip
        HStack {
            Image(systemName: iconForRefType(attachment.attachmentType))
                .foregroundStyle(.orange)
            Text(attachment.referenceLabel ?? "Reference")
                .font(.caption)
        }
        .padding(6)
        .background(.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 6))

    default:
        // File attachment
        HStack {
            Image(systemName: "doc")
            Text(attachment.fileName ?? "File")
                .font(.caption)
        }
    }
}
```

### Step 5: Auto-Fill Job Context When Clocked In

This is a program-wide rule: when the user is clocked into a job, auto-fill job context for actions. For chat:

```swift
// When composing in a general channel while clocked in,
// show a banner: "You're working on [Job Name]"
if let currentClockEntry = appCore.currentClockEntry,
   let jobName = currentClockEntry.jobName {
    HStack {
        Image(systemName: "clock.fill").foregroundStyle(.green)
        Text("Working on \(jobName)")
            .font(.caption)
        Spacer()
    }
    .padding(.horizontal)
    .padding(.vertical, 4)
    .background(.green.opacity(0.1))
}
```

### Step 6: Auto-Save to Job Notebook

When a photo or file is sent in a job-linked channel, auto-save it to the job's notebook:

```swift
// After sending message with attachments:
if let jobId = channel.jobId {
    for attachment in photoAndFileAttachments {
        try? await chatService.autoSaveToJobNotebook(channelId: channelId, attachment: attachment)
    }
}
```

### Step 7: Update ConflictResolver

Add `message_attachments` to the whitelist.

## Important Notes
- Photo picker uses `PhotosUI.PhotosPicker` for iOS
- File picker uses `.fileImporter` modifier
- Part picker should be a searchable list sheet (reuse catalog search if possible)
- References are NOT file attachments — they're links to entities in the database
- Auto-save to notebook is best-effort (try? — don't fail the message send)
- Job context auto-fill is a pattern for the WHOLE app, not just chat

## Success Criteria
- [ ] Migration creates message_attachments table
- [ ] Photo/file/reference attachment buttons in composer
- [ ] Pending attachments preview before sending
- [ ] Part references render as tappable blue links in bubbles
- [ ] PO/Job references render as labeled chips
- [ ] Photos render as thumbnails in bubbles
- [ ] Auto-save photos/files to job notebook
- [ ] Job context banner when clocked in
- [ ] ConflictResolver updated
- [ ] Project builds with no errors

## Log Entry
```
## Prompt 42C Results (YYYY-MM-DD)
- Migration: message_attachments table
- Composer: 3 attachment buttons (photo, file, reference)
- Bubbles: tappable part links, photo thumbnails, reference chips
- Auto-save to job notebook
- Build: PASS/FAIL
```

**Wait for user confirmation before proceeding to prompt 42D.**

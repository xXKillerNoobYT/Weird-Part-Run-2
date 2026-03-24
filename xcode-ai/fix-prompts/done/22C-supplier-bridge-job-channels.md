# 22C — Supplier Bridge: Job-Linked Channels + RFI Integration

> **Chain position:** 22A → 22B → **22C**
> **Prerequisite:** 22B complete (supplier channel UI exists)
> **Log file:** `xcode-ai/prompt-results-log.md`

## Instructions

**IMPORTANT:** Before implementing, first plan your approach by reading all files mentioned below. Understand the current state, then implement the fixes. When done, wait for the user to confirm before proceeding to the next prompt.

## Context

Supplier channels need to work with the existing job chat system. When a team is on a job and needs to communicate with a supplier about that job's materials, the channel should link to both the job and the supplier. The RFI (Request for Information) system also needs a supplier path — currently RFIs only link to GC contacts.

**Existing infrastructure:**
- `chat_channels.job_id` — optional FK to jobs (used for job channels)
- `qa_threads.job_id` — required FK to jobs
- `rfi_objects.gc_contact_id` — FK to contacts (GC only currently)
- `supplier_channel_bridges` — from 22A

**Files to modify:**
- `core/Sources/WiredPartCore/Services/ChatService.swift` — job-linked supplier channels
- `Weird Parts IOS/Weird Parts IOS/Features/Chat/IOSChannelsPage.swift` — show job context on supplier channels
- `Weird Parts IOS/Weird Parts IOS/Features/Chat/IOSRFIListPage.swift` — supplier RFI support
- `Weird Parts IOS/Weird Parts IOS/Features/Jobs/IOSJobDetailTabView.swift` — add supplier channel access from job

## Task

### Step 1: Add job-linked supplier channel creation

Update `ChatService.createSupplierChannel()` to accept an optional `jobId`:

```swift
/// Create a supplier channel optionally linked to a job.
public func createSupplierChannel(
    name: String,
    supplierId: Int64,
    supplierDisplayName: String,
    contactId: Int64?,
    role: String?,
    createdBy: Int64,
    jobId: Int64? = nil  // NEW: optional job link
) throws -> Int64 {
    try db.writer.write { dbConn in
        // Create channel with type "supplier" and optional job link
        try dbConn.execute(sql: """
            INSERT INTO chat_channels (channel_type, job_id, name, created_by, is_active, created_at)
            VALUES ('supplier', ?, ?, ?, 1, datetime('now'))
            """, arguments: [jobId, name, createdBy])
        let channelId = dbConn.lastInsertedRowID

        // Add creator as admin member
        try dbConn.execute(sql: """
            INSERT INTO chat_channel_members (channel_id, user_id, role, joined_at)
            VALUES (?, ?, 'admin', datetime('now'))
            """, arguments: [channelId, createdBy])

        // Create bridge
        let token = UUID().uuidString
        try dbConn.execute(sql: """
            INSERT INTO supplier_channel_bridges
            (channel_id, supplier_id, contact_id, display_name, role, invite_token, is_active, created_at)
            VALUES (?, ?, ?, ?, ?, ?, 1, datetime('now'))
            """, arguments: [channelId, supplierId, contactId, supplierDisplayName, role, token])

        return channelId
    }
}
```

### Step 2: Add supplier channel section to job detail

In `IOSJobDetailTabView.swift`, add a section showing supplier channels linked to this job:

```swift
// In the job detail tabs or info section:
Section("Supplier Channels") {
    if jobSupplierChannels.isEmpty {
        Button {
            showCreateSupplierChannel = true
        } label: {
            Label("Add Supplier Channel", systemImage: "plus.bubble")
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 44)
        }
    } else {
        ForEach(jobSupplierChannels, id: \.channelId) { channel in
            Button {
                // Navigate to channel
                NotificationCenter.default.post(
                    name: .init("navigateToChannel"),
                    object: nil,
                    userInfo: ["channelId": channel.channelId]
                )
            } label: {
                HStack {
                    Image(systemName: "building.2")
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(channel.supplierName)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        if let role = channel.role {
                            Text(role)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if channel.unreadCount > 0 {
                        Text("\(channel.unreadCount)")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red)
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                }
                .frame(minHeight: 44)
            }
        }

        Button {
            showCreateSupplierChannel = true
        } label: {
            Label("Add Another", systemImage: "plus.circle")
                .font(.subheadline)
        }
    }
}

@State private var jobSupplierChannels: [ChatService.SupplierChannelRow] = []
@State private var showCreateSupplierChannel = false
```

Load job supplier channels:

```swift
// In loadData or .task:
if let chatService = appCore.chatService, let userId = appCore.currentUserId {
    let allChannels = try chatService.listSupplierChannels(userId: userId)
    jobSupplierChannels = allChannels.filter { channel in
        // Filter to channels linked to this job
        // Need a way to check job_id on the channel
        // Add a getChannelJobId helper or include it in SupplierChannelRow
        true // placeholder — implement job filtering
    }
}
```

**Note:** You may need to add `jobId` to `SupplierChannelRow` or create a method like `listSupplierChannelsForJob(jobId:, userId:)`:

```swift
/// List supplier channels linked to a specific job.
public func listSupplierChannelsForJob(jobId: Int64, userId: Int64) throws -> [SupplierChannelRow] {
    try db.writer.read { dbConn in
        let rows = try Row.fetchAll(dbConn, sql: """
            SELECT cc.id AS channel_id, cc.name AS channel_name,
                   s.name AS supplier_name, scb.supplier_id,
                   scb.display_name, scb.role,
                   (SELECT MAX(created_at) FROM chat_messages WHERE channel_id = cc.id AND deleted_at IS NULL) AS last_message_at,
                   (SELECT COUNT(*) FROM chat_messages cm
                    WHERE cm.channel_id = cc.id AND cm.deleted_at IS NULL
                    AND cm.created_at > COALESCE(
                        (SELECT read_at FROM chat_read_receipts WHERE channel_id = cc.id AND user_id = ?), '1970-01-01'
                    )) AS unread_count
            FROM chat_channels cc
            JOIN supplier_channel_bridges scb ON scb.channel_id = cc.id AND scb.deleted_at IS NULL
            JOIN suppliers s ON s.id = scb.supplier_id AND s.deleted_at IS NULL
            WHERE cc.channel_type = 'supplier' AND cc.job_id = ? AND cc.deleted_at IS NULL
            ORDER BY last_message_at DESC NULLS LAST
            """, arguments: [userId, jobId])

        return rows.map { row in
            SupplierChannelRow(
                channelId: row["channel_id"],
                channelName: row["channel_name"] ?? "",
                supplierName: row["supplier_name"] ?? "",
                supplierId: row["supplier_id"],
                bridgeDisplayName: row["display_name"] ?? "",
                role: row["role"],
                lastMessageAt: row["last_message_at"],
                unreadCount: row["unread_count"] ?? 0
            )
        }
    }
}
```

### Step 3: Show job name on supplier channels in channels list

In `IOSChannelsPage.swift`, when a supplier channel has a `job_id`, show the job name as a subtitle:

```swift
// In the channel row view:
if channel.channelType == "supplier" {
    VStack(alignment: .leading, spacing: 2) {
        Text(channel.name)
            .font(.subheadline)
            .fontWeight(.medium)
        if let jobName = channel.jobName {
            Text("Job: \(jobName)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
```

This may require updating the `listChannels()` query to include job name via a LEFT JOIN.

### Step 4: Add supplier RFI path

Update `IOSRFIListPage.swift` to support supplier-directed RFIs alongside GC-directed RFIs. The `rfi_objects` table has `gc_contact_id` — we can repurpose the RFI flow for suppliers by also showing supplier bridge context.

```swift
// In the RFI list, add a filter or section for supplier RFIs:
// A supplier RFI = a qa_thread linked to a supplier channel

Section("Supplier Questions") {
    // Q&A threads that originated in supplier channels
    ForEach(supplierQuestions, id: \.id) { question in
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "building.2")
                    .foregroundStyle(.orange)
                Text(question.subject)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            HStack {
                Text(question.supplierName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(question.status.capitalized)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(statusColor(question.status).opacity(0.1))
                    .foregroundStyle(statusColor(question.status))
                    .clipShape(Capsule())
            }
        }
        .frame(minHeight: 44)
    }
}
```

Add a method to ChatService for supplier Q&A threads:

```swift
/// Create a Q&A thread linked to a supplier channel for RFI purposes.
public func createSupplierQuestion(
    channelId: Int64,
    jobId: Int64,
    askedBy: Int64,
    subject: String,
    priority: String = "normal"
) throws -> Int64 {
    try db.writer.write { dbConn in
        try dbConn.execute(sql: """
            INSERT INTO qa_threads (channel_id, job_id, asked_by, subject, priority, status, created_at)
            VALUES (?, ?, ?, ?, ?, 'open', datetime('now'))
            """, arguments: [channelId, jobId, askedBy, subject, priority])
        return dbConn.lastInsertedRowID
    }
}
```

## Important Notes

- Job-linked supplier channels are the primary use case: "We're on Job X and need to talk to Supplier Y about materials."
- The `chat_channels.job_id` column already exists and accepts nullable FKs — no migration needed.
- RFI for suppliers extends the existing Q&A → RFI escalation path. The same `qa_threads` table works; the supplier context comes from the channel being a supplier channel.
- The `navigateToChannel` notification is a placeholder — adapt to whatever navigation pattern the app uses (NavigationPath, router, etc.).
- If the job detail tab view doesn't have space for a full section, a simple "Message Supplier" button with a supplier picker is sufficient.
- Unread counts on supplier channels help users see when there are pending supplier communications.

## Success Criteria

- [ ] `createSupplierChannel()` accepts optional `jobId`
- [ ] `listSupplierChannelsForJob()` returns channels for a specific job
- [ ] Job detail page shows supplier channels with unread badges
- [ ] "Add Supplier Channel" button on job detail creates job-linked channel
- [ ] Channels list shows job name subtitle on job-linked supplier channels
- [ ] Supplier Q&A thread creation for RFI flow
- [ ] RFI page shows supplier questions section
- [ ] Project builds with no errors

## Log Entry

```
## Prompt 22C Results (YYYY-MM-DD)
- Job-linked supplier channels with listSupplierChannelsForJob()
- Supplier channel section on job detail with unread badges
- Job name shown on supplier channels in channel list
- Supplier Q&A thread for RFI integration
- Build: [PASS/FAIL]
```

**Supplier communication bridge complete. Continue with the next prompt chain.**

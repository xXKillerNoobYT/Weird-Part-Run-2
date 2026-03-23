# 45C — Job Types, Warranty, & Payment Hold

> **Chain position:** **45C** (standalone, feeds into 45D)
> **Log file:** `xcode-ai/prompt-results-log.md`

## MANDATORY RULES
1. DO NOT use `import GRDB` in UI files
2. DO NOT use empty `catch { }` blocks
3. DO NOT use `#if os(iOS)` guards

## Instructions

**IMPORTANT:** Before implementing, read `AppDatabase+Migrations.swift` and `JobsService.swift`. Add migration columns for warranty tracking, continuous jobs, and payment hold. Add service methods for these features.

## Context

Jobs need three new classification capabilities: (1) Warranty tracking with start/end dates and duration, (2) Continuous job flag for ongoing maintenance contracts, (3) Payment hold status with amount and date. The clock page must block clock-in for payment hold jobs.

## Task

### Step 1: Migration

```swift
// In AppDatabase+Migrations.swift — new migration

try db.alter(table: "jobs") { t in
    // Warranty fields
    t.add(column: "warranty_start", .text)
    t.add(column: "warranty_end", .text)
    t.add(column: "warranty_duration_days", .integer)

    // Job classification
    t.add(column: "job_classification", .text).defaults(to: "standard")
    // Values: "standard", "continuous", "service_call"

    // Payment hold
    t.add(column: "payment_hold_amount", .real)
    t.add(column: "payment_hold_date", .text)
    t.add(column: "payment_hold_reason", .text)

    // Continuous job fields
    t.add(column: "is_continuous", .boolean).defaults(to: false)
    t.add(column: "continuous_schedule", .text)  // JSON: days of week, frequency
}
```

### Step 2: Service Methods in JobsService

```swift
// MARK: - Warranty Tracking

/// Set warranty period for a job
func setWarranty(jobId: Int64, startDate: Date, durationDays: Int) async throws {
    let endDate = Calendar.current.date(byAdding: .day, value: durationDays, to: startDate)!
    try await db.write { db in
        try db.execute(sql: """
            UPDATE jobs SET
                warranty_start = :start,
                warranty_end = :end,
                warranty_duration_days = :days,
                status = 'warranty',
                updated_at = datetime('now')
            WHERE id = :jobId
        """, arguments: [
            "start": ISO8601DateFormatter().string(from: startDate),
            "end": ISO8601DateFormatter().string(from: endDate),
            "days": durationDays,
            "jobId": jobId
        ])
    }
}

/// Check if warranty is active
func isWarrantyActive(jobId: Int64) async throws -> Bool {
    try await db.read { db in
        let row = try Row.fetchOne(db, sql: """
            SELECT warranty_end FROM jobs WHERE id = :jobId
        """, arguments: ["jobId": jobId])
        guard let endStr = row?["warranty_end"] as? String,
              let endDate = ISO8601DateFormatter().date(from: endStr) else { return false }
        return endDate > Date()
    }
}

/// Get warranty days remaining
func warrantyDaysRemaining(jobId: Int64) async throws -> Int? {
    try await db.read { db in
        let row = try Row.fetchOne(db, sql: """
            SELECT warranty_end FROM jobs WHERE id = :jobId
        """, arguments: ["jobId": jobId])
        guard let endStr = row?["warranty_end"] as? String,
              let endDate = ISO8601DateFormatter().date(from: endStr) else { return nil }
        return Calendar.current.dateComponents([.day], from: Date(), to: endDate).day
    }
}

// MARK: - Payment Hold

/// Put job on payment hold
func setPaymentHold(jobId: Int64, amount: Double, reason: String?) async throws {
    try await db.write { db in
        try db.execute(sql: """
            UPDATE jobs SET
                status = 'payment_hold',
                payment_hold_amount = :amount,
                payment_hold_date = datetime('now'),
                payment_hold_reason = :reason,
                updated_at = datetime('now')
            WHERE id = :jobId
        """, arguments: ["amount": amount, "reason": reason, "jobId": jobId])
    }
}

/// Remove payment hold
func removePaymentHold(jobId: Int64) async throws {
    try await db.write { db in
        try db.execute(sql: """
            UPDATE jobs SET
                status = 'active',
                payment_hold_amount = NULL,
                payment_hold_date = NULL,
                payment_hold_reason = NULL,
                updated_at = datetime('now')
            WHERE id = :jobId
        """, arguments: ["jobId": jobId])
    }
}

/// Check if job is on payment hold (for clock blocking)
func isJobOnPaymentHold(jobId: Int64) async throws -> Bool

// MARK: - Continuous Jobs

/// Mark job as continuous
func setJobContinuous(jobId: Int64, schedule: ContinuousSchedule?) async throws

struct ContinuousSchedule: Codable, Sendable {
    let daysOfWeek: [Int]  // 1=Mon, 7=Sun
    let frequency: String  // "weekly", "biweekly", "monthly"
}

/// Get continuous jobs for current user
func getContinuousJobs(userId: Int64) async throws -> [Job]
```

### Step 3: Block Clock-In for Payment Hold Jobs

In `IOSClockPage.swift`:

```swift
// When user selects a job to clock into:
func attemptClockIn(jobId: Int64) async {
    do {
        // Check payment hold FIRST
        let isHeld = try await jobsService.isJobOnPaymentHold(jobId: jobId)
        if isHeld {
            actionError = "This job is on payment hold. Contact your manager."
            return
        }
        // Proceed with normal clock-in
        try await jobsService.clockIn(jobId: jobId, userId: currentUserId)
    } catch {
        actionError = error.localizedDescription
    }
}
```

### Step 4: Update ConflictResolver

The new columns are on the existing `jobs` table — no new tables to add, but verify the ConflictResolver handles the new fields properly.

## Important Notes
- Warranty status is a JOB STATUS (status = "warranty"), not a separate flag
- Warranty end date is auto-calculated from start + duration days
- Payment hold blocks clock-in for ALL workers (enforced at service level)
- Payment hold reason is only visible to managers (privacy)
- Continuous jobs have a schedule (which days, frequency) but may not always be scheduled
- job_classification is separate from status — a job can be "continuous" classification with "active" status
- Standard warranty durations: 30, 60, 90, 365 days (picker in UI)

## Success Criteria
- [ ] Migration adds warranty, classification, and payment hold columns to jobs
- [ ] Warranty service methods: set, check active, days remaining
- [ ] Payment hold: set, remove, check (for clock blocking)
- [ ] Continuous job: set, get for user
- [ ] Clock page blocks clock-in for payment hold jobs with error message
- [ ] All errors show in UI
- [ ] Project builds with no errors

## Log Entry
```
## Prompt 45C Results (YYYY-MM-DD)
- Migration: X new columns on jobs table
- Service: warranty, payment hold, continuous job methods
- Clock page: payment hold blocking
- Build: PASS/FAIL
```

**Wait for user confirmation before proceeding to prompt 45D.**

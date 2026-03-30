# 44F — Payment Tracking System

> **Chain position:** **44F** (requires 44C customer detail)
> **Prerequisite:** 44C (customer detail page with billing section)
> **Log file:** `xcode-ai/prompt-results-log.md`

## MANDATORY RULES
1. DO NOT use `import GRDB` in UI files
2. DO NOT use empty `catch { }` blocks
3. DO NOT use `#if os(iOS)` guards

## Instructions

**IMPORTANT:** Before implementing, read `IOSCustomerDetailPage.swift` (post-44C) and the Settings pages. Add a company-wide setting to enable/disable payment tracking, and when enabled, add payment status visualization and alerts.

## Context

Some construction companies track payments per customer; others don't want to deal with it. This is a company-wide toggle in Settings. When enabled: customer detail shows a green-to-red payment status bar, overdue invoices trigger alerts, and the People Dashboard shows payment-at-risk customers. When disabled: none of these features appear.

## Task

### Step 1: Migration — Payment Tracking

```sql
CREATE TABLE payment_records (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    customer_id INTEGER NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
    job_id INTEGER REFERENCES jobs(id),
    invoice_number TEXT,
    amount REAL NOT NULL,
    due_date TEXT NOT NULL,
    paid_date TEXT,
    paid_amount REAL,
    status TEXT NOT NULL DEFAULT 'pending',  -- 'pending', 'partial', 'paid', 'overdue'
    notes TEXT,
    created_by INTEGER REFERENCES users(id),
    created_at TEXT DEFAULT (datetime('now')),
    updated_at TEXT DEFAULT (datetime('now')),
    deleted_at TEXT
);

-- Settings for payment tracking
-- Add to settings table:
-- payment_tracking_enabled: 0/1 (default 0)
-- default_payment_terms_days: 30
-- overdue_warning_days: 7  (warn X days before due)
-- auto_payment_hold: 0/1  (auto-hold jobs when overdue)
```

### Step 2: Service Methods

```swift
// In PeopleService or a new PaymentService:

struct PaymentRecord: Identifiable, Codable, Sendable { /* ... */ }

struct PaymentStatus: Sendable {
    let totalInvoiced: Double
    let totalPaid: Double
    let totalOverdue: Double
    let oldestOverdueDays: Int?
    var paymentPercent: Double { totalPaid / max(totalInvoiced, 1) }
    var isOverdue: Bool { totalOverdue > 0 }
}

func isPaymentTrackingEnabled() async throws -> Bool
func setPaymentTrackingEnabled(_ enabled: Bool) async throws

func getCustomerPaymentStatus(customerId: Int64) async throws -> PaymentStatus
func getPaymentRecords(customerId: Int64) async throws -> [PaymentRecord]
func createPaymentRecord(customerId: Int64, jobId: Int64?, amount: Double, dueDate: Date, invoiceNumber: String?) async throws -> PaymentRecord
func recordPayment(recordId: Int64, amount: Double, paidDate: Date) async throws
func getOverdueCustomers() async throws -> [CustomerPaymentAlert]

struct CustomerPaymentAlert: Identifiable, Sendable {
    let id: Int64
    let customerName: String
    let overdueAmount: Double
    let overdueDays: Int
}
```

### Step 3: Payment Status Bar Component

```swift
struct PaymentStatusBar: View {
    let status: PaymentStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Payment Status")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(status.paymentPercent * 100))% paid")
                    .font(.caption).bold()
            }

            // Green-to-red gradient bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Background (full width)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(barColor.opacity(0.2))

                    // Filled portion
                    RoundedRectangle(cornerRadius: 4)
                        .fill(barColor)
                        .frame(width: geo.size.width * status.paymentPercent)
                }
            }
            .frame(height: 8)

            if status.isOverdue {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text("Overdue: \(formatCurrency(status.totalOverdue))")
                        .font(.caption).foregroundStyle(.red)
                    if let days = status.oldestOverdueDays {
                        Text("(\(days) days)")
                            .font(.caption2).foregroundStyle(.red)
                    }
                }
            }
        }
    }

    var barColor: Color {
        if status.paymentPercent >= 0.9 { return .green }
        if status.paymentPercent >= 0.5 { return .yellow }
        return .red
    }
}
```

### Step 4: Settings Page for Payment Tracking

Add a section in AppConfigPage or create a new settings section:

```swift
Section {
    Toggle("Enable Payment Tracking", isOn: $paymentTrackingEnabled)
        .onChange(of: paymentTrackingEnabled) { _, newValue in
            Task { try? await service.setPaymentTrackingEnabled(newValue) }
        }

    if paymentTrackingEnabled {
        Stepper("Payment Terms: \(paymentTermsDays) days", value: $paymentTermsDays, in: 7...120)
        Stepper("Overdue Warning: \(overdueWarningDays) days before", value: $overdueWarningDays, in: 1...30)
        Toggle("Auto Payment Hold", isOn: $autoPaymentHold)
    }
} header: {
    Text("Payment Tracking")
} footer: {
    Text("When enabled, track invoices and payments per customer. Shows payment status on customer detail pages.")
}
```

### Step 5: Wire into Customer Detail + People Dashboard

**Customer Detail (44C already has the section — activate it):**

```swift
// In the billing section of IOSCustomerDetailPage:
if paymentTrackingEnabled {
    PaymentStatusBar(status: paymentStatus)

    // Payment history
    ForEach(paymentRecords) { record in
        HStack {
            VStack(alignment: .leading) {
                Text(record.invoiceNumber ?? "Invoice")
                Text(record.dueDate, style: .date)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing) {
                Text(formatCurrency(record.amount))
                Text(record.status.capitalized)
                    .font(.caption)
                    .foregroundStyle(record.status == "overdue" ? .red : .green)
            }
        }
    }

    Button { activeSheet = .addPayment } label: {
        Label("Record Payment", systemImage: "dollarsign.circle")
    }
}
```

**People Dashboard (44A — add overdue alerts):**

```swift
// In IOSPeopleDashboardPage, when payment tracking is enabled:
if paymentTrackingEnabled && !overdueCustomers.isEmpty {
    Section {
        ForEach(overdueCustomers) { alert in
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                VStack(alignment: .leading) {
                    Text(alert.customerName).font(.headline)
                    Text("\(alert.overdueDays) days overdue")
                        .font(.caption).foregroundStyle(.red)
                }
                Spacer()
                Text(formatCurrency(alert.overdueAmount))
                    .font(.headline).foregroundStyle(.red)
            }
        }
    } header: {
        Text("Payment Alerts")
    }
}
```

### Step 6: Update ConflictResolver

Add `payment_records` to the whitelist.

## Important Notes
- Payment tracking is OFF by default — must be explicitly enabled in Settings
- When disabled, NO payment-related UI appears anywhere
- The green-to-red bar: green (90%+ paid), yellow (50-90%), red (<50%)
- Auto payment hold (optional): automatically puts jobs on hold when customer is overdue
- Payment records are per-invoice, not per-payment (a single invoice can have partial payments)
- This is simple AR tracking — NOT full accounting software

## Success Criteria
- [ ] Migration creates payment_records table
- [ ] Settings toggle for payment tracking enable/disable
- [ ] PaymentStatusBar component (green-to-red gradient)
- [ ] Customer detail: payment history, record payment
- [ ] People dashboard: overdue alerts (when enabled)
- [ ] Default payment terms, overdue warning, auto-hold settings
- [ ] ConflictResolver updated
- [ ] No payment UI when feature is disabled
- [ ] Project builds with no errors

## Log Entry
```
## Prompt 44F Results (YYYY-MM-DD)
- Migration: payment_records table
- Settings: enable/disable toggle, terms, warning days
- PaymentStatusBar component
- Customer detail + dashboard integration
- Build: PASS/FAIL
```

**Wait for user confirmation before proceeding.**

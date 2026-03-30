# 44C — Customer Detail Page Full Rebuild

> **Chain position:** **44C** (requires 39A for hat permissions)
> **Prerequisite:** 39A (permission audit — view_job_financials permission)
> **Log file:** `xcode-ai/prompt-results-log.md`

## MANDATORY RULES
1. DO NOT use `import GRDB` in UI files
2. DO NOT use empty `catch { }` blocks
3. DO NOT use `#if os(iOS)` guards

## Instructions

**IMPORTANT:** Before implementing, read `IOSCustomerDetailPage.swift` and `PeopleService.swift`. Rebuild the customer detail page with full sections for contacts, billing, job history, communication history, documents, and lifetime stats.

## Context

The current customer detail page is minimal. For a construction business, customer records need: multiple contacts per customer (owner, site contact, billing contact), business info, billing/payment tracking (hat-gated behind `view_job_financials`), complete job history, communication log, and lifetime stats (total revenue, jobs completed, average job size).

## Task

### Step 1: Service Methods

```swift
// In PeopleService:

struct CustomerDetail: Sendable {
    let customer: Customer
    let contacts: [Contact]
    let jobHistory: [JobSummary]
    let stats: CustomerStats
    let communicationLog: [CommunicationEntry]
}

struct CustomerStats: Sendable {
    let totalJobs: Int
    let activeJobs: Int
    let completedJobs: Int
    let totalRevenue: Double?  // nil if no financial permission
    let averageJobSize: Double?
    let firstJobDate: Date?
    let lastJobDate: Date?
}

struct CommunicationEntry: Identifiable, Sendable {
    let id: Int64
    let type: String  // "note", "call", "email", "meeting"
    let content: String
    let createdBy: String
    let createdAt: Date
}

func getCustomerDetail(customerId: Int64, includeFinancials: Bool) async throws -> CustomerDetail
func getCustomerContacts(customerId: Int64) async throws -> [Contact]
func addCommunicationEntry(customerId: Int64, type: String, content: String, createdBy: Int64) async throws
func getCustomerStats(customerId: Int64, includeFinancials: Bool) async throws -> CustomerStats
```

### Step 2: Rebuild IOSCustomerDetailPage.swift

```swift
List {
    // Contact Info
    Section {
        if let phone = customer.phone {
            LabeledContent("Phone", value: phone)
        }
        if let email = customer.email {
            LabeledContent("Email", value: email)
        }
        if let address = customer.address {
            LabeledContent("Address", value: address)
        }
    } header: {
        Text("Contact Info")
    }

    // Additional Contacts
    Section {
        ForEach(detail.contacts) { contact in
            VStack(alignment: .leading) {
                HStack {
                    Text(contact.name).font(.headline)
                    Text(contact.role ?? "Contact")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let phone = contact.phone {
                    Text(phone).font(.caption)
                }
            }
        }
        Button { activeSheet = .addContact } label: {
            Label("Add Contact", systemImage: "person.badge.plus")
        }
    } header: {
        Text("Additional Contacts")
    }

    // Business Info
    Section {
        if let company = customer.company {
            LabeledContent("Company", value: company)
        }
        if let type = customer.customerType {
            LabeledContent("Type", value: type)
        }
    } header: {
        Text("Business Info")
    }

    // Billing & Payment (hat-gated)
    if appCore.hasPermission("view_job_financials") {
        Section {
            if let stats = detail.stats, let revenue = stats.totalRevenue {
                LabeledContent("Total Revenue", value: formatCurrency(revenue))
                if let avg = stats.averageJobSize {
                    LabeledContent("Avg Job Size", value: formatCurrency(avg))
                }
            }
            // Payment status bar (green to red) — when enabled in settings
            if paymentTrackingEnabled {
                PaymentStatusBar(customerId: customer.id!)
            }
        } header: {
            Text("Billing & Payment")
        }
    }

    // Job History
    Section {
        if detail.jobHistory.isEmpty {
            Text("No jobs yet").foregroundStyle(.secondary)
        } else {
            ForEach(detail.jobHistory) { job in
                HStack {
                    VStack(alignment: .leading) {
                        Text(job.name).font(.headline)
                        Text(job.status.capitalized)
                            .font(.caption)
                            .foregroundStyle(statusColor(job.status))
                    }
                    Spacer()
                    if let date = job.startDate {
                        Text(date, style: .date)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    } header: {
        HStack {
            Text("Job History")
            Spacer()
            Text("\(detail.stats.totalJobs) total")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // Communication History
    Section {
        ForEach(detail.communicationLog) { entry in
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Image(systemName: commIcon(entry.type))
                        .foregroundStyle(.blue)
                    Text(entry.type.capitalized)
                        .font(.caption).bold()
                    Spacer()
                    Text(entry.createdAt, style: .relative)
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Text(entry.content)
                    .font(.caption)
                Text("by \(entry.createdBy)")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        Button { activeSheet = .addNote } label: {
            Label("Add Note", systemImage: "square.and.pencil")
        }
    } header: {
        Text("Communication History")
    }

    // Documents
    Section {
        Text("Contracts, proposals, and documents")
            .foregroundStyle(.secondary)
    } header: {
        Text("Documents")
    }

    // Lifetime Stats
    Section {
        LabeledContent("Total Jobs", value: "\(detail.stats.totalJobs)")
        LabeledContent("Active", value: "\(detail.stats.activeJobs)")
        LabeledContent("Completed", value: "\(detail.stats.completedJobs)")
        if let first = detail.stats.firstJobDate {
            LabeledContent("Customer Since", value: first, format: .dateTime.month().year())
        }
    } header: {
        Text("Lifetime Stats")
    }
}
```

## Important Notes
- Billing section ONLY visible with `view_job_financials` permission (from 39A)
- Additional contacts link to the People/Contacts system
- Communication log is a simple notes system (type + content + timestamp)
- Payment tracking is controlled by a company-wide setting (see 44F)
- Stats with financial data only populated when user has permission
- Job history should link to job detail pages

## Success Criteria
- [ ] Customer detail shows all sections: contact, additional contacts, business, billing, job history, communication, documents, stats
- [ ] Billing section hat-gated behind view_job_financials
- [ ] Multiple contacts per customer
- [ ] Communication history with add note
- [ ] Job history with status colors
- [ ] Lifetime stats (total jobs, active, completed, customer since)
- [ ] All errors show in UI
- [ ] Project builds with no errors

## Log Entry
```
## Prompt 44C Results (YYYY-MM-DD)
- IOSCustomerDetailPage rebuilt with X sections
- PeopleService: X methods for customer detail
- Billing hat-gated behind view_job_financials
- Build: PASS/FAIL
```

**Wait for user confirmation before proceeding.**
